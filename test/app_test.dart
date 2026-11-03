import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/app/app_dependencies.dart';
import '../lib/app/learning_calculator_app.dart';
import '../lib/features/guardian/guardian_access.dart';

void main() {
  testWidgets(
    'opens the calculator offline using injected app dependencies',
    (tester) async {
      final localStore = _InMemoryLocalStore();
      final syncClient = _FakeSyncClient();

      await tester.pumpWidget(
        LearningCalculatorApp(
          localStore: localStore,
          syncClient: syncClient,
          guardianAccess: _FakeGuardianAccess(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Calculator'), findsOneWidget);
      expect(find.byKey(const Key('expression-input')), findsOneWidget);
      expect(localStore.initialized, isTrue);
      expect(syncClient.syncRequests, 0);
      expect(find.text('Incomplete expression'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('expression-input')),
        '24 ÷ 6',
      );

      expect(find.text('24 ÷ 6'), findsOneWidget);
      expect(
        tester.widget<SelectableText>(
          find.byKey(const Key('calculation-result')),
        ).data,
        '4',
      );

      await tester.enterText(
        find.byKey(const Key('expression-input')),
        '1/3',
      );
      expect(
        tester.widget<SelectableText>(
          find.byKey(const Key('calculation-result')),
        ).data,
        '1/3',
      );
      expect(find.text('≈ 0.333333'), findsNothing);

      await tester.tap(find.text('Show decimal'));
      await tester.pumpAndSettle();
      expect(find.text('≈ 0.333333'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('expression-input')),
        '2 +',
      );
      expect(find.text('Incomplete expression'), findsOneWidget);
    },
  );

  testWidgets(
    'reveals grade-aware help separately and hides it for invalid input',
    (tester) async {
      await tester.pumpWidget(
        LearningCalculatorApp(
          localStore: _InMemoryLocalStore(),
          syncClient: _FakeSyncClient(),
          guardianAccess: _FakeGuardianAccess(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('expression-input')),
        '8 × 3',
      );

      expect(
        tester.widget<SelectableText>(
          find.byKey(const Key('calculation-result')),
        ).data,
        '24',
      );
      expect(find.byKey(const Key('calculation-hint')), findsNothing);
      expect(find.text('Worked steps'), findsNothing);

      await tester.tap(find.byKey(const Key('learner-grade')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grade 4').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('show-hint')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Grade 4 tip:'), findsOneWidget);

      await tester.tap(find.byKey(const Key('show-worked-steps')));
      await tester.pumpAndSettle();
      expect(find.text('Worked steps'), findsOneWidget);
      expect(find.textContaining('8 × 3 = 24'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('expression-input')),
        '8 + @',
      );
      expect(find.byKey(const Key('calculation-error')), findsOneWidget);
      expect(find.byKey(const Key('calculation-hint')), findsNothing);
      expect(find.text('Worked steps'), findsNothing);
    },
  );

  testWidgets(
    'saves calculations in the selected learner history and keeps profiles separate',
    (tester) async {
      final localStore = _InMemoryLocalStore();
      await tester.pumpWidget(
        LearningCalculatorApp(
          localStore: localStore,
          syncClient: _FakeSyncClient(),
          guardianAccess: _FakeGuardianAccess(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('learner-grade')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grade 4').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('expression-input')),
        '3/4 + 1/4',
      );
      expect(
        tester.widget<SelectableText>(
          find.byKey(const Key('calculation-result')),
        ).data,
        '1',
      );

      tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('show-history')));
      await tester.pumpAndSettle();
      expect(find.text('3/4 + 1/4 = 1'), findsOneWidget);
      await tester.tap(find.byKey(const Key('close-history')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add-learner')));
      await tester.pumpAndSettle();
      final profiles = await localStore.getProfiles();
      expect(profiles, hasLength(2));
      expect(profiles.map((profile) => profile.grade).toList(), [4, 3]);

      await tester.tap(find.byKey(const Key('show-history')));
      await tester.pumpAndSettle();
      expect(find.text('No calculations yet'), findsOneWidget);
    },
  );

  testWidgets('calculator keys build a calculation with labeled controls', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);

    await tester.pumpWidget(
      LearningCalculatorApp(
        localStore: _InMemoryLocalStore(),
        syncClient: _FakeSyncClient(),
        guardianAccess: _FakeGuardianAccess(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('keypad-8')));
    await tester.tap(find.byKey(const Key('keypad-8')));
    await tester.tap(find.byKey(const Key('keypad-multiply')));
    await tester.tap(find.byKey(const Key('keypad-3')));

    expect(
      tester.widget<SelectableText>(
        find.byKey(const Key('calculation-result')),
      ).data,
      '24',
    );
    expect(find.bySemanticsLabel('Multiply'), findsOneWidget);
  });
}

class _InMemoryLocalStore implements LocalStore {
  bool initialized = false;
  final Map<String, LearnerProfile> _profiles = {};
  final Map<String, List<CalculationHistoryEntry>> _history = {};
  var _nextId = 0;

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<List<LearnerProfile>> getProfiles() async =>
      List.unmodifiable(_profiles.values);

  @override
  Future<LearnerProfile?> getProfile(String profileId) async =>
      _profiles[profileId];

  @override
  Future<LearnerProfile> createProfile({required int grade}) async {
    final profile = LearnerProfile(
      id: 'test-profile-${_nextId++}',
      grade: grade,
      createdAt: DateTime.utc(2026),
    );
    _profiles[profile.id] = profile;
    _history[profile.id] = [];
    return profile;
  }

  @override
  Future<LearnerProfile> updateProfileGrade(
    String profileId, {
    required int grade,
  }) async {
    final current = _profiles[profileId]!;
    final updated = LearnerProfile(
      id: current.id,
      grade: grade,
      createdAt: current.createdAt,
    );
    _profiles[profileId] = updated;
    return updated;
  }

  @override
  Future<CalculationHistoryEntry> addHistoryEntry({
    required String profileId,
    required String expression,
    required String result,
    required DateTime timestamp,
    required String topic,
  }) async {
    final entry = CalculationHistoryEntry(
      id: 'test-history-${_nextId++}',
      profileId: profileId,
      expression: expression,
      result: result,
      timestamp: timestamp,
      topic: topic,
    );
    _history[profileId]!.add(entry);
    return entry;
  }

  @override
  Future<List<CalculationHistoryEntry>> getHistory(String profileId) async =>
      List.unmodifiable(_history[profileId] ?? []);

  @override
  Future<void> clearHistory(String profileId) async {
    _history[profileId]?.clear();
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
  SyncStatus get status => const SyncStatus(phase: SyncPhase.disabled);

  @override
  Stream<SyncStatus> get statusChanges => const Stream<SyncStatus>.empty();

  @override
  bool get pairingAvailable => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> syncPendingChanges() async {
    syncRequests++;
  }

  @override
  Future<void> pairDevice(String localProfileId, String code) async {}

  @override
  Future<String> createPairingCode(String localProfileId) async => '';

  @override
  Future<void> dispose() async {}
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
