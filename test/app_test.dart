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
}

class _FakeSyncClient implements SyncClient {
  int syncRequests = 0;

  @override
  Future<void> syncPendingChanges() async {
    syncRequests++;
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
