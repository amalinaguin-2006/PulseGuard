// lib/controllers/history_controller.dart
//
// Pulse Guard - Phase 5: reading history, personal baselines and export.
//
// Loads stored readings (summary columns only, no raw traces) and the user
// profile through DatabaseService, keeps them in memory (newest first) and
// derives everything the history and trend screens need:
//   * range and quality filtering
//   * summary statistics for the filtered set
//   * daily trend points including a rolling 7-day RMSSD average
//   * PersonalBaseline: resting BPM, RMSSD and stress, plus the 7-day RMSSD
//     average and its change versus the previous 7 days
//   * delete / clear, profile saving, CSV and JSON export
//
// Typical wiring with the measurement controller:
//   final history = HistoryController();
//   final measurement = MeasurementController(
//     onReadingSaved: (id, reading) => history.registerSavedReading(reading),
//   );
//   await history.load();
//   measurement.start(baselineRmssdMs: history.preferredBaselineRmssd);

import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/ppg_reading.dart';
import '../models/user_profile.dart';
import '../services/database_service.dart';

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Time range for the filtered history view.
enum HistoryRange { all, today, last7Days, last30Days, custom }

/// Aggregate figures for a set of readings.
class HistorySummary {
  const HistorySummary({
    required this.count,
    required this.averageBpm,
    required this.minBpm,
    required this.maxBpm,
    required this.averageRmssd,
    required this.averageStress,
    required this.averageSignalQuality,
  });

  final int count;
  final double averageBpm;
  final double minBpm;
  final double maxBpm;
  final double averageRmssd;
  final double averageStress;

  /// Mean signal quality in percent (0-100).
  final double averageSignalQuality;
}

/// The user's personal reference values, from their own good-quality
/// readings.
class PersonalBaseline {
  const PersonalBaseline({
    required this.restingBpm,
    required this.restingRmssd,
    required this.baselineStress,
    required this.readingCount,
    required this.windowDays,
    required this.rmssd7DayAverage,
    required this.rmssd7DayCount,
    required this.previousRmssd7DayAverage,
    required this.rmssdTrendPercent,
  });

  /// Average resting heart rate (outlier-robust mean), in BPM.
  final double restingBpm;

  /// Average resting RMSSD in milliseconds.
  final double restingRmssd;

  /// Average stress index (0-100) at rest.
  final double baselineStress;

  /// Good-quality readings behind the three values above.
  final int readingCount;

  /// Length of the baseline window in days.
  final int windowDays;

  /// Mean RMSSD over the last 7 days (null if no good readings).
  final double? rmssd7DayAverage;

  /// Readings behind [rmssd7DayAverage].
  final int rmssd7DayCount;

  /// Mean RMSSD over the 7 days before that (null if none).
  final double? previousRmssd7DayAverage;

  /// Percentage change of the 7-day RMSSD average versus the previous 7 days
  /// (positive = HRV rising). Null when either side is missing.
  final double? rmssdTrendPercent;
}

/// One day of the trend chart.
class DailyTrendPoint {
  const DailyTrendPoint({
    required this.day,
    required this.count,
    required this.averageBpm,
    required this.averageRmssd,
    required this.averageStress,
    required this.rolling7DayRmssd,
  });

  /// Local calendar day (midnight).
  final DateTime day;
  final int count;
  final double averageBpm;
  final double averageRmssd;
  final double averageStress;

  /// Mean RMSSD of all readings in this day and the six days before it
  /// (within the currently filtered set).
  final double rolling7DayRmssd;
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

class HistoryController extends ChangeNotifier {
  HistoryController({
    DatabaseService? database,
    this.maxReadings = 1000,
    this.baselineWindowDays = 30,
    this.baselineMinQuality = 60.0,
    this.minReadingsForBaseline = 3,
    DateTime Function()? now,
  })  : assert(maxReadings > 0),
        assert(baselineWindowDays > 0),
        assert(minReadingsForBaseline > 0),
        _database = database ?? DatabaseService.instance,
        _now = now ?? DateTime.now;

  /// Most recent readings kept in memory.
  final int maxReadings;

  /// Days of history used for the resting baseline.
  final int baselineWindowDays;

  /// Minimum signal quality (percent) for a reading to count toward baselines.
  final double baselineMinQuality;

  /// Good readings required before a baseline is produced.
  final int minReadingsForBaseline;

