import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../lib/app/learning_calculator_app.dart';
import '../lib/app/sqlite_local_store.dart';
import '../lib/features/guardian/guardian_access.dart';
import '../lib/features/sync/sync_coordinator.dart';
import '../lib/features/sync/sync_dependencies.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets(
    'guardian pairing queues offline history, retries safely, merges devices, '
    'and reports the last successful sync',
    (tester) async {
      final store = SqliteLocalStore(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      await store.initialize();
      final profile = await store.createProfile(grade: 4);
      final localEntry = await store.addHistoryEntry(
        profileId: profile.id,
        expression: '8 × 7',
        result: '56',
        timestamp: DateTime.now().toUtc(),
        topic: 'multiplication',
      );
      final api = _FakeSyncApi()
        ..remoteEntries.add(
          const SyncHistoryRecord(
            id: 'remote-entry-1',
            expression: '9 + 6',
            result: '15',
            timestamp: '2026-11-02T11:00:00Z',
            topic: 'addition',
          ),
        );
      final connectivity = _ControllableConnectivity(initiallyOnline: true);
      final credentials = _InMemoryCredentials();
      final syncClient = SyncCoordinator(
        localStore: store,
        api: api,
        credentials: credentials,
        connectivity: connectivity,
        enabled: true,
      );
      addTearDown(() async {
        await syncClient.dispose();
        await store.close();
      });

      await tester.pumpWidget(
        LearningCalculatorApp(
          localStore: store,
          syncClient: syncClient,
          guardianAccess: _FakeGuardianAccess(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not paired'), findsOneWidget);

      await tester.tap(find.text('Guardian controls'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('guardian-pin')), '123456');
      await tester.enterText(
        find.byKey(const Key('guardian-pin-confirm')),
        '123456',
      );
      await tester.tap(find.byKey(const Key('guardian-save-pin')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('expression, result, timestamp, and topic'),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const Key('guardian-pairing-opt-in')),
      );
      await tester.tap(find.byKey(const Key('guardian-pairing-opt-in')));
      await tester.ensureVisible(
        find.byKey(const Key('guardian-start-pairing')),
      );
      await tester.tap(find.byKey(const Key('guardian-start-pairing')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('guardian-pairing-code')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('guardian-pairing-code')),
        'ABCD-2345',
      );
      await tester.ensureVisible(
        find.byKey(const Key('guardian-submit-pairing-code')),
      );
      await tester.tap(find.byKey(const Key('guardian-submit-pairing-code')));
      await tester.pumpAndSettle();

      expect(api.pairedCodes, ['ABCD-2345']);
      expect(credentials.tokens.values, contains('device-secret'));
      expect(api.submittedHistoryIds, contains(localEntry.id));
      expect(api.submittedHistoryIds, contains('remote-entry-1'));
      expect((await store.getProfile(profile.id))?.grade, 5);
      await tester.ensureVisible(
        find.byKey(const Key('guardian-create-pairing-code')),
      );
      await tester.tap(find.byKey(const Key('guardian-create-pairing-code')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('ABCD-2345 (expires'),
        findsOneWidget,
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      connectivity.setOnline(false);
      final offlineEntry = await store.addHistoryEntry(
        profileId: profile.id,
        expression: '12 ÷ 3',
        result: '4',
        timestamp: DateTime.now().toUtc(),
        topic: 'division',
      );
      await syncClient.syncPendingChanges();
      await tester.pumpAndSettle();
      expect(find.text('Waiting for connection'), findsOneWidget);
      expect(find.text('1 change waiting to sync'), findsOneWidget);

      api.failNextSyncAfterAcceptingChanges = true;
      final failedRetry = api.trackNextSync();
      connectivity.setOnline(true);
      await failedRetry;
      await tester.pumpAndSettle();
      expect(find.text('Sync paused'), findsOneWidget);
      expect(find.text('1 change waiting to sync'), findsOneWidget);

      final successfulRetry = api.trackNextSync();
      await syncClient.syncPendingChanges();
      await successfulRetry;
      await tester.pumpAndSettle();

      expect(api.submittedHistoryIds, contains(offlineEntry.id));
      expect(api.serverHistory.map((entry) => entry.id).toSet(), {
        localEntry.id,
        'remote-entry-1',
        offlineEntry.id,
      });
      expect(
        (await store.getHistory(profile.id)).map((entry) => entry.id).toSet(),
        {
          localEntry.id,
          'remote-entry-1',
          offlineEntry.id,
        },
      );
      expect(find.text('Synced'), findsOneWidget);
      expect(find.textContaining('Last synced'), findsOneWidget);

      await syncClient.syncPendingChanges();
      expect(api.serverHistory, hasLength(3));
    },
  );

  test('cloud history erasure targets the linked cloud profile', () async {
    final store = SqliteLocalStore(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    await store.initialize();
    final profile = await store.createProfile(grade: 4);
    await store.linkSyncProfile(
      localProfileId: profile.id,
      remoteProfileId: 'cloud-profile-1',
    );
    final api = _FakeSyncApi();
    final syncClient = SyncCoordinator(
      localStore: store,
      api: api,
      credentials: _InMemoryCredentials(),
      connectivity: _ControllableConnectivity(initiallyOnline: true),
      enabled: true,
    );
    addTearDown(() async {
      await syncClient.dispose();
      await store.close();
    });

    await syncClient.eraseCloudHistory(profile.id, 'guardian-secret');

    expect(api.erasedProfileId, 'cloud-profile-1');
    expect(api.guardianCredential, 'guardian-secret');
  });
}

class _FakeSyncApi implements SyncApi {
  final List<String> pairedCodes = [];
  final List<String> submittedHistoryIds = [];
  final List<SyncHistoryRecord> remoteEntries = [];
  Completer<void>? _nextSyncCompleted;
  bool failNextSyncAfterAcceptingChanges = false;
  String? erasedProfileId;
  String? guardianCredential;

  List<SyncHistoryRecord> get serverHistory => List.unmodifiable(remoteEntries);

  Future<void> trackNextSync() {
    _nextSyncCompleted = Completer<void>();
    return _nextSyncCompleted!.future;
  }

  @override
  Future<PairedDevice> pair(String code) async {
    pairedCodes.add(code);
    return const PairedDevice(
      profileId: 'cloud-profile-1',
      deviceToken: 'device-secret',
    );
  }

  @override
  Future<SyncSnapshot> sync({
    required String profileId,
    required String bearerToken,
    int? grade,
    required List<SyncHistoryRecord> history,
  }) async {
    expect(profileId, 'cloud-profile-1');
    expect(bearerToken, 'device-secret');
    submittedHistoryIds.addAll(history.map((entry) => entry.id));
    for (final entry in history) {
      if (!remoteEntries.any((remote) => remote.id == entry.id)) {
        remoteEntries.add(entry);
      }
    }
    if (failNextSyncAfterAcceptingChanges) {
      failNextSyncAfterAcceptingChanges = false;
      _completeTrackedSync();
      throw StateError('response lost after server accepted the request');
    }
    final snapshot = SyncSnapshot(
      profileId: profileId,
      grade: grade ?? 5,
      history: List.unmodifiable(remoteEntries),
    );
    _completeTrackedSync();
    return snapshot;
  }

  void _completeTrackedSync() {
    final tracked = _nextSyncCompleted;
    if (tracked != null && !tracked.isCompleted) tracked.complete();
  }

  @override
  Future<PairingCode> createPairingCode(String bearerToken) async =>
      PairingCode(
        code: 'ABCD-2345',
        expiresAt: DateTime.utc(2026, 11, 2, 12, 10),
      );

  @override
  Future<void> eraseHistory({
    required String profileId,
    required String guardianCredential,
  }) async {
    erasedProfileId = profileId;
    this.guardianCredential = guardianCredential;
  }
}

class _ControllableConnectivity implements ConnectivitySource {
  _ControllableConnectivity({required bool initiallyOnline})
    : _online = initiallyOnline;

  bool _online;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  @override
  Future<bool> get isOnline async => _online;

  @override
  Stream<bool> get changes => _changes.stream;

  @override
  Future<void> dispose() => _changes.close();

  void setOnline(bool online) {
    _online = online;
    _changes.add(online);
  }
}

class _InMemoryCredentials implements SyncCredentialStore {
  final Map<String, String> tokens = {};

  @override
  Future<String?> read(String profileId) async => tokens[profileId];

  @override
  Future<void> write(String profileId, String token) async {
    tokens[profileId] = token;
  }

  @override
  Future<void> delete(String profileId) async {
    tokens.remove(profileId);
  }
}

class _FakeGuardianAccess implements GuardianAccess {
  @override
  Future<bool> hasPin() async => false;

  @override
  Future<void> setPin(String pin) async {}

  @override
  Future<bool> verifyPin(String pin) async => false;

  @override
  Future<bool> canUseBiometrics() async => false;

  @override
  Future<bool> authenticateWithBiometrics() async => false;
}
