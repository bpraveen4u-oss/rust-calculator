import 'package:flutter/material.dart';

import '../features/calculator/presentation/calculator_home_page.dart';
import '../features/guardian/guardian_access.dart';
import 'app_dependencies.dart';

class LearningCalculatorApp extends StatelessWidget {
  const LearningCalculatorApp({
    required this.localStore,
    required this.syncClient,
    required this.guardianAccess,
    super.key,
  });

  final LocalStore localStore;
  final SyncClient syncClient;
  final GuardianAccess guardianAccess;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Learning Calculator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF315D75)),
        useMaterial3: true,
      ),
      home: CalculatorHomePage(
        localStore: localStore,
        guardianAccess: guardianAccess,
      ),
    );
  }
}
