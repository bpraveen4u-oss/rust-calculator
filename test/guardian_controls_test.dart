import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/app/app_dependencies.dart';
import '../lib/app/learning_calculator_app.dart';
import '../lib/features/guardian/guardian_access.dart';

void main() {
  testWidgets(
    'guardian PIN protects sync disclosures and pairing stays unavailable',
    (tester) async {
      final guardianAccess = _FakeGuardianAccess();
      final syncClient = _FakeSyncClient();
      await tester.pumpWidget(
        LearningCalculatorApp(
          localStore: _InMemoryLocalStore(),
          syncClient: syncClient,
          guardianAccess: guardianAccess,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardian controls'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('guardian-pin')),
        '123456',
      );
      await tester.enterText(
        find.byKey(const Key('guardian-pin-confirm')),
        '123455',
      );
      await tester.ensureVisible(find.byKey(const Key('guardian-save-pin')));
      await tester.tap(find.byKey(const Key('guardian-save-pin')));
      await tester.pumpAndSettle();
      expect(find.text('PINs do not match.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('guardian-pin-confirm')),
        '123456',
      );
      await tester.tap(find.byKey(const Key('guardian-save-pin')));
      await tester.pumpAndSettle();

      expect(find.text('Guardian controls'), findsWidgets);
      expect(
        find.textContaining(
          'Production cloud sync remains disabled pending legal/privacy review.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('no recovery key'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('guardian-start-pairing')),
        100,
      );
      expect(
        tester.widget<FilledButton>(
          find.byKey(const Key('guardian-start-pairing')),
        ).onPressed,
        isNull,
      );
      expect(guardianAccess.savedPin, '123456');
      expect(find.textContaining('does not provide consent'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('guardian-pairing-opt-in')),
        100,
      );
      await tester.tap(find.byKey(const Key('guardian-pairing-opt-in')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(
          find.byKey(const Key('guardian-start-pairing')),
        ).onPressed,
        isNotNull,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('guardian-start-pairing')),
        100,
      );
      await tester.tap(find.byKey(const Key('guardian-start-pairing')));
      await tester.pumpAndSettle();
      expect(
        find.text('Pairing is not available in this experiment.'),
        findsOneWidget,
      );
      expect(syncClient.syncRequests, 0);
    },
  );

  testWidgets(
    'a guardian can erase cloud history without clearing local data',
    (tester) async {
      final localStore = _InMemoryLocalStore();
      final syncClient = _FakeSyncClient()..pairingAvailable = true;
      await tester.pumpWidget(
        LearningCalculatorApp(
          localStore: localStore,
          syncClient: syncClient,
          guardianAccess: _FakeGuardianAccess()..savedPin = '654321',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardian controls'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('guardian-unlock-pin')),
        '654321',
      );
      await tester.tap(find.byKey(const Key('guardian-unlock')));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('guardian-erase-credential')),
        100,
      );
      await tester.enterText(
        find.byKey(const Key('guardian-erase-credential')),
        'guardian-secret',
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('guardian-erase-cloud-history')),
        100,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const Key('guardian-erase-cloud-history')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This permanently deletes cloud history for this learner. '
          'Local history on this device will not be deleted.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('guardian-confirm-cloud-erase')));
      await tester.pumpAndSettle();

      expect(syncClient.erasedProfileId, 'local-profile-1');
      expect(syncClient.erasedCredential, 'guardian-secret');
      expect(localStore.clearHistoryCalls, 0);
      expect(find.text('Cloud history deleted.'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('guardian-erase-credential')),
            )
            .controller!
            .text,
        isEmpty,
      );
    },
  );

  testWidgets(
    'cloud history erasure reports failure without exposing secrets',
    (tester) async {
      final syncClient = _FakeSyncClient()
        ..pairingAvailable = true
        ..eraseError = true;
      await tester.pumpWidget(
        LearningCalculatorApp(
          localStore: _InMemoryLocalStore(),
          syncClient: syncClient,
          guardianAccess: _FakeGuardianAccess()..savedPin = '654321',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardian controls'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('guardian-unlock-pin')),
        '654321',
      );
      await tester.tap(find.byKey(const Key('guardian-unlock')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('guardian-erase-credential')),
        100,
      );
      await tester.enterText(
        find.byKey(const Key('guardian-erase-credential')),
        'guardian-secret',
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('guardian-erase-cloud-history')),
        100,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const Key('guardian-erase-cloud-history')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('guardian-confirm-cloud-erase')));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not delete cloud history. Check the credential and '
            'connection, then try again.'),
        findsOneWidget,
      );
      expect(find.text('guardian-secret'), findsNothing);
    },
  );

  testWidgets('a returning guardian must unlock the protected area', (
    tester,
  ) async {
    final guardianAccess = _FakeGuardianAccess()..savedPin = '654321';
    await tester.pumpWidget(
      LearningCalculatorApp(
        localStore: _InMemoryLocalStore(),
        syncClient: _FakeSyncClient(),
        guardianAccess: guardianAccess,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guardian controls'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guardian-unlock-pin')), findsOneWidget);
    expect(
      find.textContaining(
        'Production cloud sync remains disabled pending legal/privacy review.',
      ),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const Key('guardian-unlock-pin')),
      '000000',
    );
    await tester.tap(find.byKey(const Key('guardian-unlock')));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect PIN.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('guardian-unlock-pin')),
      '654321',
    );
    await tester.tap(find.byKey(const Key('guardian-unlock')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Production cloud sync remains disabled pending legal/privacy review.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a supported platform biometric can unlock guardian controls', (
    tester,
  ) async {
    final guardianAccess = _FakeGuardianAccess()
      ..savedPin = '654321'
      ..biometricsAvailable = true
      ..biometricResult = true;
    await tester.pumpWidget(
      LearningCalculatorApp(
        localStore: _InMemoryLocalStore(),
        syncClient: _FakeSyncClient(),
        guardianAccess: guardianAccess,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guardian controls'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use biometrics'));
    await tester.pumpAndSettle();

    expect(guardianAccess.biometricAttempts, 1);
    expect(
      find.textContaining(
        'Production cloud sync remains disabled pending legal/privacy review.',
      ),
      findsOneWidget,
    );
  });
}

