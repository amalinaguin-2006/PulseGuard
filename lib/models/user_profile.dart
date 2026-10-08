/// PulseGuard — User Profile Data Model
///
/// Represents a single user profile with baseline biometric calibration
/// values.  Stored in the `user_profiles` SQLite table.
///
/// Design notes:
///   • [id] is an auto-incrementing primary key assigned by SQLite.
///   • [baselineBpm] and [baselineHrv] are populated after the initial
///     calibration session and used as reference points for stress scoring.
///   • [createdAt] is persisted as an ISO-8601 string for portability
///     across platforms and time-zone safety.
library;

class UserProfile {
  /// SQLite auto-increment primary key (`NULL` on insert → assigned by DB).
  final int? id;

  /// User's display name.
  final String name;

  /// User's age in years (used for age-adjusted HRV normative ranges).
  final int age;

  /// Gender identifier — e.g. `'male'`, `'female'`, `'other'`.
  final String gender;

  /// Resting baseline heart rate in beats-per-minute, established during
  /// the initial calibration session.  `null` until calibration completes.
  final double? baselineBpm;

  /// Resting baseline heart-rate variability (RMSSD in ms), established
  /// during calibration.  `null` until calibration completes.
  final double? baselineHrv;

  /// ISO-8601 timestamp of when this profile was created.
  final String createdAt;

  const UserProfile({
    this.id,
    required this.name,
    required this.age,
    required this.gender,
    this.baselineBpm,
    this.baselineHrv,
    required this.createdAt,
  });

  // ── Serialisation ──────────────────────────────────────────────────────

  /// Constructs a [UserProfile] from a SQLite row map.
  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as int?,
      name: map['name'] as String,
      age: map['age'] as int,
      gender: map['gender'] as String,
      baselineBpm: map['baseline_bpm'] != null
          ? (map['baseline_bpm'] as num).toDouble()
          : null,
      baselineHrv: map['baseline_hrv'] != null
          ? (map['baseline_hrv'] as num).toDouble()
          : null,
      createdAt: map['created_at'] as String,
    );
  }

  /// Serialises this profile into a map suitable for SQLite insertion.
  ///
  /// [id] is deliberately omitted so SQLite assigns the auto-increment key.
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'age': age,
      'gender': gender,
      'baseline_bpm': baselineBpm,
      'baseline_hrv': baselineHrv,
      'created_at': createdAt,
    };
  }

  // ── Copy-With ──────────────────────────────────────────────────────────

  /// Returns a shallow copy of this profile with the specified fields
  /// replaced.  Useful for updating baseline values after calibration.
  UserProfile copyWith({
    int? id,
    String? name,
    int? age,
    String? gender,
    double? baselineBpm,
    double? baselineHrv,
    String? createdAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      baselineBpm: baselineBpm ?? this.baselineBpm,
      baselineHrv: baselineHrv ?? this.baselineHrv,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // ── Debug ──────────────────────────────────────────────────────────────

  @override
  String toString() {
    return 'UserProfile(id: $id, name: $name, age: $age, gender: $gender, '
        'baselineBpm: $baselineBpm, baselineHrv: $baselineHrv, '
        'createdAt: $createdAt)';
  }
}