  final DatabaseService _database;
  final DateTime Function() _now;

  // Data.
  List<PpgReading> _readings = <PpgReading>[];
  UserProfile? _profile;
  PersonalBaseline? _baseline;

  // Filter.
  HistoryRange _range = HistoryRange.all;
  DateTime? _customStart;
  DateTime? _customEnd;
  double _minSignalQuality = 0.0;

  // Derived caches (cleared by _invalidate).
  List<PpgReading>? _filteredCache;
  HistorySummary? _summaryCache;
  bool _summaryCached = false;
  List<DailyTrendPoint>? _trendCache;

  // Status.
  bool _loading = false;
  String? _errorMessage;
  int _loadGeneration = 0;
  bool _disposed = false;

  // -------------------------------------------------------------------------
  // Read-only state
  // -------------------------------------------------------------------------

  bool get isLoading => _loading;

  /// Last error from a database operation, or null.
  String? get errorMessage => _errorMessage;

  UserProfile? get profile => _profile;

  PersonalBaseline? get baseline => _baseline;

  /// Resting RMSSD to pass to `MeasurementController.start`: the computed
  /// baseline when available, otherwise the value stored in the profile.
  double? get preferredBaselineRmssd {
    final computed = _baseline?.restingRmssd;
    if (computed != null && computed > 0) return computed;
    final stored = _profile?.baselineHrv;
    return (stored != null && stored > 0) ? stored : null;
  }

  HistoryRange get range => _range;
  DateTime? get customStart => _customStart;
  DateTime? get customEnd => _customEnd;

  /// Minimum signal quality (percent) of readings shown.
  double get minSignalQuality => _minSignalQuality;

  /// Total readings held in memory, ignoring filters.
  int get totalCount => _readings.length;

  /// Readings matching the current filter, newest first.
  List<PpgReading> get readings => UnmodifiableListView<PpgReading>(_filtered());

  /// Statistics of the filtered readings, or null when there are none.
  HistorySummary? get summary {
    if (_summaryCached) return _summaryCache;
    _summaryCache = _buildSummary(_filtered());
    _summaryCached = true;
    return _summaryCache;
  }

  /// Per-day averages of the filtered readings (oldest first) with a rolling
  /// 7-day RMSSD, ready for a trend chart.
  List<DailyTrendPoint> get dailyTrend {
    final cached = _trendCache;
    if (cached != null) return cached;
    final built = _buildTrend(_filtered());
    _trendCache = built;
    return built;
  }

  // -------------------------------------------------------------------------
  // Loading
  // -------------------------------------------------------------------------

