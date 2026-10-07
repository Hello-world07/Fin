double evaluateCalculation(String expression) {
  final tokens = RegExp(r'(\d+(?:\.\d+)?)|[+\-×÷%]')
      .allMatches(expression.replaceAll(' ', ''))
      .map((match) => match.group(0)!)
      .toList();
  if (tokens.isEmpty) throw const FormatException();

  final values = <double>[];
  final ops = <String>[];
  for (final token in tokens) {
    final number = double.tryParse(token);
    if (number != null) {
      values.add(number);
    } else if (token == '%') {
      if (values.isEmpty) throw const FormatException();
      values[values.length - 1] = values.last / 100;
    } else {
      while (ops.isNotEmpty && _precedence(ops.last) >= _precedence(token)) {
        _apply(values, ops.removeLast());
      }
      ops.add(token);
    }
  }
  while (ops.isNotEmpty) {
    _apply(values, ops.removeLast());
  }
  if (values.length != 1) throw const FormatException();
  return values.single;
}

int _precedence(String op) => (op == '×' || op == '÷') ? 2 : 1;

void _apply(List<double> values, String op) {
  if (values.length < 2) throw const FormatException();
  final right = values.removeLast();
  final left = values.removeLast();
  values.add(switch (op) {
    '+' => left + right,
    '-' => left - right,
    '×' => left * right,
    '÷' => right == 0 ? throw const FormatException() : left / right,
    _ => throw const FormatException(),
  });
}
