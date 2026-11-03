import 'package:flutter/material.dart';

import '../../../app/app_dependencies.dart';

class CalculatorHomePage extends StatefulWidget {
  const CalculatorHomePage({required this.localStore, super.key});

  final LocalStore localStore;

  @override
  State<CalculatorHomePage> createState() => _CalculatorHomePageState();
}

class _CalculatorHomePageState extends State<CalculatorHomePage> {
  late final Future<void> _storeReady;

  @override
  void initState() {
    super.initState();
    _storeReady = widget.localStore.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calculator')),
      body: FutureBuilder<void>(
        future: _storeReady,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: TextField(
                  key: const Key('expression-input'),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Enter a calculation',
                  ),
                  textInputAction: TextInputAction.done,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