class _FakeGuardianAccess implements GuardianAccess {
  String? savedPin;
  bool biometricsAvailable = false;
  bool biometricResult = false;
  int biometricAttempts = 0;

  @override
  Future<bool> hasPin() async => savedPin != null;

  @override
  Future<void> setPin(String pin) async {
    savedPin = pin;
  }

  @override
  Future<bool> verifyPin(String pin) async => savedPin == pin;

  @override
  Future<bool> canUseBiometrics() async => biometricsAvailable;

  @override
  Future<bool> authenticateWithBiometrics() async {
    biometricAttempts++;
    return biometricResult;
  }
}

class _InMemoryLocalStore implements LocalStore {
  int clearHistoryCalls = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<LearnerProfile>> getProfiles() async => [];

  @override
  Future<LearnerProfile?> getProfile(String profileId) async => null;

  @override
  Future<LearnerProfile> createProfile({required int grade}) {
    return Future.value(
      LearnerProfile(
        id: 'local-profile-1',
        grade: grade,
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Future<LearnerProfile> updateProfileGrade(
    String profileId, {
    required int grade,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<CalculationHistoryEntry> addHistoryEntry({
    required String profileId,
    required String expression,
    required String result,
    required DateTime timestamp,
    required String topic,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<CalculationHistoryEntry>> getHistory(String profileId) async =>
      [];

  @override
  Future<void> clearHistory(String profileId) async {
    clearHistoryCalls++;
  }

  @override
  Future<void> linkSyncProfile({
    required String localProfileId,
    required String remoteProfileId,
  }) async {}

  @override
  Future<List<SyncProfileState>> getSyncProfiles() async => [];

  @override
  Future<PendingSyncChanges?> getPendingSyncChanges(String profileId) async =>
      null;

  @override
  Future<int> getPendingSyncCount() async => 0;

  @override
  Future<void> mergeRemoteProfileGrade(
    String profileId, {
    required int grade,
  }) async {}

  @override
  Future<void> mergeRemoteHistory(
    String profileId,
    List<CalculationHistoryEntry> entries,
  ) async {}

  @override
  Future<void> markSyncSucceeded({
    required String profileId,
    required DateTime syncedAt,
    required int? syncedGrade,
    required List<String> syncedHistoryIds,
  }) async {}
}

class _FakeSyncClient implements SyncClient {
  int syncRequests = 0;
  @override
  bool pairingAvailable = false;
  bool eraseError = false;
  String? erasedProfileId;
  String? erasedCredential;

  @override
  SyncStatus get status => const SyncStatus(phase: SyncPhase.disabled);

  @override
  Stream<SyncStatus> get statusChanges => const Stream<SyncStatus>.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> syncPendingChanges() async {
    syncRequests++;
  }

  @override
  Future<void> eraseCloudHistory(
    String localProfileId,
    String guardianCredential,
  ) async {
    if (eraseError) throw StateError('unauthorized');
    erasedProfileId = localProfileId;
    erasedCredential = guardianCredential;
  }

  @override
  Future<void> pairDevice(String localProfileId, String code) async {}

  @override
  Future<String> createPairingCode(String localProfileId) async => '';

  @override
  Future<void> dispose() async {}
}
