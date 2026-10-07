import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/domain/due_status.dart';
import 'package:personal_finance/src/domain/enums.dart';

void main() {
  final now = DateTime(2026, 10, 3, 12, 30);

  test('relative due text covers upcoming and overdue states', () {
    expect(relativeDueText(DateTime(2026, 10, 3), now), 'Due today');
    expect(relativeDueText(DateTime(2026, 10, 4), now), 'Due tomorrow');
    expect(relativeDueText(DateTime(2026, 10, 8), now), 'in 5 days');
    expect(relativeDueText(DateTime(2026, 10, 1), now), 'Overdue by 2 days');
  });

  test('reminder status is stable by day', () {
    expect(
      reminderStatusFor(DateTime(2026, 10, 3, 23), now),
      ReminderStatus.dueToday,
    );
    expect(
      reminderStatusFor(DateTime(2026, 10, 4), now),
      ReminderStatus.upcoming,
    );
    expect(
      reminderStatusFor(DateTime(2026, 10, 2), now),
      ReminderStatus.overdue,
    );
  });
}