  /// Loads the latest readings and the profile. Safe to call repeatedly; only
  /// the most recent call applies its result.
  Future<void> load() async {
    if (_disposed) return;
    final generation = ++_loadGeneration;
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final readings = await _database.fetchRecentReadings(limit: maxReadings);
      final profile = await _database.fetchCurrentProfile();
      if (_disposed || generation != _loadGeneration) return;
      _readings = readings;
      _profile = profile;
      _invalidate();
      _recomputeBaseline();
    } catch (e) {
      if (_disposed || generation != _loadGeneration) return;
      _errorMessage = e.toString();
    } finally {
      if (!_disposed && generation == _loadGeneration) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Adds a freshly saved reading without reloading from the database (use as
  /// `MeasurementController.onReadingSaved`).
  void registerSavedReading(PpgReading reading) {
    if (_disposed) return;
    final id = reading.id;
    if (id != null && _readings.any((PpgReading r) => r.id == id)) return;

    // Keep list entries light: drop any raw trace.
    final summaryCopy = PpgReading(
      id: id,
      timestamp: reading.timestamp,
      bpm: reading.bpm,
      rmssd: reading.rmssd,
      stressIndex: reading.stressIndex,
      signalQuality: reading.signalQuality,
    );
    final updated = List<PpgReading>.of(_readings)
      ..add(summaryCopy)
      ..sort((PpgReading a, PpgReading b) => b.timestamp.compareTo(a.timestamp));
    if (updated.length > maxReadings) {
      updated.removeRange(maxReadings, updated.length);
    }
    _readings = updated;
    _invalidate();
    _recomputeBaseline();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Filtering
  // -------------------------------------------------------------------------

  /// Selects the time range. For [HistoryRange.custom] pass [customStart]
  /// and/or [customEnd] (both inclusive; either may be null for open-ended).
  void setRange(
    HistoryRange range, {
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    _range = range;
    _customStart = range == HistoryRange.custom ? customStart : null;
    _customEnd = range == HistoryRange.custom ? customEnd : null;
    _invalidate();
    notifyListeners();
  }

  /// Hides readings below [percent] signal quality (0-100).
  void setMinSignalQuality(double percent) {
    _minSignalQuality = math.max(0.0, math.min(100.0, percent));
    _invalidate();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Mutations
  // -------------------------------------------------------------------------

  /// Deletes one reading. Returns true if it existed.
  Future<bool> deleteReading(int id) async {
    try {
      final rowsDeleted = await _database.deleteReading(id);
      if (_disposed) return rowsDeleted > 0;
      if (rowsDeleted > 0) {
        _readings = _readings.where((PpgReading r) => r.id != id).toList();
        _invalidate();
        _recomputeBaseline();
      }
      _errorMessage = null;
      notifyListeners();
      return rowsDeleted > 0;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Deletes all readings (the profile is kept). Returns how many rows were
  /// removed, or -1 if the database operation failed.
  Future<int> clearAll() async {
    try {
      final removed = await _database.clearAllReadings();
      if (_disposed) return removed;
      _readings = <PpgReading>[];
      _invalidate();
      _recomputeBaseline();
      _errorMessage = null;
      notifyListeners();
      return removed;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return -1;
    }
  }

  /// Inserts the profile (no id yet) or updates it (id set). Returns true on
  /// success.
  Future<bool> saveProfile(UserProfile profile) async {
    try {
      if (profile.id == null) {
        final id = await _database.insertUserProfile(profile);
        _profile = profile.copyWith(id: id);
      } else {
        final updated = await _database.updateUserProfile(profile);
        if (updated <= 0) {
          _errorMessage = 'Profile ${profile.id} no longer exists.';
          notifyListeners();
          return false;
        }
        _profile = profile;
      }
      _errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Export
  // -------------------------------------------------------------------------

  /// CSV string containing the readings (oldest first).
  String exportCsv({bool filteredOnly = true}) {
    final source = filteredOnly ? _filtered() : _readings;
    final buffer = StringBuffer()
      ..write('id,timestamp_utc,bpm,rmssd_ms,stress_index,signal_quality_pct\n');
    for (final reading in source.reversed) {
      buffer
        ..write(reading.id ?? '')
        ..write(',')
        ..write(reading.dateTime.toUtc().toIso8601String())
        ..write(',')
        ..write(reading.bpm.toStringAsFixed(1))
        ..write(',')
        ..write(reading.rmssd.toStringAsFixed(1))
        ..write(',')
        ..write(reading.stressIndex.toStringAsFixed(1))
        ..write(',')
        ..write(reading.signalQuality.toStringAsFixed(0))
        ..write('\n');
    }
    return buffer.toString();
  }

  /// Pretty-printed JSON with the active filter, summary, baseline and the
  /// readings (oldest first).
  String exportSummaryJson({bool filteredOnly = true}) {
    final source = filteredOnly ? _filtered() : _readings;
    final stats = _buildSummary(source);
    final baseline = _baseline;
    final map = <String, Object?>{
      'generatedAtUtc': _now().toUtc().toIso8601String(),
      'filter': filteredOnly
          ? <String, Object?>{
              'range': _range.name,
              'customStartUtc': _customStart?.toUtc().toIso8601String(),
              'customEndUtc': _customEnd?.toUtc().toIso8601String(),
              'minSignalQualityPct': _minSignalQuality,
            }
          : null,
      'summary': stats == null
          ? null
          : <String, Object?>{
              'count': stats.count,
              'averageBpm': _round(stats.averageBpm, 1),
              'minBpm': _round(stats.minBpm, 1),
              'maxBpm': _round(stats.maxBpm, 1),
              'averageRmssdMs': _round(stats.averageRmssd, 1),
              'averageStressIndex': _round(stats.averageStress, 1),
              'averageSignalQualityPct': _round(stats.averageSignalQuality, 0),
            },
      'baseline': baseline == null
          ? null
          : <String, Object?>{
              'restingBpm': _round(baseline.restingBpm, 1),
              'restingRmssdMs': _round(baseline.restingRmssd, 1),
              'baselineStressIndex': _round(baseline.baselineStress, 1),
              'readingCount': baseline.readingCount,
              'windowDays': baseline.windowDays,
              'rmssd7DayAverageMs': _roundOrNull(baseline.rmssd7DayAverage, 1),
              'rmssdTrendPercent': _roundOrNull(baseline.rmssdTrendPercent, 1),
            },
      'readings': source.reversed
          .map(
            (PpgReading r) => <String, Object?>{
              'id': r.id,
              'timestampUtc': r.dateTime.toUtc().toIso8601String(),
              'bpm': _round(r.bpm, 1),
              'rmssdMs': _round(r.rmssd, 1),
              'stressIndex': _round(r.stressIndex, 1),
              'signalQualityPct': _round(r.signalQuality, 0),
            },
          )
          .toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Writes the CSV export into [directory] (created if missing) and returns
  /// the file. Throws [FileSystemException] if writing fails.
  Future<File> exportCsvToFile(
    Directory directory, {
    bool filteredOnly = true,
  }) async {
    await directory.create(recursive: true);
    final stamp = _fileStamp(_now());
    final file = File('${directory.path}/pulse_guard_history_$stamp.csv');
    return file.writeAsString(exportCsv(filteredOnly: filteredOnly), flush: true);
  }

  // -------------------------------------------------------------------------
  // Derived data
  // -------------------------------------------------------------------------

  void _invalidate() {
    _filteredCache = null;
    _summaryCache = null;
    _summaryCached = false;
    _trendCache = null;
  }

  List<PpgReading> _filtered() {
    final cached = _filteredCache;
    if (cached != null) return cached;

    final now = _now();
    DateTime? start;
    DateTime? end;
    switch (_range) {
      case HistoryRange.all:
        break;
      case HistoryRange.today:
        final local = now.toLocal();
        start = DateTime(local.year, local.month, local.day);
        break;
      case HistoryRange.last7Days:
        start = now.subtract(const Duration(days: 7));
        break;
      case HistoryRange.last30Days:
        start = now.subtract(const Duration(days: 30));
        break;
      case HistoryRange.custom:
        start = _customStart;
        end = _customEnd;
        break;
    }

    final DateTime? rangeStart = start;
    final DateTime? rangeEnd = end;
    final minQuality = _minSignalQuality;
    final result = _readings.where((PpgReading r) {
      if (rangeStart != null && r.dateTime.isBefore(rangeStart)) return false;
      if (rangeEnd != null && r.dateTime.isAfter(rangeEnd)) return false;
      return r.signalQuality >= minQuality;
    }).toList(growable: false);
    _filteredCache = result;
    return result;
  }

  HistorySummary? _buildSummary(List<PpgReading> source) {
    if (source.isEmpty) return null;
    var bpmSum = 0.0;
    var rmssdSum = 0.0;
    var stressSum = 0.0;
    var qualitySum = 0.0;
    var minBpm = source.first.bpm;
    var maxBpm = source.first.bpm;
    for (final r in source) {
      bpmSum += r.bpm;
      rmssdSum += r.rmssd;
      stressSum += r.stressIndex;
      qualitySum += r.signalQuality;
      minBpm = math.min(minBpm, r.bpm);
      maxBpm = math.max(maxBpm, r.bpm);
    }
    final n = source.length;
    return HistorySummary(
      count: n,
      averageBpm: bpmSum / n,
      minBpm: minBpm,
      maxBpm: maxBpm,
      averageRmssd: rmssdSum / n,
      averageStress: stressSum / n,
      averageSignalQuality: qualitySum / n,
    );
  }

  List<DailyTrendPoint> _buildTrend(List<PpgReading> source) {
    final byDay = <int, List<PpgReading>>{};
    for (final r in source) {
      final local = r.dateTime.toLocal();
      final key = _dayKey(local.year, local.month, local.day);
      (byDay[key] ??= <PpgReading>[]).add(r);
    }

    final keys = byDay.keys.toList()..sort();
    final points = <DailyTrendPoint>[];
    for (final key in keys) {
      final dayReadings = byDay[key] ?? const <PpgReading>[];
      if (dayReadings.isEmpty) continue;
      final day = DateTime(key ~/ 10000, (key ~/ 100) % 100, key % 100);

      var bpmSum = 0.0;
      var rmssdSum = 0.0;
      var stressSum = 0.0;
      for (final r in dayReadings) {
        bpmSum += r.bpm;
        rmssdSum += r.rmssd;
        stressSum += r.stressIndex;
      }

      // Rolling window: this day and the six days before it.
      var windowSum = 0.0;
      var windowCount = 0;
      for (var back = 0; back < 7; back++) {
        final d = DateTime(day.year, day.month, day.day - back);
        final list = byDay[_dayKey(d.year, d.month, d.day)];
        if (list == null) continue;
        for (final r in list) {
          windowSum += r.rmssd;
          windowCount++;
        }
      }

      final n = dayReadings.length;
      points.add(
        DailyTrendPoint(
          day: day,
          count: n,
          averageBpm: bpmSum / n,
          averageRmssd: rmssdSum / n,
          averageStress: stressSum / n,
          rolling7DayRmssd: windowCount == 0 ? rmssdSum / n : windowSum / windowCount,
        ),
      );
    }
    return points;
  }

  void _recomputeBaseline() {
    final now = _now();
    final good = _readings
        .where((PpgReading r) => r.signalQuality >= baselineMinQuality)
        .toList();

    final windowStart = now.subtract(Duration(days: baselineWindowDays));
    final inWindow =
        good.where((PpgReading r) => !r.dateTime.isBefore(windowStart)).toList();
    if (inWindow.length < minReadingsForBaseline) {
      _baseline = null;
      return;
    }

    final sevenStart = now.subtract(const Duration(days: 7));
    final fourteenStart = now.subtract(const Duration(days: 14));
    final recent = good
        .where((PpgReading r) => !r.dateTime.isBefore(sevenStart))
        .map((PpgReading r) => r.rmssd)
        .toList();
    final previous = good
        .where(
          (PpgReading r) =>
              !r.dateTime.isBefore(fourteenStart) &&
              r.dateTime.isBefore(sevenStart),
        )
        .map((PpgReading r) => r.rmssd)
        .toList();

    final recentAverage = recent.isEmpty ? null : _mean(recent);
    final previousAverage = previous.isEmpty ? null : _mean(previous);
    double? trend;
    if (recentAverage != null && previousAverage != null && previousAverage > 0) {
      trend = (recentAverage - previousAverage) / previousAverage * 100.0;
    }

    _baseline = PersonalBaseline(
      restingBpm: _robustMean(inWindow.map((PpgReading r) => r.bpm).toList()),
      restingRmssd:
          _robustMean(inWindow.map((PpgReading r) => r.rmssd).toList()),
      baselineStress:
          _robustMean(inWindow.map((PpgReading r) => r.stressIndex).toList()),
      readingCount: inWindow.length,
      windowDays: baselineWindowDays,
      rmssd7DayAverage: recentAverage,
      rmssd7DayCount: recent.length,
      previousRmssd7DayAverage: previousAverage,
      rmssdTrendPercent: trend,
    );
  }

  // -------------------------------------------------------------------------
  // Small helpers
  // -------------------------------------------------------------------------

  static int _dayKey(int year, int month, int day) =>
      year * 10000 + month * 100 + day;

  static double _mean(List<double> values) {
    var sum = 0.0;
    for (final v in values) {
      sum += v;
    }
    return sum / values.length;
  }

  static double _median(List<double> sorted) {
    final mid = sorted.length >> 1;
    return sorted.length.isOdd
        ? sorted[mid]
        : 0.5 * (sorted[mid - 1] + sorted[mid]);
  }

  /// Mean after discarding values more than 3 robust standard deviations
  /// (MAD-based) from the median, so one bad reading cannot skew a baseline.
  static double _robustMean(List<double> values) {
    if (values.length < 4) return _mean(values);
    final sorted = List<double>.of(values)..sort();
    final median = _median(sorted);
    final deviations = sorted.map((double v) => (v - median).abs()).toList()
      ..sort();
    final mad = _median(deviations) * 1.4826;
    if (mad <= 1e-9) return _mean(values);
    final kept =
        values.where((double v) => (v - median).abs() <= 3.0 * mad).toList();
    return kept.isEmpty ? _mean(values) : _mean(kept);
  }

  static double _round(double value, int digits) =>
      double.parse(value.toStringAsFixed(digits));

  static double? _roundOrNull(double? value, int digits) =>
      value == null ? null : _round(value, digits);

  static String _fileStamp(DateTime time) {
    final t = time.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  // -------------------------------------------------------------------------
  // Framework hooks
  // -------------------------------------------------------------------------

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _loadGeneration++;
    super.dispose();
  }
}
