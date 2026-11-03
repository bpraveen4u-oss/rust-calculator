import 'package:flutter/widgets.dart';

import 'app/default_dependencies.dart';
import 'app/learning_calculator_app.dart';
import 'app/sqlite_local_store.dart';
import 'features/guardian/guardian_access.dart';

void main() {
  final localStore = SqliteLocalStore();
  runApp(
    LearningCalculatorApp(
      localStore: localStore,
      syncClient: createDefaultSyncClient(localStore),
      guardianAccess: SecureGuardianAccess(),
    ),
  );
}
