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
        find.text('Cloud sync is disabled pending legal/privacy review.'),
        findsOneWidget,
      );
      expect(find.textContaining('No recovery key'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(
          find.byKey(const Key('guardian-start-pairing')),
        ).onPressed,
        isNull,
      );
      expect(guardianAccess.savedPin, '123456');
      expect(find.textContaining('does not provide consent'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('guardian-pairing-opt-in')),
      );
      await tester.tap(find.byKey(const Key('guardian-pairing-opt-in')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(
          find.byKey(const Key('guardian-start-pairing')),
        ).onPressed,
        isNotNull,
      );
      await tester.ensureVisible(
        find.byKey(const Key('guardian-start-pairing')),
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
      find.text('Cloud sync is disabled pending legal/privacy review.'),
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
      find.text('Cloud sync is disabled pending legal/privacy review.'),
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
      find.text('Cloud sync is disabled pending legal/privacy review.'),
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
  @override
  Future<void> initialize() async {}

  @override
  Future<List<LearnerProfile>> getProfiles() async => [];

  @override
  Future<LearnerProfile?> getProfile(String profileId) async => null;

  @override
  Future<LearnerProfile> createProfile({required int grade}) {
    throw UnimplementedError();
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
  Future<void> clearHistory(String profileId) async {}
}

class _FakeSyncClient implements SyncClient {
  int syncRequests = 0;

  @override
  Future<void> syncPendingChanges() async {
    syncRequests++;
  }
}
