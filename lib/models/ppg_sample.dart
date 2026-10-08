/// PulseGuard — Raw PPG Frame Sample Model
///
/// Encapsulates a single photoplethysmography (PPG) sample captured from
/// an individual camera frame during real-time biometric acquisition.
library;

/// Represents a single time-stamped raw PPG frame sample extracted
/// from the mobile device's camera stream.
///
/// Contains the extracted red and green channel intensities along with
/// the finger contact classification flag.
class PpgFrameSample {
  /// Timestamp of the captured frame in microseconds since Unix epoch.
  ///
  /// Preferred for high-frequency signal processing and filtering where
  /// integer microsecond deltas avoid floating-point drift.
  final int timestampMicros;

  /// High-level [DateTime] representation derived from [timestampMicros].
  final DateTime timestamp;

  /// Mean red channel intensity extracted from the region of interest (0.0 to 255.0).
  ///
  /// In camera-based PPG, red light undergoes minimal tissue absorption,
  /// modulated primarily by pulsatile arterial blood volume changes.
  final double redValue;

  /// Mean green channel intensity extracted from the region of interest (0.0 to 255.0).
  ///
  /// Green light is strongly absorbed by oxyhemoglobin and provides a
  /// high-contrast reference signal for motion artifact cancellation.
  final double greenValue;

  /// Flag indicating whether a finger covering the camera lens and torch
  /// was positively detected during this frame.
  final bool isFingerPresent;

  /// Constructs a [PpgFrameSample].
  ///
  /// If [timestamp] is omitted, it is automatically computed from [timestampMicros].
  PpgFrameSample({
    required this.timestampMicros,
    DateTime? timestamp,
    required this.redValue,
    required this.greenValue,
    required this.isFingerPresent,
  }) : timestamp =
            timestamp ?? DateTime.fromMicrosecondsSinceEpoch(timestampMicros);

  /// Convenience factory creating a sample stamped with the current time.
  factory PpgFrameSample.now({
    required double redValue,
    required double greenValue,
    required bool isFingerPresent,
  }) {
    final now = DateTime.now();
    return PpgFrameSample(
      timestampMicros: now.microsecondsSinceEpoch,
      timestamp: now,
      redValue: redValue,
      greenValue: greenValue,
      isFingerPresent: isFingerPresent,
    );
  }

  /// Deserialises a [PpgFrameSample] from a map.
  factory PpgFrameSample.fromMap(Map<String, dynamic> map) {
    final micros = map['timestamp_micros'] as int? ??
        (map['timestamp'] is int
            ? map['timestamp'] as int
            : DateTime.parse(map['timestamp'] as String).microsecondsSinceEpoch);

    return PpgFrameSample(
      timestampMicros: micros,
      timestamp: map['timestamp'] is String
          ? DateTime.parse(map['timestamp'] as String)
          : DateTime.fromMicrosecondsSinceEpoch(micros),
      redValue: (map['red_value'] as num).toDouble(),
      greenValue: (map['green_value'] as num).toDouble(),
      isFingerPresent: map['is_finger_present'] == 1 ||
          map['is_finger_present'] == true,
    );
  }

  /// Serialises this sample into a key-value map.
  Map<String, dynamic> toMap() {
    return {
      'timestamp_micros': timestampMicros,
      'timestamp': timestamp.toIso8601String(),
      'red_value': redValue,
      'green_value': greenValue,
      'is_finger_present': isFingerPresent ? 1 : 0,
    };
  }

  /// Returns a new [PpgFrameSample] with updated fields.
  PpgFrameSample copyWith({
    int? timestampMicros,
    DateTime? timestamp,
    double? redValue,
    double? greenValue,
    bool? isFingerPresent,
  }) {
    final resolvedMicros = timestampMicros ??
        (timestamp != null ? timestamp.microsecondsSinceEpoch : this.timestampMicros);
    return PpgFrameSample(
      timestampMicros: resolvedMicros,
      timestamp: timestamp ?? (timestampMicros != null
          ? DateTime.fromMicrosecondsSinceEpoch(timestampMicros)
          : this.timestamp),
      redValue: redValue ?? this.redValue,
      greenValue: greenValue ?? this.greenValue,
      isFingerPresent: isFingerPresent ?? this.isFingerPresent,
    );
  }

  @override
  String toString() =>
      'PpgFrameSample(t: ${timestamp.toIso8601String()}, R: ${redValue.toStringAsFixed(2)}, G: ${greenValue.toStringAsFixed(2)}, finger: $isFingerPresent)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PpgFrameSample &&
          runtimeType == other.runtimeType &&
          timestampMicros == other.timestampMicros &&
          redValue == other.redValue &&
          greenValue == other.greenValue &&
          isFingerPresent == other.isFingerPresent;

  @override
  int get hashCode => Object.hash(
        timestampMicros,
        redValue,
        greenValue,
        isFingerPresent,
      );
}
