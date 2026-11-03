import 'package:flutter/material.dart';

import '../../../app/app_dependencies.dart';
import '../domain/expression_evaluator.dart';

class CalculatorHomePage extends StatefulWidget {
  const CalculatorHomePage({required this.localStore, super.key});

  final LocalStore localStore;

  @override
  State<CalculatorHomePage> createState() => _CalculatorHomePageState();
}

class _CalculatorHomePageState extends State<CalculatorHomePage> {
  late final Future<void> _storeReady;
  final _expressionController = TextEditingController();
  final _evaluator = const ExpressionEvaluator();
  EvaluationOutcome? _outcome;
  bool _showDecimal = false;

  @override
  void initState() {
    super.initState();
    _storeReady = widget.localStore.initialize();
  }

  @override
  void dispose() {
    _expressionController.dispose();
    super.dispose();
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('expression-input'),
                      controller: _expressionController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Enter a calculation',
                      ),
                      textInputAction: TextInputAction.done,
                      onChanged: (expression) {
                        setState(() {
                          _outcome = _evaluator.evaluate(expression);
                          _showDecimal = false;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_outcome case EvaluationSuccess(:final value))
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Answer'),
                          SelectableText(
                            value.toString(),
                            key: const Key('calculation-result'),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _showDecimal = !_showDecimal;
                              });
                            },
                            child: Text(
                              _showDecimal ? 'Hide decimal' : 'Show decimal',
                            ),
                          ),
                          if (_showDecimal)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Decimal equivalent'),
                                Text(
                                  value.toDecimalString(),
                                  key: const Key('decimal-equivalent'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    if (_outcome case EvaluationFailure(:final message))
                      Text(
                        message,
                        key: const Key('calculation-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
