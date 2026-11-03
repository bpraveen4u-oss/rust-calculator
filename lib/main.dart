import 'package:flutter/widgets.dart';

import 'app/default_dependencies.dart';
import 'app/learning_calculator_app.dart';

void main() {
  runApp(
    LearningCalculatorApp(
      localStore: OfflineLocalStore(),
      syncClient: DisabledSyncClient(),
    ),
  );
}
