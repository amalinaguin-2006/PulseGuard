/// PulseGuard — SQLite Database Service (Singleton)
///
/// Manages the local `pulse_guard.db` database lifecycle and exposes
/// typed CRUD operations for [UserProfile] and [PpgReading] models.
///
/// Design decisions:
///   • **Singleton** via private constructor + static [instance] getter
///     so every widget / service shares one connection pool.
///   • **Lazy initialisation** — the database file is created on the
///     first call to any public method, not at import time.
///   • **Index on `ppg_readings.timestamp`** for O(log n) date-range
///     queries used by trend charts and history views.
///   • All public methods wrap calls in try/catch and rethrow with
///     context so upstream callers can show meaningful error UI.
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

/// Schema version.  Increment this and add migration logic in
/// [_onUpgrade] when the schema changes in future releases.
const int _kDatabaseVersion = 1;

// Table & column names kept as constants to avoid typo-induced bugs.
const String _kTableUserProfiles = 'user_profiles';
const String _kTablePpgReadings = 'ppg_readings';

// ─────────────────────────────────────────────────────────────────────────────
// DDL Statements
// ─────────────────────────────────────────────────────────────────────────────

/// CREATE TABLE for user profiles.
const String _kCreateUserProfilesTable = '''
  CREATE TABLE $_kTableUserProfiles (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    name         TEXT    NOT NULL,
    age          INTEGER NOT NULL,
    gender       TEXT    NOT NULL,
    baseline_bpm REAL,
    baseline_hrv REAL,
    created_at   TEXT    NOT NULL
  )
''';

/// CREATE TABLE for PPG telemetry readings.
const String _kCreatePpgReadingsTable = '''
  CREATE TABLE $_kTablePpgReadings (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp      TEXT    NOT NULL,
    bpm            REAL    NOT NULL,
    rmssd          REAL    NOT NULL,
    stress_index   REAL    NOT NULL,
    signal_quality REAL    NOT NULL,
    raw_ppg_data   TEXT
  )
''';

/// Index on timestamp for fast chronological and date-range queries.
const String _kCreateTimestampIndex = '''
  CREATE INDEX idx_ppg_timestamp ON $_kTablePpgReadings (timestamp)
''';

// ─────────────────────────────────────────────────────────────────────────────
// Database Service
// ─────────────────────────────────────────────────────────────────────────────

/// Singleton service that owns the SQLite connection and exposes typed
/// CRUD helpers for every persistent model in PulseGuard.
class DatabaseService {
  // ── Singleton plumbing ─────────────────────────────────────────────────

  DatabaseService._internal();

  /// The single shared instance of this service.
  static final DatabaseService instance = DatabaseService._internal();

  /// The lazily-initialised database handle.
  Database? _database;

  /// Returns the open database handle, creating the file and tables on
  /// the very first invocation.
  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // ── Initialisation & Schema ────────────────────────────────────────────

  /// Opens (or creates) the database file and runs the schema DDL.
  Future<Database> _initDatabase() async {
    // Resolve the platform-specific databases directory.
    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, _kDatabaseName);

    return openDatabase(
      path,
      version: _kDatabaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Called exactly once when the database file is first created.
  Future<void> _onCreate(Database db, int version) async {
    // Use a batch so all DDL runs in a single transaction.
    final batch = db.batch();
    batch.execute(_kCreateUserProfilesTable);
    batch.execute(_kCreatePpgReadingsTable);
    batch.execute(_kCreateTimestampIndex);
    await batch.commit(noResult: true);
  }

  /// Placeholder for future schema migrations.
  ///
  /// When bumping [_kDatabaseVersion], add incremental ALTER / CREATE
  /// statements here keyed on [oldVersion] → [newVersion] ranges.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Example pattern for future migrations:
    // if (oldVersion < 2) {
    //   await db.execute('ALTER TABLE ...');
    // }
  }

  // ═════════════════════════════════════════════════════════════════════════
  //  USER PROFILE CRUD
  // ═════════════════════════════════════════════════════════════════════════

  /// Inserts a new [UserProfile] and returns the auto-generated row id.
  ///
  /// Throws a [DatabaseException] if a constraint is violated.
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
  ///
  /// Returns the number of rows affected (expected: 1).
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

  /// Fetches the most-recently created [UserProfile], or `null` if none
  /// exists yet (first-launch state).
  ///
  /// PulseGuard is designed as a single-user app, so the "current" profile
  /// is simply the latest row ordered by creation timestamp.
  Future<UserProfile?> fetchCurrentProfile() async {
    try {
      final db = await database;
      final rows = await db.query(
        _kTableUserProfiles,
        orderBy: 'created_at DESC',
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

  // ═════════════════════════════════════════════════════════════════════════
  //  PPG READING CRUD
  // ═════════════════════════════════════════════════════════════════════════

  /// Inserts a new [PpgReading] and returns the auto-generated row id.
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
  ///
  /// Used by the dashboard trend chart and recent-history list.
  /// Defaults to 30 readings — enough for a meaningful short-term trend.
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

  /// Returns all PPG readings whose [timestamp] falls within the
  /// inclusive range `[start, end]`.
  ///
  /// Both [start] and [end] must be ISO-8601 strings so that SQLite's
  /// lexicographic comparison produces correct chronological ordering.
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
  ///
  /// Returns the number of rows deleted (expected: 0 or 1).
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

  /// Removes **all** PPG readings from the database.
  ///
  /// This is a destructive operation intended for "Reset Data" flows.
  /// Returns the number of rows deleted.
  Future<int> clearAllReadings() async {
    try {
      final db = await database;
      return await db.delete(_kTablePpgReadings);
    } catch (e) {
      throw Exception('Failed to clear all PPG readings: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  //  LIFECYCLE
  // ═════════════════════════════════════════════════════════════════════════

  /// Closes the database connection.
  ///
  /// Call this during app teardown if you need deterministic cleanup.
  /// After calling [close], the next access to [database] will
  /// transparently re-open the connection.
  Future<void> close() async {
    final db = _database;
    if (db != null && db.isOpen) {
      await db.close();
      _database = null;
    }
  }
}
