import 'dart:math';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart' as sqflite;

import 'local_store.dart';

class SqliteLocalStore implements LocalStore {
  SqliteLocalStore({
    sqflite.DatabaseFactory? databaseFactory,
    String? databasePath,
  }) : _databaseFactory = databaseFactory ?? sqflite.databaseFactory,
       _databasePath = databasePath;

  static const _databaseName = 'learning_calculator.db';
  static const _databaseVersion = 1;
  static const _profileTable = 'learner_profiles';
  static const _historyTable = 'calculation_history';

  final sqflite.DatabaseFactory _databaseFactory;
  final String? _databasePath;
  Future<void>? _opening;
  sqflite.Database? _database;

  @override
  Future<void> initialize() {
    if (_database != null) {
      return Future<void>.value();
    }
    return _opening ??= _openDatabase();
  }

  Future<void> _openDatabase() async {
    final databasePath =
        _databasePath ??
        path.join(await _databaseFactory.getDatabasesPath(), _databaseName);
    _database = await _databaseFactory.openDatabase(
      databasePath,
      options: sqflite.OpenDatabaseOptions(
        version: _databaseVersion,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE $_profileTable (
              id TEXT PRIMARY KEY NOT NULL,
              grade INTEGER NOT NULL CHECK (grade IN (3, 4, 5)),
              created_at INTEGER NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE $_historyTable (
              id TEXT PRIMARY KEY NOT NULL,
              profile_id TEXT NOT NULL
                REFERENCES $_profileTable(id) ON DELETE CASCADE,
              expression TEXT NOT NULL,
              result TEXT NOT NULL,
              recorded_at INTEGER NOT NULL,
              topic TEXT NOT NULL
            )
          ''');
          await database.execute('''
            CREATE INDEX calculation_history_by_profile_and_time
            ON $_historyTable(profile_id, recorded_at DESC)
          ''');
        },
      ),
    );
  }

  Future<sqflite.Database> get _db async {
    await initialize();
    return _database!;
  }

  @override
  Future<List<LearnerProfile>> getProfiles() async {
    final rows = await (await _db).query(
      _profileTable,
      orderBy: 'created_at, id',
    );
    return rows.map(_profileFromRow).toList(growable: false);
  }

  @override
  Future<LearnerProfile?> getProfile(String profileId) async {
    final rows = await (await _db).query(
      _profileTable,
      where: 'id = ?',
      whereArgs: [profileId],
      limit: 1,
    );
    return rows.isEmpty ? null : _profileFromRow(rows.single);
  }

  @override
  Future<LearnerProfile> createProfile({required int grade}) async {
    _validateGrade(grade);
    final timestamp = DateTime.now().toUtc();
    final profile = LearnerProfile(
      id: _newId('p'),
      grade: grade,
      createdAt: timestamp,
    );
    await (await _db).insert(_profileTable, {
      'id': profile.id,
      'grade': profile.grade,
      'created_at': profile.createdAt.millisecondsSinceEpoch,
    });
    return profile;
  }

  @override
  Future<LearnerProfile> updateProfileGrade(
    String profileId, {
    required int grade,
  }) async {
    _validateGrade(grade);
    final updated = await (await _db).update(
      _profileTable,
      {'grade': grade},
      where: 'id = ?',
      whereArgs: [profileId],
    );
    if (updated == 0) {
      throw StateError('Learner profile does not exist.');
    }
    return (await getProfile(profileId))!;
  }

  @override
  Future<CalculationHistoryEntry> addHistoryEntry({
    required String profileId,
    required String expression,
    required String result,
    required DateTime timestamp,
    required String topic,
  }) async {
    if (await getProfile(profileId) == null) {
      throw StateError('Learner profile does not exist.');
    }
    final entry = CalculationHistoryEntry(
      id: _newId('h'),
      profileId: profileId,
      expression: expression,
      result: result,
      timestamp: timestamp.toUtc(),
      topic: topic,
    );
    await (await _db).insert(_historyTable, {
      'id': entry.id,
      'profile_id': entry.profileId,
      'expression': entry.expression,
      'result': entry.result,
      'recorded_at': entry.timestamp.millisecondsSinceEpoch,
      'topic': entry.topic,
    });
    return entry;
  }

  @override
  Future<List<CalculationHistoryEntry>> getHistory(String profileId) async {
    final rows = await (await _db).query(
      _historyTable,
      where: 'profile_id = ?',
      whereArgs: [profileId],
      orderBy: 'recorded_at DESC, id DESC',
    );
    return rows.map(_historyFromRow).toList(growable: false);
  }

  @override
  Future<void> clearHistory(String profileId) async {
    await (await _db).delete(
      _historyTable,
      where: 'profile_id = ?',
      whereArgs: [profileId],
    );
  }

  Future<void> close() async {
    final opening = _opening;
    if (opening != null) {
      await opening;
    }
    final database = _database;
    _database = null;
    _opening = null;
    await database?.close();
  }

  LearnerProfile _profileFromRow(Map<String, Object?> row) {
    return LearnerProfile(
      id: row['id']! as String,
      grade: row['grade']! as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at']! as int,
        isUtc: true,
      ),
    );
  }

  CalculationHistoryEntry _historyFromRow(Map<String, Object?> row) {
    return CalculationHistoryEntry(
      id: row['id']! as String,
      profileId: row['profile_id']! as String,
      expression: row['expression']! as String,
      result: row['result']! as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        row['recorded_at']! as int,
        isUtc: true,
      ),
      topic: row['topic']! as String,
    );
  }

  static void _validateGrade(int grade) {
    if (grade < 3 || grade > 5) {
      throw ArgumentError.value(grade, 'grade', 'Must be 3, 4, or 5.');
    }
  }

  static String _newId(String prefix) {
    final random = Random.secure();
    final suffix = List<int>.generate(16, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${prefix}_$suffix';
  }
}
