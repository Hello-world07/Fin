import 'dart:math' as math;

double calculateMonthlyEmi(double principal, double annualRate, int months) {
  if (!principal.isFinite ||
      principal <= 0 ||
      !annualRate.isFinite ||
      annualRate < 0 ||
      months <= 0 ||
      months > 1200) {
    throw const FormatException('Check principal, rate and tenure.');
  }
  if (annualRate == 0) return principal / months;
  final r = annualRate / 12 / 100;
  final factor = math.pow(1 + r, months).toDouble();
  final result = principal * r * factor / (factor - 1);
  if (!result.isFinite) throw const FormatException('Result is too large.');
  return result;
}

double calculateToolResult(
  CalculatorTool tool,
  double amount,
  double value, {
  bool alternate = false,
  double annualRate = 0,
  double years = 0,
}) {
  if (!amount.isFinite ||
      !value.isFinite ||
      amount < 0 ||
      amount > 1e15 ||
      value < 0 ||
      value > 1e9) {
    throw const FormatException('Check the inputs.');
  }
  final result = switch (tool) {
    CalculatorTool.gst =>
      alternate ? amount / (1 + value / 100) : amount * (1 + value / 100),
    CalculatorTool.discount => amount * (1 - value / 100),
    CalculatorTool.split =>
      value == 0
          ? throw const FormatException('Enter a number of people.')
          : amount / value,
    CalculatorTool.interest =>
      alternate
          ? amount * math.pow(1 + annualRate / 100, years).toDouble()
          : amount * (1 + annualRate * years / 100),
    CalculatorTool.change =>
      amount == 0
          ? throw const FormatException('Starting value cannot be zero.')
          : (value - amount) / amount * 100,
  };
  if (!result.isFinite || result.abs() > 1e15) {
    throw const FormatException('Result is too large.');
  }
  return result;
}

enum CalculatorTool { gst, discount, split, interest, change }
