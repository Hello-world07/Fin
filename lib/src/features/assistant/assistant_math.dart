import '../../core/formatters.dart';
import '../../domain/emi_math.dart';

double parseAssistantNumber(String text) {
  final match = RegExp(
    r'^([0-9]+(?:\.[0-9]+)?)(k|l|lakh|lakhs|cr|crore|crores)?$',
    caseSensitive: false,
  ).firstMatch(text.replaceAll(RegExp(r'[\s,]'), ''));
  if (match == null) {
    throw const FormatException('Please enter a valid number.');
  }
  final base = double.parse(match.group(1)!);
  final multiplier = switch (match.group(2)?.toLowerCase()) {
    'k' => 1000,
    'l' || 'lakh' || 'lakhs' => 100000,
    'cr' || 'crore' || 'crores' => 10000000,
    _ => 1,
  };
  final value = base * multiplier;
  if (!value.isFinite || value > 1000000000000000) {
    throw const FormatException('That number is too large.');
  }
  return value;
}

class _Token {
  const _Token(this.text);
  final String text;
}

class _Value {
  const _Value(this.number, [this.percent = false]);
  final double number;
  final bool percent;
}

class _MathParser {
  _MathParser(String source) {
    if (source.length > 256) {
      throw const FormatException('That calculation is too long.');
    }
    final input = source.toLowerCase().replaceAll(',', '');
    final pattern = RegExp(
      r'\s*([0-9]+(?:\.[0-9]+)?(?:\s*(?:lakhs|lakh|crores|crore|cr|k|l))?|of|[()+\-*/×÷%])',
      caseSensitive: false,
    );
    var cursor = 0;
    while (cursor < input.length) {
      final match = pattern.matchAsPrefix(input, cursor);
      if (match == null) {
        if (input.substring(cursor).trim().isEmpty) break;
        throw const FormatException('I could not read that calculation.');
      }
      tokens.add(_Token(match.group(1)!));
      if (tokens.length > 128) {
        throw const FormatException('That calculation is too long.');
      }
      cursor = match.end;
    }
  }

  final tokens = <_Token>[];
  int index = 0;

  String? get peek => index < tokens.length ? tokens[index].text : null;

  bool consume(String value) {
    if (peek != value) return false;
    index++;
    return true;
  }

  _Value parse() {
    if (tokens.isEmpty) throw const FormatException('Enter a calculation.');
    final value = expression();
    if (peek != null ||
        !value.number.isFinite ||
        value.number.abs() > 1000000000000000) {
      throw const FormatException('I could not read that calculation.');
    }
    return value;
  }

  _Value expression() {
    var left = term();
    while (peek == '+' || peek == '-') {
      final operator = tokens[index++].text;
      final right = term();
      final amount = right.percent ? left.number * right.number : right.number;
      left = _Value(
        operator == '+' ? left.number + amount : left.number - amount,
      );
    }
    return left;
  }

  _Value term() {
    var left = factor();
    while (peek == '*' ||
        peek == '/' ||
        peek == '×' ||
        peek == '÷' ||
        peek == 'of') {
      final operator = tokens[index++].text;
      final right = factor();
      if (operator == '/' || operator == '÷') {
        if (right.number == 0) {
          throw const FormatException('Division by zero is not possible.');
        }
        left = _Value(left.number / right.number);
      } else {
        left = _Value(left.number * right.number);
      }
    }
    return left;
  }

  _Value factor() {
    if (consume('+')) return factor();
    if (consume('-')) return _Value(-factor().number);
    _Value value;
    if (consume('(')) {
      value = expression();
      if (!consume(')')) {
        throw const FormatException('A closing bracket is missing.');
      }
    } else {
      final token = peek;
      if (token == null) {
        throw const FormatException('The calculation is incomplete.');
      }
      index++;
      value = _Value(parseAssistantNumber(token));
    }
    if (consume('%')) return _Value(value.number / 100, true);
    return value;
  }
}

double evaluateAssistantMath(String expression) =>
    _MathParser(expression).parse().number;

String? assistantMathExpression(String question) {
  final q = question.trim().toLowerCase();
  if (RegExp(r"^(?:calculate|what is|what's)\s+").hasMatch(q)) {
    final expression = q
        .replaceFirst(RegExp(r"^(?:calculate|what is|what's)\s+"), '')
        .replaceAll('?', '')
        .trim();
    if (RegExp(r'^[0-9(]').hasMatch(expression) &&
        RegExp(r'[+*/×÷%\-]|\bof\b').hasMatch(expression)) {
      return expression;
    }
  }
  if (RegExp(r'^[0-9(]').hasMatch(q) &&
      RegExp(r'[+*/×÷%\-]|\bof\b').hasMatch(q) &&
      !RegExp(
        r'\b(add|emi|money|subscription|borrowed|gave|lent)\b',
      ).hasMatch(q)) {
    return q;
  }
  return null;
}

int calculateAssistantEmiPaise(
  double principal,
  double annualRate,
  int months,
) {
  if (principal <= 0 || annualRate < 0 || months <= 0 || months > 1200) {
    throw const FormatException('Please check the amount, rate and tenure.');
  }
  return expectedEmiInstallmentPaise(
    principalPaise: (principal * 100).round(),
    tenure: months,
    annualInterestRate: annualRate,
  );
}

String formatAssistantResult(double value) {
  if (!value.isFinite || value.abs() > 1000000000000000) {
    throw const FormatException('That result is too large.');
  }
  final paise = (value * 100).round();
  final amount = paise % 100 == 0
      ? formatMoney(paise)
      : '₹${_indianNumber(value.abs().toStringAsFixed(2))}'.replaceFirst(
          '₹',
          value < 0 ? '-₹' : '₹',
        );
  final whole = value.abs().floor();
  final words = _numberWords(whole);
  return '$amount (${value < 0 ? 'Minus ' : ''}$words${paise.abs() % 100 == 0 ? '' : ' and ${_numberWords(paise.abs() % 100)} paise'})';
}

String _indianNumber(String value) {
  final parts = value.split('.');
  var integer = parts.first;
  if (integer.length > 3) {
    final tail = integer.substring(integer.length - 3);
    integer =
        '${integer.substring(0, integer.length - 3).replaceAllMapped(RegExp(r'\B(?=(\d{2})+(?!\d))'), (match) => ',')},$tail';
  }
  return '$integer.${parts.last}';
}

String _numberWords(int value) {
  const small = [
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
    'thirteen',
    'fourteen',
    'fifteen',
    'sixteen',
    'seventeen',
    'eighteen',
    'nineteen',
  ];
  const tens = [
    '',
    '',
    'twenty',
    'thirty',
    'forty',
    'fifty',
    'sixty',
    'seventy',
    'eighty',
    'ninety',
  ];
  String words(int n) {
    if (n < 20) return small[n];
    if (n < 100) {
      return '${tens[n ~/ 10]}${n % 10 == 0 ? '' : ' ${words(n % 10)}'}';
    }
    if (n < 1000) {
      return '${words(n ~/ 100)} hundred${n % 100 == 0 ? '' : ' ${words(n % 100)}'}';
    }
    for (final (unit, label) in [
      (10000000, 'crore'),
      (100000, 'lakh'),
      (1000, 'thousand'),
    ]) {
      if (n >= unit) {
        return '${words(n ~/ unit)} $label${n % unit == 0 ? '' : ' ${words(n % unit)}'}';
      }
    }
    return small[n];
  }

  final result = words(value);
  return '${result[0].toUpperCase()}${result.substring(1)}';
}
