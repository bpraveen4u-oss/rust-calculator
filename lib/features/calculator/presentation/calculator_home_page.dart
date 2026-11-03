import 'package:flutter/material.dart';

import '../../../app/app_dependencies.dart';
import '../../guardian/guardian_access.dart';
import '../../guardian/presentation/guardian_controls_page.dart';
import '../domain/expression_evaluator.dart';
import '../domain/learning_content.dart';

class CalculatorHomePage extends StatefulWidget {
  const CalculatorHomePage({
    required this.localStore,
    required this.guardianAccess,
    super.key,
  });

  final LocalStore localStore;
  final GuardianAccess guardianAccess;

  @override
  State<CalculatorHomePage> createState() => _CalculatorHomePageState();
}

class _CalculatorHomePageState extends State<CalculatorHomePage> {
  late final Future<void> _storeReady;
  final _expressionController = TextEditingController();
  final _evaluator = const ExpressionEvaluator();
  final _learningContent = const LearningContentGenerator();
  EvaluationOutcome? _outcome;
  DetailedEvaluation? _detailedEvaluation;
  LearnerGrade _grade = LearnerGrade.grade3;
  String? _hint;
  WorkedExplanation? _workedExplanation;
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
      appBar: AppBar(
        title: const Text('Calculator'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GuardianControlsPage(
                    guardianAccess: widget.guardianAccess,
                  ),
                ),
              );
            },
            child: const Text('Guardian controls'),
          ),
        ],
      ),
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
                child: ListView(
                  shrinkWrap: true,
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
                          final evaluation =
                              _evaluator.evaluateWithSteps(expression);
                          _detailedEvaluation = evaluation;
                          _outcome = evaluation.outcome;
                          _showDecimal = false;
                          _hint = null;
                          _workedExplanation = null;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Your grade',
                        border: OutlineInputBorder(),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<LearnerGrade>(
                          key: const Key('learner-grade'),
                          value: _grade,
                          isExpanded: true,
                          items: LearnerGrade.values
                              .map(
                                (grade) => DropdownMenuItem(
                                  value: grade,
                                  child: Text(grade.label),
                                ),
                              )
                              .toList(),
                          onChanged: (grade) {
                            if (grade == null) {
                              return;
                            }
                            setState(() {
                              _grade = grade;
                              _hint = null;
                              _workedExplanation = null;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
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
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                key: const Key('show-hint'),
                                onPressed: _canExplain
                                    ? () {
                                        setState(() {
                                          _hint = _learningContent.hintFor(
                                            _expressionController.text,
                                            _grade,
                                          );
                                        });
                                      }
                                    : null,
                                child: const Text('Show hint'),
                              ),
                              TextButton(
                                key: const Key('show-worked-steps'),
                                onPressed: _canExplain
                                    ? () {
                                        setState(() {
                                          _workedExplanation =
                                              _learningContent
                                                  .workedExplanationFor(
                                            _expressionController.text,
                                            _grade,
                                          );
                                        });
                                      }
                                    : null,
                                child: const Text('Show worked steps'),
                              ),
                            ],
                          ),
                          if (_hint case final hint?)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                hint,
                                key: const Key('calculation-hint'),
                              ),
                            ),
                          if (_workedExplanation case final explanation?)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Worked steps'),
                                  for (var index = 0;
                                      index < explanation.steps.length;
                                      index++)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        '${index + 1}. '
                                        '${explanation.steps[index]}',
                                      ),
                                    ),
                                  if (explanation.fractionBar case
                                      final fractionBar?)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: _FractionBarVisual(
                                        fractionBar: fractionBar,
                                      ),
                                    ),
                                ],
                              ),
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

  bool get _canExplain {
    final evaluation = _detailedEvaluation;
    return evaluation != null &&
        evaluation.outcome is EvaluationSuccess &&
        evaluation.steps.isNotEmpty;
  }
}

class _FractionBarVisual extends StatelessWidget {
  const _FractionBarVisual({required this.fractionBar});

  final FractionBar fractionBar;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: '${fractionBar.numerator} of ${fractionBar.denominator} equal '
          'parts shaded',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${fractionBar.numerator} of ${fractionBar.denominator} equal '
              'parts shaded',
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (var part = 0; part < fractionBar.denominator; part++)
                  Expanded(
                    child: Container(
                      height: 28,
                      margin: const EdgeInsets.only(right: 2),
                      decoration: BoxDecoration(
                        color: part < fractionBar.numerator
                            ? colors.primaryContainer
                            : colors.surface,
                        border: Border.all(color: colors.outline),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
