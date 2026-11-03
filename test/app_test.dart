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

  @override
  Future<void> initialize() async {
    initialized = true;
  }
}

class _FakeSyncClient implements SyncClient {
  int syncRequests = 0;

  @override
  Future<void> syncPendingChanges() async {
    syncRequests++;
  }
}
