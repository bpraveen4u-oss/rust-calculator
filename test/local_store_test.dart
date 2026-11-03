import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../lib/app/sqlite_local_store.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('local learner storage', () {
    late SqliteLocalStore store;
    String? persistentDatabasePath;

    setUp(() {
      persistentDatabasePath = null;
      store = SqliteLocalStore(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
    });

    tearDown(() async {
      await store.close();
      final databasePath = persistentDatabasePath;
      if (databasePath != null) {
        await databaseFactoryFfi.deleteDatabase(databasePath);
      }
    });

    test(
      'keeps pseudonymous profiles and calculation history separate',
      () async {
        await store.initialize();
        final gradeFour = await store.createProfile(grade: 4);
        final gradeFive = await store.createProfile(grade: 5);

        expect(gradeFour.id, isNot(gradeFive.id));
        expect(gradeFour.id, matches(RegExp(r'^p_[0-9a-f]{32}$')));
        expect(gradeFour.grade, 4);
        expect(gradeFive.grade, 5);

        await store.addHistoryEntry(
          profileId: gradeFour.id,
          expression: '8 × 7',
          result: '56',
          timestamp: DateTime.utc(2026, 11, 2, 12),
          topic: 'multiplication',
        );

        final history = await store.getHistory(gradeFour.id);
        expect(history, hasLength(1));
        expect(history.single.expression, '8 × 7');
        expect(history.single.result, '56');
        expect(history.single.timestamp, DateTime.utc(2026, 11, 2, 12));
        expect(history.single.topic, 'multiplication');
        expect(await store.getHistory(gradeFive.id), isEmpty);
      },
    );

    test('keeps the selected grade on its pseudonymous profile', () async {
      await store.initialize();
      final profile = await store.createProfile(grade: 3);

      final updated = await store.updateProfileGrade(profile.id, grade: 5);

      expect(updated.id, profile.id);
      expect(updated.grade, 5);
      expect((await store.getProfile(profile.id))?.grade, 5);
    });

    test(
      'clears history only when explicitly requested for that profile',
      () async {
        await store.initialize();
        final first = await store.createProfile(grade: 3);
        final second = await store.createProfile(grade: 4);

        for (final profile in [first, second]) {
          await store.addHistoryEntry(
            profileId: profile.id,
            expression: '9 + 6',
            result: '15',
            timestamp: DateTime.utc(2026, 11, 2),
            topic: 'addition',
          );
        }

        await store.clearHistory(first.id);

        expect(await store.getHistory(first.id), isEmpty);
        expect(await store.getHistory(second.id), hasLength(1));
        expect(await store.getProfile(first.id), isNotNull);
      },
    );

    test(
      'retains profiles and history after reopening its SQLite database',
      () async {
        final databasePath = path.join(
          Directory.current.path,
          '.local_store_persistence_test.db',
        );
        persistentDatabasePath = databasePath;
        await databaseFactoryFfi.deleteDatabase(databasePath);
        store = SqliteLocalStore(
          databaseFactory: databaseFactoryFfi,
          databasePath: databasePath,
        );
        await store.initialize();
        final profile = await store.createProfile(grade: 4);
        await store.addHistoryEntry(
          profileId: profile.id,
          expression: '18 ÷ 3',
          result: '6',
          timestamp: DateTime.utc(2026, 11, 2),
          topic: 'division',
        );
        await store.close();

        store = SqliteLocalStore(
          databaseFactory: databaseFactoryFfi,
          databasePath: databasePath,
        );

        expect((await store.getProfile(profile.id))?.grade, 4);
        expect(
          (await store.getHistory(profile.id)).single.expression,
          '18 ÷ 3',
        );
      },
    );

    test('rejects grades outside the supported range', () async {
      await store.initialize();

      await expectLater(
        store.createProfile(grade: 2),
        throwsArgumentError,
      );
    });
  });
}
