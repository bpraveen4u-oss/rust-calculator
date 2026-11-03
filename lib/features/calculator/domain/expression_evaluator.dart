enum ExpressionErrorKind { incomplete, invalid, divisionByZero }

sealed class EvaluationOutcome {
  const EvaluationOutcome();
}

final class EvaluationSuccess extends EvaluationOutcome {
  const EvaluationSuccess(this.value);

  final ExactRational value;
}

final class EvaluationFailure extends EvaluationOutcome {
  const EvaluationFailure(this.kind, this.message);

  final ExpressionErrorKind kind;
  final String message;
}

final class ExactRational {
  factory ExactRational(BigInt numerator, [BigInt? denominator]) {
    var normalizedNumerator = numerator;
    var normalizedDenominator = denominator ?? BigInt.one;
    if (normalizedDenominator == BigInt.zero) {
      throw ArgumentError.value(denominator, 'denominator', 'Cannot be zero');
    }
    if (normalizedDenominator.isNegative) {
      normalizedNumerator = -normalizedNumerator;
      normalizedDenominator = -normalizedDenominator;
    }
    final divisor = normalizedNumerator.abs().gcd(normalizedDenominator);
    return ExactRational._(
      normalizedNumerator ~/ divisor,
      normalizedDenominator ~/ divisor,
    );
  }

  const ExactRational._(this.numerator, this.denominator);

  final BigInt numerator;
  final BigInt denominator;

  ExactRational add(ExactRational other) => ExactRational(
        numerator * other.denominator + other.numerator * denominator,
        denominator * other.denominator,
      );

  ExactRational subtract(ExactRational other) => ExactRational(
        numerator * other.denominator - other.numerator * denominator,
        denominator * other.denominator,
      );

  ExactRational multiply(ExactRational other) => ExactRational(
        numerator * other.numerator,
        denominator * other.denominator,
      );

  ExactRational divide(ExactRational other) => ExactRational(
        numerator * other.denominator,
        denominator * other.numerator,
      );

  ExactRational get negated => ExactRational(-numerator, denominator);

  String toDecimalString({int precision = 6}) {
    var remaining = denominator;
    var twos = 0;
    var fives = 0;
    while (remaining % BigInt.from(2) == BigInt.zero) {
      remaining ~/= BigInt.from(2);
      twos++;
    }
    while (remaining % BigInt.from(5) == BigInt.zero) {
      remaining ~/= BigInt.from(5);
      fives++;
    }

    final isTerminating = remaining == BigInt.one;
    final scale = isTerminating
        ? (twos > fives ? twos : fives)
        : precision;
    final scaleFactor = BigInt.from(10).pow(scale);
    final absoluteScaled = numerator.abs() * scaleFactor;
    var rounded = absoluteScaled ~/ denominator;
    final remainder = absoluteScaled % denominator;
    if (remainder * BigInt.from(2) >= denominator) {
      rounded += BigInt.one;
    }

    final sign = numerator.isNegative && rounded != BigInt.zero ? '-' : '';
    final digits = rounded.toString().padLeft(scale + 1, '0');
    final whole =
        scale == 0 ? digits : digits.substring(0, digits.length - scale);
    final fraction = scale == 0
        ? ''
        : digits
            .substring(digits.length - scale)
            .replaceFirst(RegExp(r'0+$'), '');
    final decimal = fraction.isEmpty ? whole : '$whole.$fraction';
    final approximation = isTerminating ? '' : '≈ ';
    return '$approximation$sign$decimal';
  }

  @override
  String toString() => denominator == BigInt.one
      ? numerator.toString()
      : '$numerator/$denominator';
}

class ExpressionEvaluator {
  const ExpressionEvaluator();

  EvaluationOutcome evaluate(String expression) {
    try {
      return EvaluationSuccess(_ExpressionParser(expression).parse());
    } on _ExpressionError catch (error) {
      return EvaluationFailure(error.kind, error.message);
    }
  }
}

enum _TokenType {
  number,
  plus,
  minus,
  multiply,
  divide,
  leftParenthesis,
  rightParenthesis,
  end,
}

final class _Token {
  const _Token(this.type, {this.value});

  final _TokenType type;
  final ExactRational? value;
}

final class _ExpressionError implements Exception {
  const _ExpressionError(this.kind, this.message);

  final ExpressionErrorKind kind;
  final String message;
}

final class _ExpressionParser {
  _ExpressionParser(String source) : _tokens = _tokenize(source);

  final List<_Token> _tokens;
  int _position = 0;

  ExactRational parse() {
    if (_current.type == _TokenType.end) {
      throw const _ExpressionError(
        ExpressionErrorKind.incomplete,
        'Incomplete expression',
      );
    }
    final value = _parseExpression();
    if (_current.type != _TokenType.end) {
      _invalid();
    }
    return value;
  }

