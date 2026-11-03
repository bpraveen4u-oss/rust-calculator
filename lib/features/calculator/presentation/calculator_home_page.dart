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
  List<LearnerProfile> _profiles = [];
  List<CalculationHistoryEntry> _history = [];
  LearnerProfile? _activeProfile;
  EvaluationOutcome? _outcome;
  DetailedEvaluation? _detailedEvaluation;
  String? _hint;
  WorkedExplanation? _workedExplanation;
  bool _showDecimal = false;
  String? _lastSavedExpression;

  @override
  void initState() {
    super.initState();
    _storeReady = _loadLearners();
  }

  Future<void> _loadLearners() async {
    await widget.localStore.initialize();
    _profiles = await widget.localStore.getProfiles();
    if (_profiles.isEmpty) {
      _profiles = [await widget.localStore.createProfile(grade: 3)];
    }
    _activeProfile = _profiles.first;
    _history = await widget.localStore.getHistory(_activeProfile!.id);
  }

  @override
  void dispose() {
    _expressionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSaved =
        _lastSavedExpression != null &&
        _lastSavedExpression == _expressionController.text.trim();
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
          if (snapshot.hasError) {
            return const Center(
              child: Semantics(
                liveRegion: true,
                child: Text('Unable to load the learner profile.'),
              ),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ListView(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _profileSelector(),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          key: const Key('add-learner'),
                          tooltip: 'Add learner profile',
                          onPressed: _addLearner,
                          icon: const Icon(Icons.person_add_alt_1),
                        ),
                        OutlinedButton.icon(
                          key: const Key('show-history'),
                          onPressed: _showHistory,
                          icon: const Icon(Icons.history),
                          label: const Text('History'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
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
                          onChanged: _updateGrade,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('expression-input'),
                      controller: _expressionController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Enter a calculation',
                        hintText: 'For example, 3/4 + 1/4',
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _saveCalculation(),
                      onChanged: (expression) {
                        _evaluateExpression(expression);
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_outcome case EvaluationSuccess(:final value))
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Answer'),
                          Semantics(
                            liveRegion: true,
                            label: 'Answer, ${value.toString()}',
                            child: SelectableText(
                              value.toString(),
                              key: const Key('calculation-result'),
                              style:
                                  Theme.of(context).textTheme.headlineMedium,
                            ),
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
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            key: const Key('save-calculation'),
                            onPressed: isSaved ? null : _saveCalculation,
                            icon: const Icon(Icons.bookmark_add_outlined),
                            label: Text(
                              isSaved ? 'Saved to history' : 'Save to history',
                            ),
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
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        semanticsLabel: 'Invalid calculation. $message.',
                      ),
                    const SizedBox(height: 16),
                    _calculatorKeypad(),
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

  LearnerGrade get _grade => LearnerGrade.values.firstWhere(
        (grade) => grade.number == _activeProfile!.grade,
      );

  Widget _profileSelector() {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Learner profile',
        border: OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: const Key('learner-profile'),
          value: _activeProfile!.id,
          isExpanded: true,
          items: [
            for (var index = 0; index < _profiles.length; index++)
              DropdownMenuItem(
                value: _profiles[index].id,
                child: Text('Learner ${index + 1}'),
              ),
          ],
          onChanged: _selectLearner,
        ),
      ),
    );
  }

  Widget _calculatorKeypad() {
    const keys = [
      _CalculatorKey('7', label: '7'),
      _CalculatorKey('8', label: '8'),
      _CalculatorKey('9', label: '9'),
      _CalculatorKey('÷', label: 'Divide', value: '÷'),
      _CalculatorKey('4', label: '4'),
      _CalculatorKey('5', label: '5'),
      _CalculatorKey('6', label: '6'),
      _CalculatorKey('×', label: 'Multiply', value: '×'),
      _CalculatorKey('1', label: '1'),
      _CalculatorKey('2', label: '2'),
      _CalculatorKey('3', label: '3'),
      _CalculatorKey('−', label: 'Subtract', value: '−'),
      _CalculatorKey('(', label: 'Open parenthesis'),
      _CalculatorKey('0', label: '0'),
      _CalculatorKey(')', label: 'Close parenthesis'),
      _CalculatorKey('+', label: 'Add'),
      _CalculatorKey('.', label: 'Decimal point'),
      _CalculatorKey('/', label: 'Fraction bar'),
      _CalculatorKey('Clear', label: 'Clear calculation'),
      _CalculatorKey('⌫', label: 'Delete last character'),
    ];

    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1,
      children: [
        for (final key in keys)
          Semantics(
            button: true,
            label: key.label,
            child: ExcludeSemantics(
              child: OutlinedButton(
                key: Key(
                  'keypad-${key.label.toLowerCase().replaceAll(' ', '-')}',
                ),
                onPressed: () => _pressKey(key),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(52, 52),
                  textStyle: Theme.of(context).textTheme.titleLarge,
                ),
                child: Text(key.symbol),
              ),
            ),
          ),
      ],
    );
  }

  void _pressKey(_CalculatorKey key) {
    if (key.symbol == 'Clear') {
      _expressionController.clear();
      _evaluateExpression('');
      return;
    }
    if (key.symbol == '⌫') {
      _deleteLastCharacter();
      return;
    }

    final value = key.value ?? key.symbol;
    final current = _expressionController.value;
    final selection = current.selection;
    final start = selection.isValid ? selection.start : current.text.length;
    final end = selection.isValid ? selection.end : current.text.length;
    final text = current.text.replaceRange(start, end, value);
    _expressionController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    _evaluateExpression(text);
  }

  void _deleteLastCharacter() {
    final current = _expressionController.value;
    final selection = current.selection;
    final start = selection.isValid ? selection.start : current.text.length;
    final end = selection.isValid ? selection.end : current.text.length;
    final deleteStart = start == end && start > 0 ? start - 1 : start;
    final text = current.text.replaceRange(deleteStart, end, '');
    _expressionController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: deleteStart),
    );
    _evaluateExpression(text);
  }

  void _evaluateExpression(String expression) {
    setState(() {
      if (expression.trim().isEmpty) {
        _detailedEvaluation = null;
        _outcome = null;
        _showDecimal = false;
        _hint = null;
        _workedExplanation = null;
        _lastSavedExpression = null;
        return;
      }
      final evaluation = _evaluator.evaluateWithSteps(expression);
      _detailedEvaluation = evaluation;
      _outcome = evaluation.outcome;
      _showDecimal = false;
      _hint = null;
      _workedExplanation = null;
      _lastSavedExpression = null;
    });
  }

  Future<void> _updateGrade(LearnerGrade? grade) async {
    if (grade == null) {
      return;
    }
    final profile = _activeProfile!;
    final updated = await widget.localStore.updateProfileGrade(
      profile.id,
      grade: grade.number,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _activeProfile = updated;
      _profiles = [
        for (final item in _profiles)
          if (item.id == updated.id) updated else item,
      ];
      _hint = null;
      _workedExplanation = null;
    });
  }

  Future<void> _selectLearner(String? profileId) async {
    if (profileId == null || profileId == _activeProfile!.id) {
      return;
    }
    final profile = _profiles.firstWhere((item) => item.id == profileId);
    final history = await widget.localStore.getHistory(profile.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _activeProfile = profile;
      _history = history;
      _expressionController.clear();
      _outcome = null;
      _detailedEvaluation = null;
      _hint = null;
      _workedExplanation = null;
      _showDecimal = false;
      _lastSavedExpression = null;
    });
  }

  Future<void> _addLearner() async {
    final profile = await widget.localStore.createProfile(grade: 3);
    if (!mounted) {
      return;
    }
    setState(() {
      _profiles = [..._profiles, profile];
      _activeProfile = profile;
      _history = [];
      _expressionController.clear();
      _outcome = null;
      _detailedEvaluation = null;
      _hint = null;
      _workedExplanation = null;
      _showDecimal = false;
      _lastSavedExpression = null;
    });
  }

  Future<void> _saveCalculation() async {
    final profile = _activeProfile;
    final outcome = _outcome;
    final expression = _expressionController.text.trim();
    if (profile == null ||
        expression.isEmpty ||
        outcome is! EvaluationSuccess ||
        expression == _lastSavedExpression) {
      return;
    }
    final entry = await widget.localStore.addHistoryEntry(
      profileId: profile.id,
      expression: expression,
      result: outcome.value.toString(),
      timestamp: DateTime.now().toUtc(),
      topic: _topicFor(expression),
    );
    if (!mounted || _activeProfile?.id != profile.id) {
      return;
    }
    setState(() {
      _history = [entry, ..._history];
      _lastSavedExpression = expression;
    });
  }

  String _topicFor(String expression) {
    if (expression.contains('/')) {
      return 'fractions';
    }
    if (expression.contains('.')) {
      return 'decimals';
    }
    if (expression.contains('×') || expression.contains('*')) {
      return 'multiplication';
    }
    if (expression.contains('÷')) {
      return 'division';
    }
    if (expression.contains('-') || expression.contains('−')) {
      return 'subtraction';
    }
    return 'addition';
  }

  Future<void> _showHistory() async {
    final profile = _activeProfile!;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Calculation history for ${_profileLabel(profile)}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      key: const Key('close-history'),
                      tooltip: 'Close history',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Divider(),
                if (_history.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('No calculations yet'),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        final entry = _history[index];
                        final localTime = entry.timestamp.toLocal();
                        final date = MaterialLocalizations.of(context)
                            .formatShortDate(localTime);
                        final time = MaterialLocalizations.of(context)
                            .formatTimeOfDay(
                          TimeOfDay.fromDateTime(localTime),
                        );
                        return ListTile(
                          title: Text(
                            '${entry.expression} = ${entry.result}',
                          ),
                          subtitle: Text('${entry.topic} · $date · $time'),
                          contentPadding: EdgeInsets.zero,
                          onTap: () {
                            Navigator.pop(context);
                            _expressionController.text = entry.expression;
                            _evaluateExpression(entry.expression);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _profileLabel(LearnerProfile profile) =>
      'Learner ${_profiles.indexOf(profile) + 1}';
}

class _CalculatorKey {
  const _CalculatorKey(this.symbol, {required this.label, this.value});

  final String symbol;
  final String label;
  final String? value;
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
