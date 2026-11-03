import 'package:flutter_test/flutter_test.dart';

import '../lib/features/calculator/domain/expression_evaluator.dart';

void main() {
  const evaluator = ExpressionEvaluator();

  test('evaluates multi-step expressions with standard precedence', () {
    final result = evaluator.evaluate('2 + 3 × 4 - (8 ÷ 2)');

    expect(result, isA<EvaluationSuccess>());
    expect((result as EvaluationSuccess).value.toString(), '10');
  });

  test('keeps decimal and fraction arithmetic exact', () {
    final result = evaluator.evaluate('1.25 + 1/4');

    expect(result, isA<EvaluationSuccess>());
    expect((result as EvaluationSuccess).value.toString(), '3/2');
  });

  test('evaluates proper and mixed fractions to a simplified result', () {
    final result = evaluator.evaluate('1 1/2 + 2/3');

    expect(result, isA<EvaluationSuccess>());
    expect((result as EvaluationSuccess).value.toString(), '13/6');
  });

  test('offers a decimal equivalent separately from the exact result', () {
    final result = evaluator.evaluate('1/3');

    expect(result, isA<EvaluationSuccess>());
    final value = (result as EvaluationSuccess).value;
    expect(value.toString(), '1/3');
    expect(value.toDecimalString(), '≈ 0.333333');
  });

  test('distinguishes incomplete expressions from invalid ones', () {
    final incomplete = evaluator.evaluate('2 + (3 ×');
    final invalid = evaluator.evaluate('2 + @');
    final divisionByZero = evaluator.evaluate('4 / 0');

    expect(incomplete, isA<EvaluationFailure>());
    expect(
      (incomplete as EvaluationFailure).kind,
      ExpressionErrorKind.incomplete,
    );
    expect(invalid, isA<EvaluationFailure>());
    expect(
      (invalid as EvaluationFailure).kind,
      ExpressionErrorKind.invalid,
    );
    expect(divisionByZero, isA<EvaluationFailure>());
    expect(
      (divisionByZero as EvaluationFailure).kind,
      ExpressionErrorKind.divisionByZero,
    );
  });
}
