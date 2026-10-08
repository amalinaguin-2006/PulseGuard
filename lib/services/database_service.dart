/// PulseGuard — SQLite Database Service (Singleton, Schema v2)
///
/// Manages the local `pulse_guard.db` database lifecycle and exposes
/// typed CRUD operations for [UserProfile] and [PpgReading] models with
/// full support for v1 -> v2 schema migrations.
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/ppg_reading.dart';
import '../models/user_profile.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

/// Database file name stored in the platform-default databases directory.
const String _kDatabaseName = 'pulse_guard.db';

/// Schema version 2: Added email, health_json, avatar_path, password_hash,
/// salt to user_profiles; added sdnn to ppg_readings.
const int _kDatabaseVersion = 2;

// Table & column names
const String _kTableUserProfiles = 'user_profiles';
const String _kTablePpgReadings = 'ppg_readings';

// ─────────────────────────────────────────────────────────────────────────────
// DDL Statements
// ─────────────────────────────────────────────────────────────────────────────

/// CREATE TABLE for user profiles (v2).
const String _kCreateUserProfilesTable = '''
  CREATE TABLE $_kTableUserProfiles (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    name          TEXT    NOT NULL,
    age           INTEGER NOT NULL,
    gender        TEXT    NOT NULL,
    email         TEXT,
    health_json   TEXT,
    baseline_bpm  REAL,
    baseline_hrv  REAL,
    avatar_path   TEXT,
    password_hash TEXT,
    salt          TEXT,
    created_at    TEXT    NOT NULL
  )
''';

/// CREATE TABLE for PPG telemetry readings (v2).
const String _kCreatePpgReadingsTable = '''
  CREATE TABLE $_kTablePpgReadings (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp      TEXT    NOT NULL,
    bpm            REAL    NOT NULL,
    rmssd          REAL    NOT NULL,
    sdnn           REAL    NOT NULL DEFAULT 0.0,
    stress_index   REAL    NOT NULL,
    signal_quality REAL    NOT NULL,
    raw_ppg_data   TEXT
  )
''';

/// Index on timestamp for O(log n) date-range and chronological queries.
const String _kCreateTimestampIndex = '''
  CREATE INDEX idx_ppg_timestamp ON $_kTablePpgReadings (timestamp)
''';

// ─────────────────────────────────────────────────────────────────────────────
// Database Service
// ─────────────────────────────────────────────────────────────────────────────

/// Singleton service that owns the SQLite connection and exposes typed CRUD.
class DatabaseService {
  DatabaseService._internal();

  /// The single shared instance of this service.
  static final DatabaseService instance = DatabaseService._internal();

  /// The lazily-initialized database handle.
  Database? _database;

