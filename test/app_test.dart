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

  testWidgets(
    'reveals grade-aware help separately and hides it for invalid input',
    (tester) async {
      await tester.pumpWidget(
        LearningCalculatorApp(
          localStore: _InMemoryLocalStore(),
          syncClient: _FakeSyncClient(),
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
