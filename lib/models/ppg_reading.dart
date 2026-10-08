/// PulseGuard — PPG Reading Data Model
///
/// Represents a single photoplethysmography measurement captured from
/// the rear camera + torch pipeline.  Stored in the `ppg_readings`
/// SQLite table with an index on [timestamp] for fast range queries.
///
/// Field semantics:
///   • [bpm]           — Instantaneous heart rate (beats per minute).
///   • [rmssd]         — Root-mean-square of successive R-R interval
///                       differences (ms).  Primary HRV metric.
///   • [stressIndex]   — Derived 0-100 score mapping autonomic balance
///                       to a human-readable stress level.
///   • [signalQuality] — Confidence percentage (0.0–100.0) indicating
///                       how clean the PPG waveform was during capture.
///   • [rawPpgData]    — Optional JSON-encoded array of raw trace points
///                       for offline replay / advanced analysis.
library;

class PpgReading {
  /// SQLite auto-increment primary key (`null` on insert).
  final int? id;

  /// ISO-8601 timestamp of when this reading was captured.
  final String timestamp;

  /// Parsed [DateTime] representation of [timestamp].
  DateTime get dateTime =>
      DateTime.tryParse(timestamp) ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// Instantaneous heart rate in beats per minute.
  final double bpm;

  /// Root-mean-square of successive R-R interval differences (ms).
  final double rmssd;

  /// Derived stress score on a 0–100 scale.
  final double stressIndex;

  /// Signal confidence percentage (0.0–100.0).
  final double signalQuality;

  /// Optional JSON string encoding the raw PPG waveform trace points.
  /// Example: `'[{"t":0,"v":128},{"t":33,"v":135}, …]'`
  final String? rawPpgData;

  const PpgReading({
    this.id,
    required this.timestamp,
    required this.bpm,
    required this.rmssd,
    required this.stressIndex,
    required this.signalQuality,
    this.rawPpgData,
  });

  // ── Serialisation ──────────────────────────────────────────────────────

  /// Constructs a [PpgReading] from a SQLite row map.
  factory PpgReading.fromMap(Map<String, dynamic> map) {
    return PpgReading(
      id: map['id'] as int?,
      timestamp: map['timestamp'] as String,
      bpm: (map['bpm'] as num).toDouble(),
      rmssd: (map['rmssd'] as num).toDouble(),
      stressIndex: (map['stress_index'] as num).toDouble(),
      signalQuality: (map['signal_quality'] as num).toDouble(),
      rawPpgData: map['raw_ppg_data'] as String?,
    );
  }

  /// Serialises this reading into a map suitable for SQLite insertion.
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'timestamp': timestamp,
      'bpm': bpm,
      'rmssd': rmssd,
      'stress_index': stressIndex,
      'signal_quality': signalQuality,
      'raw_ppg_data': rawPpgData,
    };
  }

  // ── Copy-With ──────────────────────────────────────────────────────────

  /// Returns a shallow copy with the specified fields replaced.
  PpgReading copyWith({
    int? id,
    String? timestamp,
    double? bpm,
    double? rmssd,
    double? stressIndex,
    double? signalQuality,
    String? rawPpgData,
  }) {
    return PpgReading(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      bpm: bpm ?? this.bpm,
      rmssd: rmssd ?? this.rmssd,
      stressIndex: stressIndex ?? this.stressIndex,
      signalQuality: signalQuality ?? this.signalQuality,
      rawPpgData: rawPpgData ?? this.rawPpgData,
    );
  }

  // ── Debug ──────────────────────────────────────────────────────────────

  @override
  String toString() {
    return 'PpgReading(id: $id, timestamp: $timestamp, bpm: $bpm, '
        'rmssd: $rmssd, stressIndex: $stressIndex, '
        'signalQuality: $signalQuality, '
        'rawPpgData: ${rawPpgData != null ? "[${rawPpgData!.length} chars]" : "null"})';
  }
}
