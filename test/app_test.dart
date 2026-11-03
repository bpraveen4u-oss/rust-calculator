import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/app/app_dependencies.dart';
import '../lib/app/learning_calculator_app.dart';

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
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Calculator'), findsOneWidget);
      expect(find.byKey(const Key('expression-input')), findsOneWidget);
      expect(localStore.initialized, isTrue);
      expect(syncClient.syncRequests, 0);

      await tester.enterText(
        find.byKey(const Key('expression-input')),
        '24 ÷ 6',
      );

      expect(find.text('24 ÷ 6'), findsOneWidget);
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
