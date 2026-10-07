const emiPaymentWindow = Duration(days: 5);

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool isWithinEmiPaymentWindow(DateTime dueDate, DateTime now) {
  final dueDay = dateOnly(dueDate);
  final today = dateOnly(now);
  return !today.isBefore(dueDay.subtract(emiPaymentWindow));
}

bool isDueSoon(DateTime dueDate, DateTime now) {
  final dueDay = dateOnly(dueDate);
  final today = dateOnly(now);
  return today.isBefore(dueDay) && isWithinEmiPaymentWindow(dueDay, today);
}
