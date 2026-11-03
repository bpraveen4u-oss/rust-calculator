import 'expression_evaluator.dart';

enum LearnerGrade { grade3, grade4, grade5 }

extension LearnerGradeLabel on LearnerGrade {
  int get number => switch (this) {
        LearnerGrade.grade3 => 3,
        LearnerGrade.grade4 => 4,
        LearnerGrade.grade5 => 5,
      };

  String get label => 'Grade $number';
}

final class FractionBar {
  const FractionBar({required this.numerator, required this.denominator});

  final int numerator;
  final int denominator;
}

final class WorkedExplanation {
  const WorkedExplanation({required this.steps, this.fractionBar});

  final List<String> steps;
  final FractionBar? fractionBar;
}

class LearningContentGenerator {
  const LearningContentGenerator();

  static const _evaluator = ExpressionEvaluator();

  String? hintFor(String expression, LearnerGrade grade) {
    final evaluation = _evaluator.evaluateWithSteps(expression);
    final outcome = evaluation.outcome;
    if (outcome is! EvaluationSuccess || evaluation.steps.isEmpty) {
      return null;
    }

    final steps = _contentSteps(expression, evaluation.steps, outcome.value);
    final step = steps.first;
    final left = _format(step.left, expression);
    final right = _format(step.right, expression);
    final hint = _isFractionExpression(expression)
        ? _fractionHint(step.operator, grade)
        : _operationHint(step, grade, left, right);
    return '${grade.label} tip: $hint';
  }

  WorkedExplanation? workedExplanationFor(
    String expression,
    LearnerGrade grade,
  ) {
    final evaluation = _evaluator.evaluateWithSteps(expression);
    final outcome = evaluation.outcome;
    if (outcome is! EvaluationSuccess || evaluation.steps.isEmpty) {
      return null;
    }
    final value = outcome.value;
    final calculationSteps =
        _contentSteps(expression, evaluation.steps, value);

    final steps = <String>[];
    if (calculationSteps.length > 1 || expression.contains('(')) {
      steps.add(switch (grade) {
        LearnerGrade.grade3 =>
          'Work one operation at a time. Do the parentheses first, then '
          'multiplication and division, then addition and subtraction.',
        LearnerGrade.grade4 =>
          'Follow the order of operations: parentheses, multiplication and '
          'division, then addition and subtraction.',
        LearnerGrade.grade5 =>
          'Use the order of operations: parentheses first, then multiplication '
          'and division, then addition and subtraction.',
      });
    }

    steps.addAll(
      calculationSteps.map(
        (step) => _workedStep(step, grade, expression),
      ),
    );
    return WorkedExplanation(
      steps: List.unmodifiable(steps),
      fractionBar: _fractionBar(expression, calculationSteps, value),
    );
  }

  String _workedStep(
    CalculationStep step,
    LearnerGrade grade,
    String expression,
  ) {
    final left = _format(step.left, expression);
    final right = _format(step.right, expression);
    final result = _format(step.result, expression);
    final calculation = '$left ${step.operator} $right = $result';

    if (_isFractionExpression(expression) &&
        (step.operator == '+' || step.operator == '−')) {
      final denominator = _leastCommonMultiple(
        step.left.denominator,
        step.right.denominator,
      );
      final leftNumerator =
          step.left.numerator * (denominator ~/ step.left.denominator);
      final rightNumerator =
          step.right.numerator * (denominator ~/ step.right.denominator);
      final equivalentCalculation = '$leftNumerator/$denominator '
          '${step.operator} $rightNumerator/$denominator = $result';
      return switch (grade) {
        LearnerGrade.grade3 =>
          'Use equal-sized parts: $equivalentCalculation.',
        LearnerGrade.grade4 =>
          'Rename the fractions with denominator $denominator: '
          '$equivalentCalculation.',
        LearnerGrade.grade5 =>
          'Use a common denominator of $denominator: '
          '$equivalentCalculation.',
      };
    }
    if (_isFractionExpression(expression) && step.operator == '×') {
      final numeratorCalculation =
          '(${step.left.numerator} × ${step.right.numerator})/'
          '(${step.left.denominator} × ${step.right.denominator}) = $result';
      return switch (grade) {
        LearnerGrade.grade3 =>
          'Multiply the top numbers and the bottom numbers: '
          '$numeratorCalculation.',
        LearnerGrade.grade4 =>
          'Multiply the numerators and denominators: '
          '$numeratorCalculation.',
        LearnerGrade.grade5 =>
          'Multiply the numerators and denominators, then simplify: '
          '$numeratorCalculation.',
      };
    }
    if (_isFractionExpression(expression) && step.operator == '÷') {
      final reciprocal = ExactRational(
        step.right.denominator,
        step.right.numerator,
      );
      final reciprocalCalculation =
          '$left × $reciprocal = $result';
      return switch (grade) {
        LearnerGrade.grade3 =>
          'Keep the first fraction, flip the second, and multiply: '
          '$reciprocalCalculation.',
        LearnerGrade.grade4 =>
          'Use the reciprocal of the second fraction: '
          '$reciprocalCalculation.',
        LearnerGrade.grade5 =>
          'Multiply by the reciprocal of the second fraction: '
          '$reciprocalCalculation.',
      };
    }

    return switch (grade) {
      LearnerGrade.grade3 => switch (step.operator) {
          '+' => 'Add the two amounts: $calculation.',
          '−' => 'Take away the second amount: $calculation.',
          '×' => 'Make $left groups of $right: $calculation.',
          _ => 'Count how many groups of $right fit in $left: $calculation.',
        },
      LearnerGrade.grade4 =>
        'Use the ${_operationName(step.operator)} fact: $calculation.',
      LearnerGrade.grade5 =>
        'Apply ${_operationName(step.operator)} and keep the exact values: '
        '$calculation.',
    };
  }

