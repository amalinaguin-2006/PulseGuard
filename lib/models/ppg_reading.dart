/// PulseGuard — PPG Reading Data Model (v2)
///
/// Represents a single photoplethysmography measurement captured from
/// the rear camera + torch pipeline. Stored in the `ppg_readings`
/// SQLite table with an index on [timestamp] for fast range queries.
///
/// Field semantics:
///   • [bpm]           — Instantaneous heart rate (beats per minute).
///   • [rmssd]         — Root-mean-square of successive R-R interval differences (ms).
///   • [sdnn]          — Standard deviation of NN intervals (ms). Overall HRV power.
///   • [stressIndex]   — Derived 0-100 score mapping autonomic balance to stress level.
///   • [signalQuality] — Confidence percentage (0.0–100.0) indicating waveform purity.
///   • [rawPpgData]    — Optional JSON string encoding raw PPG waveform points.
library;

class PpgReading {
  /// SQLite auto-increment primary key (`null` on insert).
  final int? id;

  /// ISO-8601 UTC timestamp of when this reading was captured.
  final String timestamp;

  /// Parsed [DateTime] representation of [timestamp].
  DateTime get dateTime =>
      DateTime.tryParse(timestamp) ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// Instantaneous heart rate in beats per minute.
  final double bpm;

  /// Root-mean-square of successive R-R interval differences (ms).
  final double rmssd;

  /// Standard deviation of NN intervals (ms).
  final double sdnn;

  /// Derived stress score on a 0–100 scale.
  final double stressIndex;

  /// Signal confidence percentage (0.0–100.0).
  final double signalQuality;

  /// Optional JSON string encoding the raw PPG waveform trace points.
  final String? rawPpgData;

  const PpgReading({
    this.id,
    required this.timestamp,
    required this.bpm,
    required this.rmssd,
    this.sdnn = 0.0,
    required this.stressIndex,
    required this.signalQuality,
    this.rawPpgData,
  });

  // ── Serialization ─────────────────────────────────────────────────────────

  /// Constructs a [PpgReading] from a SQLite row map.
  factory PpgReading.fromMap(Map<String, dynamic> map) {
    return PpgReading(
      id: map['id'] as int?,
      timestamp: map['timestamp'] as String,
      bpm: (map['bpm'] as num).toDouble(),
      rmssd: (map['rmssd'] as num).toDouble(),
      sdnn: map['sdnn'] != null ? (map['sdnn'] as num).toDouble() : 0.0,
      stressIndex: (map['stress_index'] as num).toDouble(),
      signalQuality: (map['signal_quality'] as num).toDouble(),
      rawPpgData: map['raw_ppg_data'] as String?,
    );
  }

  /// Serializes this reading into a map suitable for SQLite insertion.
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'timestamp': timestamp,
      'bpm': bpm,
      'rmssd': rmssd,
      'sdnn': sdnn,
      'stress_index': stressIndex,
      'signal_quality': signalQuality,
      'raw_ppg_data': rawPpgData,
    };
  }

  // ── Copy-With ─────────────────────────────────────────────────────────────

  /// Returns a shallow copy with the specified fields replaced.
  PpgReading copyWith({
    int? id,
    String? timestamp,
    double? bpm,
    double? rmssd,
    double? sdnn,
    double? stressIndex,
    double? signalQuality,
    String? rawPpgData,
  }) {
    return PpgReading(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      bpm: bpm ?? this.bpm,
      rmssd: rmssd ?? this.rmssd,
      sdnn: sdnn ?? this.sdnn,
      stressIndex: stressIndex ?? this.stressIndex,
      signalQuality: signalQuality ?? this.signalQuality,
      rawPpgData: rawPpgData ?? this.rawPpgData,
    );
  }

  @override
  String toString() {
    return 'PpgReading(id: $id, timestamp: $timestamp, bpm: $bpm, '
        'rmssd: $rmssd, sdnn: $sdnn, stressIndex: $stressIndex, '
        'signalQuality: $signalQuality, '
        'rawPpgData: ${rawPpgData != null ? "[${rawPpgData!.length} chars]" : "null"})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PpgReading &&
        other.id == id &&
        other.timestamp == timestamp &&
        other.bpm == bpm &&
        other.rmssd == rmssd &&
        other.sdnn == sdnn &&
        other.stressIndex == stressIndex &&
        other.signalQuality == signalQuality &&
        other.rawPpgData == rawPpgData;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      timestamp,
      bpm,
      rmssd,
      sdnn,
      stressIndex,
      signalQuality,
      rawPpgData,
    );
  }
}
