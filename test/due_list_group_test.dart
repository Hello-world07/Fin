import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/domain/due_status.dart';

void main() {
  test('list dates are grouped by the local calendar day', () {
    final now = DateTime(2026, 10, 8, 15);
    expect(dueListGroup(DateTime(2026, 10, 7), now), DueListGroup.overdue);
    expect(dueListGroup(DateTime(2026, 10, 8), now), DueListGroup.thisWeek);
    expect(dueListGroup(DateTime(2026, 10, 11), now), DueListGroup.thisWeek);
    expect(
      dueListGroup(DateTime(2026, 10, 12), now),
      DueListGroup.laterThisMonth,
    );
    expect(
      dueListGroup(DateTime(2026, 11, 1), now),
      DueListGroup.nextMonthAndBeyond,
    );
    expect(dueListGroup(null, now), DueListGroup.noDueDate);
  });
}
