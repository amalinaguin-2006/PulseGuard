/// PulseGuard — User Profile Data Model (v2)
///
/// Represents a user profile with personal details, health questionnaire JSON,
/// avatar path, local mock auth credentials, and baseline calibration values.
library;

class UserProfile {
  /// SQLite auto-increment primary key (`null` on insert → assigned by DB).
  final int? id;

  /// User's display or full name.
  final String name;

  /// User's age in years (calculated from DOB or manually entered).
  final int age;

  /// Gender identifier (e.g., `'Male'`, `'Female'`, `'Other'`).
  final String gender;

  /// User's registered email address for local authentication.
  final String? email;

  /// JSON string encoding questionnaire responses (DOB, height, weight, cardiac
  /// device, cardiac events, arrhythmia, chronic conditions, medications, tobacco).
  final String? healthJson;

  /// Resting baseline heart rate in BPM.
  final double? baselineBpm;

  /// Resting baseline heart-rate variability (RMSSD in ms).
  final double? baselineHrv;

  /// File path to user's selected profile picture avatar.
  final String? avatarPath;

  /// Salted SHA-256 hash for local mock authentication (one account per device).
  final String? passwordHash;

  /// Random salt used for local password hashing.
  final String? salt;

  /// ISO-8601 UTC timestamp of when this profile was created.
  final String createdAt;

  const UserProfile({
    this.id,
    required this.name,
    required this.age,
    required this.gender,
    this.email,
    this.healthJson,
    this.baselineBpm,
    this.baselineHrv,
    this.avatarPath,
    this.passwordHash,
    this.salt,
    required this.createdAt,
  });

  // ── Serialization ─────────────────────────────────────────────────────────

  /// Constructs a [UserProfile] from a SQLite row map.
  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as int?,
      name: map['name'] as String? ?? 'User',
      age: map['age'] as int? ?? 25,
      gender: map['gender'] as String? ?? 'Other',
      email: map['email'] as String?,
      healthJson: map['health_json'] as String?,
      baselineBpm: map['baseline_bpm'] != null
          ? (map['baseline_bpm'] as num).toDouble()
          : null,
      baselineHrv: map['baseline_hrv'] != null
          ? (map['baseline_hrv'] as num).toDouble()
          : null,
      avatarPath: map['avatar_path'] as String?,
      passwordHash: map['password_hash'] as String?,
      salt: map['salt'] as String?,
      createdAt: map['created_at'] as String? ??
          DateTime.now().toUtc().toIso8601String(),
    );
  }

  /// Serializes this profile into a SQLite row map.
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'age': age,
      'gender': gender,
      'email': email,
      'health_json': healthJson,
      'baseline_bpm': baselineBpm,
      'baseline_hrv': baselineHrv,
      'avatar_path': avatarPath,
      'password_hash': passwordHash,
      'salt': salt,
      'created_at': createdAt,
    };
  }

  // ── Immutability helpers ──────────────────────────────────────────────────

  /// Returns a new [UserProfile] with the given fields replaced.
  UserProfile copyWith({
    int? id,
    String? name,
    int? age,
    String? gender,
    String? email,
    String? healthJson,
    double? baselineBpm,
    double? baselineHrv,
    String? avatarPath,
    String? passwordHash,
    String? salt,
    String? createdAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      email: email ?? this.email,
      healthJson: healthJson ?? this.healthJson,
      baselineBpm: baselineBpm ?? this.baselineBpm,
      baselineHrv: baselineHrv ?? this.baselineHrv,
      avatarPath: avatarPath ?? this.avatarPath,
      passwordHash: passwordHash ?? this.passwordHash,
      salt: salt ?? this.salt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'UserProfile(id: $id, name: $name, age: $age, gender: $gender, '
        'email: $email, bpm: $baselineBpm, hrv: $baselineHrv, avatar: $avatarPath)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserProfile &&
        other.id == id &&
        other.name == name &&
        other.age == age &&
        other.gender == gender &&
        other.email == email &&
        other.healthJson == healthJson &&
        other.baselineBpm == baselineBpm &&
        other.baselineHrv == baselineHrv &&
        other.avatarPath == avatarPath &&
        other.passwordHash == passwordHash &&
        other.salt == salt &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      name,
      age,
      gender,
      email,
      healthJson,
      baselineBpm,
      baselineHrv,
      avatarPath,
      passwordHash,
      salt,
      createdAt,
    );
  }
}
