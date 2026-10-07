import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/domain/calculator_math.dart';

void main() {
  test('calculator supports basic operators and precedence', () {
    expect(evaluateCalculation('10+5×2'), 20);
    expect(evaluateCalculation('100÷4-5'), 20);
  });

  test('calculator supports decimals and percent', () {
    expect(evaluateCalculation('10.5+2.25'), 12.75);
    expect(evaluateCalculation('500%'), 5);
  });
}
