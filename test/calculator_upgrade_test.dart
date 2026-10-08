import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/domain/calculator_tools_math.dart';
import 'package:personal_finance/src/features/assistant/assistant_math.dart';

void main() {
  test(
    'shared safe parser handles precedence, percent and Indian suffixes',
    () {
      expect(evaluateAssistantMath('2+2'), 4);
      expect(evaluateAssistantMath('(500+250)/3'), 250);
      expect(evaluateAssistantMath('8000 + 18%'), 9440);
      expect(evaluateAssistantMath('8000 - 10%'), 7200);
      expect(evaluateAssistantMath('15% of 8000'), 1200);
      expect(evaluateAssistantMath('1.2k + 3k'), 4200);
      expect(evaluateAssistantMath('5L+2Cr'), 20500000);
      expect(() => evaluateAssistantMath('5/0'), throwsFormatException);
      expect(() => evaluateAssistantMath('2+bad'), throwsFormatException);
      expect(() => evaluateAssistantMath('9' * 300), throwsFormatException);
    },
  );

  test('EMI formula uses monthly rate and handles zero interest', () {
    expect(calculateMonthlyEmi(120000, 0, 12), 10000);
    final r = 9 / 12 / 100;
    final factor = math.pow(1 + r, 60).toDouble();
    final expected = 500000 * r * factor / (factor - 1);
    expect(calculateMonthlyEmi(500000, 9, 60), closeTo(expected, .001));
    expect(() => calculateMonthlyEmi(0, 9, 60), throwsFormatException);
    expect(() => calculateMonthlyEmi(500000, 9, 0), throwsFormatException);
  });

  test('finance tools calculate instant results', () {
    expect(calculateToolResult(CalculatorTool.gst, 100, 18), 118);
    expect(
      calculateToolResult(CalculatorTool.gst, 118, 18, alternate: true),
      closeTo(100, .001),
    );
    expect(calculateToolResult(CalculatorTool.discount, 100, 10), 90);
    expect(calculateToolResult(CalculatorTool.split, 100, 4), 25);
    expect(
      calculateToolResult(
        CalculatorTool.interest,
        1000,
        10,
        annualRate: 10,
        years: 2,
      ),
      1200,
    );
    expect(
      calculateToolResult(
        CalculatorTool.interest,
        1000,
        10,
        alternate: true,
        annualRate: 10,
        years: 2,
      ),
      closeTo(1210, .001),
    );
    expect(calculateToolResult(CalculatorTool.change, 100, 120), 20);
    expect(
      () => calculateToolResult(CalculatorTool.split, 100, 0),
      throwsFormatException,
    );
  });
}
