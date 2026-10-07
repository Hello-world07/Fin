import 'enums.dart';

ReminderStatus reminderStatusFor(DateTime due, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final dueDay = DateTime(due.year, due.month, due.day);
  if (dueDay == today) return ReminderStatus.dueToday;
  if (dueDay.isBefore(today)) return ReminderStatus.overdue;
  return ReminderStatus.upcoming;
}

String relativeDueText(DateTime due, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final dueDay = DateTime(due.year, due.month, due.day);
  final days = dueDay.difference(today).inDays;
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  if (days > 1) return 'in $days days';
  final overdue = days.abs();
  return 'Overdue by $overdue ${overdue == 1 ? 'day' : 'days'}';
}