  FractionBar? _fractionBar(
    String expression,
    List<CalculationStep> steps,
    ExactRational value,
  ) {
    if (!_isFractionExpression(expression) ||
        !steps.any((step) => step.operator == '+' || step.operator == '−') ||
        value.numerator <= BigInt.zero ||
        value.numerator > value.denominator ||
        value.denominator > BigInt.from(12)) {
      return null;
    }
    return FractionBar(
      numerator: value.numerator.toInt(),
      denominator: value.denominator.toInt(),
    );
  }

  String _format(ExactRational value, String expression) {
    if (expression.contains('.') && _hasTerminatingDecimal(value.denominator)) {
      return value.toDecimalString();
    }
    return value.toString();
  }

  String _operationHint(
    CalculationStep step,
    LearnerGrade grade,
    String left,
    String right,
  ) {
    return switch (grade) {
      LearnerGrade.grade3 => switch (step.operator) {
          '+' => 'Try adding $left and $right by splitting them into tens '
              'and ones.',
          '−' => 'Try taking $right away from $left, or count back to check.',
          '×' => 'Think of $left × $right as $left equal groups of $right.',
          _ => 'Think: how many groups of $right fit in $left?',
        },
      LearnerGrade.grade4 => switch (step.operator) {
          '+' => 'Use place value to add $left and $right, then check the '
              'total.',
          '−' => 'Use place value to subtract $right from $left, then check '
              'by adding.',
          '×' => 'Use a multiplication fact for $left × $right, then check '
              'with division.',
          _ => 'Use a division fact for $left ÷ $right, then check by '
              'multiplying.',
        },
      LearnerGrade.grade5 => switch (step.operator) {
          '+' => 'Add $left and $right, and use subtraction to check your '
              'sum.',
          '−' => 'Subtract $right from $left, and use addition to check the '
              'difference.',
          '×' => 'Find $left × $right and use the inverse operation to check '
              'your product.',
          _ => 'Find $left ÷ $right and use multiplication to check your '
              'quotient.',
        },
    };
  }

  String _fractionHint(String operator, LearnerGrade grade) {
    return switch (operator) {
      '+' || '−' => switch (grade) {
          LearnerGrade.grade3 =>
            'Check whether the fractions name equal-sized parts before you '
            'combine them.',
          LearnerGrade.grade4 =>
            'Rename the fractions with a shared denominator before you '
            'combine them.',
          LearnerGrade.grade5 =>
            'Find a common denominator before combining the numerators.',
        },
      '×' => switch (grade) {
          LearnerGrade.grade3 =>
            'Think of multiplying fractions as finding a part of a part.',
          LearnerGrade.grade4 =>
            'Multiply the numerators and multiply the denominators.',
          LearnerGrade.grade5 =>
            'Multiply the numerators and denominators, then simplify.',
        },
      _ => switch (grade) {
          LearnerGrade.grade3 =>
            'Ask how many groups of the second fraction fit in the first.',
          LearnerGrade.grade4 =>
            'Use a related multiplication fact to check the division.',
          LearnerGrade.grade5 =>
            'Multiply by the reciprocal of the second fraction.',
        },
    };
  }

  bool _isFractionExpression(String expression) =>
      _fractionCalculationMatch(expression) != null;

  List<CalculationStep> _contentSteps(
    String expression,
    List<CalculationStep> evaluatedSteps,
    ExactRational value,
  ) {
    final match = _fractionCalculationMatch(expression);
    if (match == null) {
      return evaluatedSteps;
    }

    final operator = switch (match.group(2)) {
      '+' => '+',
      '-' || '−' => '−',
      '*' || '×' => '×',
      _ => '÷',
    };
    return [
      CalculationStep(
        left: _parseFraction(match.group(1)!),
        operator: operator,
        right: _parseFraction(match.group(3)!),
        result: value,
      ),
    ];
  }

  RegExpMatch? _fractionCalculationMatch(String expression) =>
      RegExp(
        r'^\s*(\d+\s+\d+/\d+|\d+/\d+)\s*([+\-−×*÷/])\s*(\d+\s+\d+/\d+|\d+/\d+)\s*$',
      ).firstMatch(expression);

  ExactRational _parseFraction(String source) {
    final parts = source.trim().split(RegExp(r'\s+'));
    final fraction = parts.last.split('/');
    final numerator = BigInt.parse(fraction[0]);
    final denominator = BigInt.parse(fraction[1]);
    if (parts.length == 1) {
      return ExactRational(numerator, denominator);
    }
    return ExactRational(
      BigInt.parse(parts.first) * denominator + numerator,
      denominator,
    );
  }

  bool _hasTerminatingDecimal(BigInt denominator) {
    var remaining = denominator;
    for (final factor in [BigInt.from(2), BigInt.from(5)]) {
      while (remaining % factor == BigInt.zero) {
        remaining ~/= factor;
      }
    }
    return remaining == BigInt.one;
  }

  BigInt _leastCommonMultiple(BigInt left, BigInt right) =>
      left ~/ left.gcd(right) * right;

  String _operationName(String operator) => switch (operator) {
        '+' => 'addition',
        '−' => 'subtraction',
        '×' => 'multiplication',
        _ => 'division',
      };
}