  ExactRational _parseExpression() {
    var value = _parseTerm();
    while (_current.type == _TokenType.plus ||
        _current.type == _TokenType.minus) {
      final operation = _advance().type;
      final right = _parseTerm();
      value = operation == _TokenType.plus
          ? value.add(right)
          : value.subtract(right);
    }
    return value;
  }

  ExactRational _parseTerm() {
    var value = _parseUnary();
    while (_current.type == _TokenType.multiply ||
        _current.type == _TokenType.divide) {
      final operation = _advance().type;
      final right = _parseUnary();
      if (operation == _TokenType.divide && right.numerator == BigInt.zero) {
        throw const _ExpressionError(
          ExpressionErrorKind.divisionByZero,
          'Cannot divide by zero',
        );
      }
      value = operation == _TokenType.multiply
          ? value.multiply(right)
          : value.divide(right);
    }
    return value;
  }

  ExactRational _parseUnary() {
    if (_match(_TokenType.plus)) {
      return _parseUnary();
    }
    if (_match(_TokenType.minus)) {
      return _parseUnary().negated;
    }
    return _parsePrimary();
  }

  ExactRational _parsePrimary() {
    if (_current.type == _TokenType.number) {
      return _advance().value!;
    }
    if (_match(_TokenType.leftParenthesis)) {
      final value = _parseExpression();
      if (!_match(_TokenType.rightParenthesis)) {
        if (_current.type == _TokenType.end) {
          throw const _ExpressionError(
            ExpressionErrorKind.incomplete,
            'Incomplete expression',
          );
        }
        _invalid();
      }
      return value;
    }
    if (_current.type == _TokenType.end) {
      throw const _ExpressionError(
        ExpressionErrorKind.incomplete,
        'Incomplete expression',
      );
    }
    _invalid();
  }

  bool _match(_TokenType type) {
    if (_current.type != type) {
      return false;
    }
    _advance();
    return true;
  }

  _Token get _current => _tokens[_position];

  _Token _advance() {
    final token = _current;
    if (token.type != _TokenType.end) {
      _position++;
    }
    return token;
  }

  Never _invalid() => throw const _ExpressionError(
        ExpressionErrorKind.invalid,
        'Invalid expression',
      );
}

List<_Token> _tokenize(String source) {
  final tokens = <_Token>[];
  var index = 0;

  while (index < source.length) {
    final character = source[index];
    if (_isWhitespace(character)) {
      index++;
      continue;
    }

    if (_isDigit(character) || character == '.') {
      final start = index;
      while (index < source.length && _isDigit(source[index])) {
        index++;
      }

      var hasDecimalPoint = false;
      if (index < source.length && source[index] == '.') {
        hasDecimalPoint = true;
        index++;
        while (index < source.length && _isDigit(source[index])) {
          index++;
        }
      } else if (start == index) {
        while (index < source.length && _isDigit(source[index])) {
          index++;
        }
      }

      if (start == index || (source[start] == '.' && index == start + 1)) {
        _tokenizeInvalid();
      }

      final numberText = source.substring(start, index);
      if (!hasDecimalPoint) {
        final mixedMatch = RegExp(r'\s+(\d+)/(\d+)')
            .matchAsPrefix(source, index);
        if (mixedMatch != null) {
          final whole = BigInt.parse(numberText);
          final numerator = BigInt.parse(mixedMatch.group(1)!);
          final denominator = BigInt.parse(mixedMatch.group(2)!);
          if (denominator == BigInt.zero) {
            throw const _ExpressionError(
              ExpressionErrorKind.divisionByZero,
              'Cannot divide by zero',
            );
          }
          final mixedNumerator = whole * denominator + numerator;
          tokens.add(
            _Token(
              _TokenType.number,
              value: ExactRational(mixedNumerator, denominator),
            ),
          );
          index = mixedMatch.end;
          continue;
        }
      }

      final digits = numberText.replaceAll('.', '');
      final decimalPlaces = hasDecimalPoint
          ? numberText.length - numberText.indexOf('.') - 1
          : 0;
      tokens.add(
        _Token(
          _TokenType.number,
          value: ExactRational(
            BigInt.parse(digits),
            BigInt.from(10).pow(decimalPlaces),
          ),
        ),
      );
      continue;
    }

    final type = switch (character) {
      '+' => _TokenType.plus,
      '-' || '−' => _TokenType.minus,
      '*' || '×' => _TokenType.multiply,
      '/' || '÷' => _TokenType.divide,
      '(' => _TokenType.leftParenthesis,
      ')' => _TokenType.rightParenthesis,
      _ => null,
    };
    if (type == null) {
      _tokenizeInvalid();
    }
    tokens.add(_Token(type));
    index++;
  }

  tokens.add(const _Token(_TokenType.end));
  return tokens;
}

bool _isDigit(String character) =>
    character.codeUnitAt(0) >= 48 && character.codeUnitAt(0) <= 57;

bool _isWhitespace(String character) => character.trim().isEmpty;

Never _tokenizeInvalid() => throw const _ExpressionError(
      ExpressionErrorKind.invalid,
      'Invalid expression',
    );
