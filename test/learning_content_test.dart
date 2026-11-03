import 'package:flutter_test/flutter_test.dart';

import '../lib/features/calculator/domain/learning_content.dart';

void main() {
  const content = LearningContentGenerator();

  test('hints are repeatable and use the selected grade language', () {
    final gradeThreeHint = content.hintFor('8 × 3', LearnerGrade.grade3);
    final gradeFourHint = content.hintFor('8 × 3', LearnerGrade.grade4);
    final gradeFiveHint = content.hintFor('8 × 3', LearnerGrade.grade5);

    expect(
      gradeThreeHint,
      'Grade 3 tip: Think of 8 × 3 as 8 equal groups of 3.',
    );
    expect(content.hintFor('8 × 3', LearnerGrade.grade3), gradeThreeHint);
    expect(gradeFourHint, isNot(gradeThreeHint));
    expect(gradeFiveHint, startsWith('Grade 5 tip:'));
    expect(gradeFiveHint, isNot(gradeFourHint));
  });

  test('hints cover addition, subtraction, and division', () {
    expect(
      content.hintFor('18 + 5', LearnerGrade.grade3),
      contains('tens and ones'),
    );
    expect(
      content.hintFor('18 − 5', LearnerGrade.grade4),
      contains('check by adding'),
    );
    expect(
      content.hintFor('24 ÷ 6', LearnerGrade.grade3),
      contains('how many groups of 6 fit in 24'),
    );
  });

  test('worked steps show each calculation in order of operations', () {
    final explanation = content.workedExplanationFor(
      '2 + 3 × 4',
      LearnerGrade.grade5,
    );

    expect(explanation, isNotNull);
    expect(explanation!.steps, [
      'Use the order of operations: parentheses first, then multiplication '
          'and division, then addition and subtraction.',
      'Apply multiplication and keep the exact values: 3 × 4 = 12.',
      'Apply addition and keep the exact values: 2 + 12 = 14.',
    ]);
  });

  test('fraction addition explains equal parts and adds a clarifying bar', () {
    final explanation = content.workedExplanationFor(
      '1/4 + 1/4',
      LearnerGrade.grade3,
    );

    expect(
      explanation!.steps.single,
      'Use equal-sized parts: 1/4 + 1/4 = 1/2.',
    );
    expect(explanation.fractionBar?.numerator, 1);
    expect(explanation.fractionBar?.denominator, 2);
  });

  test('fraction multiplication and division explain their fraction rules', () {
    final multiplication = content.workedExplanationFor(
      '1/2 × 2/3',
      LearnerGrade.grade5,
    );
    final division = content.workedExplanationFor(
      '1/2 ÷ 1/4',
      LearnerGrade.grade5,
    );

    expect(
      multiplication!.steps,
      [
        'Multiply the numerators and denominators, then simplify: '
            '(1 × 2)/(2 × 3) = 1/3.',
      ],
    );
    expect(
      division!.steps,
      ['Multiply by the reciprocal of the second fraction: 1/2 × 4 = 2.'],
    );
    expect(division.fractionBar, isNull);
  });

  test('decimal steps keep decimal notation', () {
    final explanation = content.workedExplanationFor(
      '1.5 + 2.25',
      LearnerGrade.grade4,
    );

    expect(explanation!.steps, ['Use the addition fact: 1.5 + 2.25 = 3.75.']);
  });

  test('invalid calculations do not produce hints or worked steps', () {
    expect(content.hintFor('2 + @', LearnerGrade.grade4), isNull);
    expect(
      content.workedExplanationFor('2 + @', LearnerGrade.grade4),
      isNull,
    );
    expect(content.hintFor('2 +', LearnerGrade.grade4), isNull);
    expect(
      content.workedExplanationFor('4 ÷ 0', LearnerGrade.grade5),
      isNull,
    );
  });
}
