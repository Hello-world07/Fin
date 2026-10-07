import 'dart:math' as math;

import 'enums.dart';

class EmiInstallment {
  const EmiInstallment({
    required this.number,
    required this.dueDate,
    required this.isPaid,
  });

  final int number;
  final DateTime dueDate;
  final bool isPaid;
}

class EmiSchedule {
  const EmiSchedule({
    required this.principalPaise,
    required this.enteredInstallmentPaise,
    required this.expectedInstallmentPaise,
    required this.tenure,
    required this.interestRate,
    required this.totalRepaymentPaise,
    required this.paidPaise,
    required this.remainingBalancePaise,
    required this.isConsistent,
    this.validationMessage,
  });

  final int principalPaise;
  final int enteredInstallmentPaise;
  final int expectedInstallmentPaise;
  final int tenure;
  final double interestRate;
  final int totalRepaymentPaise;
  final int paidPaise;
  final int remainingBalancePaise;
  final bool isConsistent;
  final String? validationMessage;

  double get progress => totalRepaymentPaise == 0
      ? 0
      : (paidPaise / totalRepaymentPaise).clamp(0.0, 1.0);
}

List<EmiInstallment> buildEmiInstallments({
  required DateTime startDate,
  required int tenure,
  required PaymentFrequency frequency,
  required Set<int> paidInstallmentNumbers,
  int alreadyPaidCount = 0,
}) {
  final installments = <EmiInstallment>[];
  for (var number = 1; number <= tenure; number++) {
    final dueDate = alreadyPaidCount == 0
        ? emiInstallmentDueDate(startDate, number, frequency)
        : number <= alreadyPaidCount
        ? _retreatDueDate(startDate, alreadyPaidCount + 1 - number, frequency)
        : emiInstallmentDueDate(
            startDate,
            number - alreadyPaidCount,
            frequency,
          );
    installments.add(
      EmiInstallment(
        number: number,
        dueDate: dueDate,
        isPaid: paidInstallmentNumbers.contains(number),
      ),
    );
  }
  return installments;
}

DateTime _retreatDueDate(
  DateTime date,
  int periods,
  PaymentFrequency frequency,
) {
  return switch (frequency) {
    PaymentFrequency.weekly => date.subtract(Duration(days: 7 * periods)),
    PaymentFrequency.monthly => _dateInMonth(
      date.year,
      date.month - periods,
      date.day,
    ),
    PaymentFrequency.quarterly => _dateInMonth(
      date.year,
      date.month - 3 * periods,
      date.day,
    ),
    PaymentFrequency.yearly => _dateInMonth(
      date.year - periods,
      date.month,
      date.day,
    ),
    PaymentFrequency.once => date,
  };
}

DateTime emiInstallmentDueDate(
  DateTime startDate,
  int installmentNumber,
  PaymentFrequency frequency,
) {
  final offset = installmentNumber - 1;
  return switch (frequency) {
    PaymentFrequency.weekly => startDate.add(Duration(days: 7 * offset)),
    PaymentFrequency.monthly => _dateInMonth(
      startDate.year,
      startDate.month + offset,
      startDate.day,
    ),
    PaymentFrequency.quarterly => _dateInMonth(
      startDate.year,
      startDate.month + 3 * offset,
      startDate.day,
    ),
    PaymentFrequency.yearly => _dateInMonth(
      startDate.year + offset,
      startDate.month,
      startDate.day,
    ),
    PaymentFrequency.once => startDate,
  };
}

DateTime advanceEmiDueDate(DateTime date, PaymentFrequency frequency) {
  return switch (frequency) {
    PaymentFrequency.weekly => date.add(const Duration(days: 7)),
    PaymentFrequency.monthly => _dateInMonth(
      date.year,
      date.month + 1,
      date.day,
    ),
    PaymentFrequency.quarterly => _dateInMonth(
      date.year,
      date.month + 3,
      date.day,
    ),
    PaymentFrequency.yearly => _dateInMonth(
      date.year + 1,
      date.month,
      date.day,
    ),
    PaymentFrequency.once => date,
  };
}

