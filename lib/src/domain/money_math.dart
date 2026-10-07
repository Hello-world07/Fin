import 'enums.dart';

class RepaymentSummary {
  const RepaymentSummary({
    required this.originalAmountPaise,
    required this.repaidAmountPaise,
    required this.remainingAmountPaise,
    required this.status,
  });

  final int originalAmountPaise;
  final int repaidAmountPaise;
  final int remainingAmountPaise;
  final MoneyStatus status;
}

RepaymentSummary calculateRepaymentSummary({
  required int originalAmountPaise,
  required Iterable<int> repaymentAmountsPaise,
  MoneyStatus activeStatus = MoneyStatus.active,
}) {
  final repaid = repaymentAmountsPaise.fold<int>(
    0,
    (sum, value) => sum + value,
  );
  final remaining = (originalAmountPaise - repaid).clamp(
    0,
    originalAmountPaise,
  );
  return RepaymentSummary(
    originalAmountPaise: originalAmountPaise,
    repaidAmountPaise: repaid,
    remainingAmountPaise: remaining,
    status: remaining == 0 ? MoneyStatus.settled : activeStatus,
  );
}

int monthlyEquivalentPaise(int amountPaise, PaymentFrequency frequency) =>
    switch (frequency) {
      PaymentFrequency.once => 0,
      PaymentFrequency.weekly => (amountPaise * 52 + 6) ~/ 12,
      PaymentFrequency.monthly => amountPaise,
      PaymentFrequency.quarterly => (amountPaise + 1) ~/ 3,
      PaymentFrequency.yearly => (amountPaise + 6) ~/ 12,
    };
