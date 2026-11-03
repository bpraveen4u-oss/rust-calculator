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
  static const _databaseVersion = 2;
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
          await _createSyncTables(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createSyncTables(database);
          }
        },
      ),
    );
  }

  Future<void> _createSyncTables(sqflite.DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE sync_profiles (
        local_profile_id TEXT PRIMARY KEY NOT NULL
          REFERENCES $_profileTable(id) ON DELETE CASCADE,
        remote_profile_id TEXT NOT NULL,
        last_successful_sync_at INTEGER
      )
    ''');
    await database.execute('''
      CREATE TABLE sync_outbox (
        local_profile_id TEXT NOT NULL
          REFERENCES $_profileTable(id) ON DELETE CASCADE,
        change_id TEXT NOT NULL,
        PRIMARY KEY(local_profile_id, change_id)
      )
    ''');
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
    final database = await _db;
    await database.transaction((transaction) async {
      final updated = await transaction.update(
        _profileTable,
        {'grade': grade},
        where: 'id = ?',
        whereArgs: [profileId],
      );
      if (updated == 0) {
        throw StateError('Learner profile does not exist.');
      }
      await transaction.rawInsert(
        '''
        INSERT OR IGNORE INTO sync_outbox (local_profile_id, change_id)
        VALUES (?, 'profile-grade')
        ''',
        [profileId],
      );
    });
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
    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.insert(_historyTable, {
        'id': entry.id,
        'profile_id': entry.profileId,
        'expression': entry.expression,
        'result': entry.result,
        'recorded_at': entry.timestamp.millisecondsSinceEpoch,
        'topic': entry.topic,
      });
      await transaction.rawInsert(
        '''
        INSERT OR IGNORE INTO sync_outbox (local_profile_id, change_id)
        SELECT ?, ?
        WHERE EXISTS (
          SELECT 1 FROM sync_profiles WHERE local_profile_id = ?
        )
        ''',
        [profileId, entry.id, profileId],
      );
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
    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.delete(
        _historyTable,
        where: 'profile_id = ?',
        whereArgs: [profileId],
      );
      await transaction.delete(
        'sync_outbox',
        where: 'local_profile_id = ? AND change_id != ?',
        whereArgs: [profileId, 'profile-grade'],
      );
    });
  }

  @override
  Future<void> linkSyncProfile({
    required String localProfileId,
    required String remoteProfileId,
  }) async {
    final database = await _db;
    if (await getProfile(localProfileId) == null) {
      throw StateError('Learner profile does not exist.');
    }
    await database.transaction((transaction) async {
      await transaction.insert(
        'sync_profiles',
        {
          'local_profile_id': localProfileId,
          'remote_profile_id': remoteProfileId,
        },
        conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
      );
      await transaction.rawInsert(
        '''
        INSERT OR IGNORE INTO sync_outbox (local_profile_id, change_id)
        SELECT ?, id FROM $_historyTable
        WHERE profile_id = ? AND recorded_at > ?
        ''',
        [
          localProfileId,
          localProfileId,
          DateTime.now()
              .toUtc()
              .subtract(const Duration(days: 90))
              .millisecondsSinceEpoch,
        ],
      );
    });
  }

  @override
  Future<List<SyncProfileState>> getSyncProfiles() async {
    final rows = await (await _db).rawQuery('''
      SELECT p.id, p.grade, p.created_at, s.remote_profile_id,
             s.last_successful_sync_at
      FROM $_profileTable AS p
      INNER JOIN sync_profiles AS s ON s.local_profile_id = p.id
      ORDER BY p.created_at, p.id
    ''');
    return rows
        .map(
          (row) => SyncProfileState(
            profile: _profileFromRow(row),
            remoteProfileId: row['remote_profile_id']! as String,
            lastSuccessfulSyncAt: row['last_successful_sync_at'] == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    row['last_successful_sync_at']! as int,
                    isUtc: true,
                  ),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<PendingSyncChanges?> getPendingSyncChanges(String profileId) async {
    final database = await _db;
    await _pruneExpiredOutbox(database);
    final profile = await getProfile(profileId);
    if (profile == null) return null;
    final linked = await database.query(
      'sync_profiles',
      columns: ['local_profile_id'],
      where: 'local_profile_id = ?',
      whereArgs: [profileId],
      limit: 1,
    );
    if (linked.isEmpty) return null;

    final changes = await database.query(
      'sync_outbox',
      columns: ['change_id'],
      where: 'local_profile_id = ?',
      whereArgs: [profileId],
    );
    final changeIds = changes
        .map((row) => row['change_id']! as String)
        .toSet();
    final historyIds = changeIds
        .where((id) => id != 'profile-grade')
        .toList(growable: false);
    final historyRows = historyIds.isEmpty
        ? <Map<String, Object?>>[]
        : await database.query(
            _historyTable,
            where:
                'profile_id = ? AND id IN ('
                '${List.filled(historyIds.length, '?').join(',')})',
            whereArgs: [profileId, ...historyIds],
          );
    return PendingSyncChanges(
      profile: profile,
      gradeChanged: changeIds.contains('profile-grade'),
      history: historyRows.map(_historyFromRow).toList(growable: false),
    );
  }

  @override
  Future<int> getPendingSyncCount() async {
    final database = await _db;
    await _pruneExpiredOutbox(database);
    final result = await database.rawQuery('''
      SELECT COUNT(*) AS change_count
      FROM sync_outbox AS o
      INNER JOIN sync_profiles AS s ON s.local_profile_id = o.local_profile_id
    ''');
    return result.single['change_count']! as int;
  }

  Future<void> _pruneExpiredOutbox(
    sqflite.DatabaseExecutor database,
  ) async {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 90))
        .millisecondsSinceEpoch;
    await database.rawDelete(
      '''
      DELETE FROM sync_outbox
      WHERE change_id IN (
        SELECT id FROM $_historyTable WHERE recorded_at <= ?
      )
      ''',
      [cutoff],
    );
  }

  @override
  Future<void> mergeRemoteProfileGrade(
    String profileId, {
    required int grade,
  }) async {
    if (grade < 3 || grade > 5) {
      throw ArgumentError.value(grade, 'grade', 'Must be 3, 4, or 5.');
    }
    await (await _db).rawUpdate(
      '''
      UPDATE $_profileTable
      SET grade = ?
      WHERE id = ?
        AND NOT EXISTS (
          SELECT 1 FROM sync_outbox
          WHERE local_profile_id = ? AND change_id = 'profile-grade'
        )
      ''',
      [grade, profileId, profileId],
    );
  }

  @override
  Future<void> mergeRemoteHistory(
    String profileId,
    List<CalculationHistoryEntry> entries,
  ) async {
    final database = await _db;
    await database.transaction((transaction) async {
      for (final entry in entries) {
        if (entry.profileId != profileId) {
          throw ArgumentError.value(
            entry.profileId,
            'entry.profileId',
            'Remote history belongs to a different profile.',
          );
        }
        await transaction.insert(
          _historyTable,
          {
            'id': entry.id,
            'profile_id': entry.profileId,
            'expression': entry.expression,
            'result': entry.result,
            'recorded_at': entry.timestamp.toUtc().millisecondsSinceEpoch,
            'topic': entry.topic,
          },
          conflictAlgorithm: sqflite.ConflictAlgorithm.ignore,
        );
      }
    });
  }

  @override
  Future<void> markSyncSucceeded({
    required String profileId,
    required DateTime syncedAt,
    required int? syncedGrade,
    required List<String> syncedHistoryIds,
  }) async {
    final database = await _db;
    await database.transaction((transaction) async {
      if (syncedGrade != null) {
        await transaction.rawDelete(
          '''
          DELETE FROM sync_outbox
          WHERE local_profile_id = ? AND change_id = 'profile-grade'
            AND EXISTS (
              SELECT 1 FROM $_profileTable
              WHERE id = ? AND grade = ?
            )
          ''',
          [profileId, profileId, syncedGrade],
        );
      }
      for (final id in syncedHistoryIds) {
        await transaction.delete(
          'sync_outbox',
          where: 'local_profile_id = ? AND change_id = ?',
          whereArgs: [profileId, id],
        );
      }
      await transaction.update(
        'sync_profiles',
        {'last_successful_sync_at': syncedAt.toUtc().millisecondsSinceEpoch},
        where: 'local_profile_id = ?',
        whereArgs: [profileId],
      );
    });
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