DateTime _dateInMonth(int year, int monthNumber, int day) {
  final month = DateTime(year, monthNumber, 1);
  final lastDay = DateTime(month.year, month.month + 1, 0).day;
  return DateTime(month.year, month.month, math.min(day, lastDay));
}

EmiSchedule calculateEmiSchedule({
  required int principalPaise,
  required int installmentPaise,
  required int tenure,
  required double? annualInterestRate,
  Iterable<int> paidInstallmentAmounts = const [],
}) {
  final interestRate = annualInterestRate ?? 0;
  final expectedInstallment = expectedEmiInstallmentPaise(
    principalPaise: principalPaise,
    tenure: tenure,
    annualInterestRate: interestRate,
  );
  final total = interestRate == 0 ? principalPaise : installmentPaise * tenure;
  final paid = paidInstallmentAmounts.fold<int>(0, (sum, value) => sum + value);
  final remaining = (total - paid).clamp(0, total);
  final roundingTolerancePaise = math.max(1, (100 / 2).round());
  final finalInstallmentPaise = total - installmentPaise * (tenure - 1);
  final consistent =
      principalPaise > 0 &&
      installmentPaise > 0 &&
      tenure > 0 &&
      interestRate >= 0 &&
      finalInstallmentPaise > 0 &&
      (installmentPaise - expectedInstallment).abs() <= roundingTolerancePaise;

  return EmiSchedule(
    principalPaise: principalPaise,
    enteredInstallmentPaise: installmentPaise,
    expectedInstallmentPaise: expectedInstallment,
    tenure: tenure,
    interestRate: interestRate,
    totalRepaymentPaise: total,
    paidPaise: paid.clamp(0, total),
    remainingBalancePaise: remaining,
    isConsistent: consistent,
    validationMessage: consistent
        ? null
        : emiValidationMessage(
            principalPaise: principalPaise,
            installmentPaise: installmentPaise,
            tenure: tenure,
            annualInterestRate: interestRate,
            expectedInstallmentPaise: expectedInstallment,
          ),
  );
}

int expectedEmiInstallmentPaise({
  required int principalPaise,
  required int tenure,
  required double annualInterestRate,
}) {
  if (principalPaise <= 0 || tenure <= 0) return 0;
  if (annualInterestRate <= 0) return (principalPaise / tenure).round();

  final monthlyRate = annualInterestRate / 12 / 100;
  final factor = math.pow(1 + monthlyRate, tenure).toDouble();
  final emi = principalPaise * monthlyRate * factor / (factor - 1);
  return emi.round();
}

String emiValidationMessage({
  required int principalPaise,
  required int installmentPaise,
  required int tenure,
  required double annualInterestRate,
  required int expectedInstallmentPaise,
}) {
  if (principalPaise <= 0) return 'Principal must be greater than zero.';
  if (installmentPaise <= 0) return 'EMI amount must be greater than zero.';
  if (tenure <= 0) return 'Tenure must be greater than zero.';
  if (annualInterestRate < 0) return 'Interest rate cannot be negative.';

  final interestText = annualInterestRate == 0
      ? '0% interest'
      : '${_trimRate(annualInterestRate)}% interest';
  return "These EMI details don't match.\n"
      'Principal ${_money(principalPaise)} with $interestText and $tenure '
      'installment${tenure == 1 ? '' : 's'} cannot have an EMI of '
      '${_money(installmentPaise)}.\n'
      'Expected EMI: ${_money(expectedInstallmentPaise)}.';
}

String _money(int paise) {
  final rupees = paise / 100;
  final whole = rupees.roundToDouble() == rupees;
  final text = whole ? rupees.toInt().toString() : rupees.toStringAsFixed(2);
  return '₹$text';
}

String _trimRate(double value) {
  if (value.roundToDouble() == value) return value.toInt().toString();
  return value.toStringAsFixed(2);
}
