import 'emi_math.dart';
import 'enums.dart';

/// The next occurrence on or after [today], anchored to the stored date.
DateTime nextSubscriptionBillingDate(
  DateTime billingDate,
  PaymentFrequency frequency,
  DateTime today,
) {
  final start = DateTime(billingDate.year, billingDate.month, billingDate.day);
  final day = DateTime(today.year, today.month, today.day);
  if (frequency == PaymentFrequency.once || !start.isBefore(day)) return start;

  final periods = switch (frequency) {
    PaymentFrequency.weekly => day.difference(start).inDays ~/ 7,
    PaymentFrequency.monthly =>
      (day.year - start.year) * 12 + day.month - start.month,
    PaymentFrequency.quarterly =>
      ((day.year - start.year) * 12 + day.month - start.month) ~/ 3,
    PaymentFrequency.yearly => day.year - start.year,
    PaymentFrequency.once => 0,
  };
  var occurrence = emiInstallmentDueDate(start, periods + 1, frequency);
  if (occurrence.isBefore(day)) {
    occurrence = emiInstallmentDueDate(start, periods + 2, frequency);
  } else {
    final previous = emiInstallmentDueDate(start, periods, frequency);
    if (!previous.isBefore(day)) occurrence = previous;
  }
  return occurrence;
}