  /// Returns the open database handle, creating the file and tables on first call.
  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Opens or creates the database file with migration support.
  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, _kDatabaseName);

    return openDatabase(
      path,
      version: _kDatabaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Called when the database file is first created.
  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    batch.execute(_kCreateUserProfilesTable);
    batch.execute(_kCreatePpgReadingsTable);
    batch.execute(_kCreateTimestampIndex);
    await batch.commit(noResult: true);
  }

  /// Handles incremental schema migrations.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Migrate v1 -> v2: Add new columns if missing
      await _safeAddColumn(db, _kTableUserProfiles, 'email', 'TEXT');
      await _safeAddColumn(db, _kTableUserProfiles, 'health_json', 'TEXT');
      await _safeAddColumn(db, _kTableUserProfiles, 'avatar_path', 'TEXT');
      await _safeAddColumn(db, _kTableUserProfiles, 'password_hash', 'TEXT');
      await _safeAddColumn(db, _kTableUserProfiles, 'salt', 'TEXT');
      await _safeAddColumn(
          db, _kTablePpgReadings, 'sdnn', 'REAL NOT NULL DEFAULT 0.0');
    }
  }

  /// Safely attempts to add a column, ignoring error if it already exists.
  Future<void> _safeAddColumn(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    try {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type;');
    } catch (_) {
      // Column may already exist from earlier test runs
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // USER PROFILE CRUD
  // ═════════════════════════════════════════════════════════════════════════

  /// Inserts a new [UserProfile] and returns the generated row id.
  Future<int> insertUserProfile(UserProfile profile) async {
    try {
      final db = await database;
      return await db.insert(
        _kTableUserProfiles,
        profile.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      throw Exception('Failed to insert user profile: $e');
    }
  }

  /// Updates an existing [UserProfile] identified by its [id].
  Future<int> updateUserProfile(UserProfile profile) async {
    if (profile.id == null) {
      throw ArgumentError('Cannot update a UserProfile without an id.');
    }
    try {
      final db = await database;
      return await db.update(
        _kTableUserProfiles,
        profile.toMap(),
        where: 'id = ?',
        whereArgs: [profile.id],
      );
    } catch (e) {
      throw Exception('Failed to update user profile (id=${profile.id}): $e');
    }
  }

  /// Fetches the most recent [UserProfile], or `null` if none exists yet.
  Future<UserProfile?> fetchCurrentProfile() async {
    try {
      final db = await database;
      final rows = await db.query(
        _kTableUserProfiles,
        orderBy: 'id DESC',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return UserProfile.fromMap(rows.first);
    } catch (e) {
      throw Exception('Failed to fetch current user profile: $e');
    }
  }

  /// Fetches a [UserProfile] by its [id], or `null` if not found.
  Future<UserProfile?> fetchUserProfileById(int id) async {
    try {
      final db = await database;
      final rows = await db.query(
        _kTableUserProfiles,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return UserProfile.fromMap(rows.first);
    } catch (e) {
      throw Exception('Failed to fetch user profile (id=$id): $e');
    }
  }

  /// Fetches a [UserProfile] by its [email], or `null` if not found.
  Future<UserProfile?> fetchUserProfileByEmail(String email) async {
    try {
      final db = await database;
      final rows = await db.query(
        _kTableUserProfiles,
        where: 'LOWER(email) = ?',
        whereArgs: [email.trim().toLowerCase()],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return UserProfile.fromMap(rows.first);
    } catch (e) {
      throw Exception('Failed to fetch user profile by email ($email): $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // PPG READING CRUD
  // ═════════════════════════════════════════════════════════════════════════

  /// Inserts a new [PpgReading] and returns the generated row id.
  Future<int> insertPpgReading(PpgReading reading) async {
    try {
      final db = await database;
      return await db.insert(
        _kTablePpgReadings,
        reading.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      throw Exception('Failed to insert PPG reading: $e');
    }
  }

  /// Returns the most recent [limit] PPG readings ordered newest-first.
  Future<List<PpgReading>> fetchRecentReadings({int limit = 30}) async {
    try {
      final db = await database;
      final rows = await db.query(
        _kTablePpgReadings,
        orderBy: 'timestamp DESC',
        limit: limit,
      );
      return rows.map(PpgReading.fromMap).toList();
    } catch (e) {
      throw Exception('Failed to fetch recent PPG readings: $e');
    }
  }

  /// Returns all PPG readings whose [timestamp] falls in the range `[start, end]`.
  Future<List<PpgReading>> fetchReadingsByDateRange(
    String start,
    String end,
  ) async {
    try {
      final db = await database;
      final rows = await db.query(
        _kTablePpgReadings,
        where: 'timestamp >= ? AND timestamp <= ?',
        whereArgs: [start, end],
        orderBy: 'timestamp ASC',
      );
      return rows.map(PpgReading.fromMap).toList();
    } catch (e) {
      throw Exception(
        'Failed to fetch PPG readings for range [$start → $end]: $e',
      );
    }
  }

  /// Deletes a single PPG reading by its [id].
  Future<int> deleteReading(int id) async {
    try {
      final db = await database;
      return await db.delete(
        _kTablePpgReadings,
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      throw Exception('Failed to delete PPG reading (id=$id): $e');
    }
  }

  /// Removes all PPG readings from the database.
  Future<int> clearAllReadings() async {
    try {
      final db = await database;
      return await db.delete(_kTablePpgReadings);
    } catch (e) {
      throw Exception('Failed to clear all PPG readings: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═════════════════════════════════════════════════════════════════════════

  /// Closes the database connection.
  Future<void> close() async {
    final db = _database;
    if (db != null && db.isOpen) {
      await db.close();
      _database = null;
    }
  }
}
