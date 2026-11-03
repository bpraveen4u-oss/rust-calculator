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
