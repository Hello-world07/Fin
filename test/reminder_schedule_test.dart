import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/domain/reminder_schedule.dart';

void main() {
  final now = DateTime(2026, 10, 9, 8);
  ReminderTarget target(
    FinanceReminderType type,
    DateTime due, {
    bool trial = false,
  }) => ReminderTarget(
    type: type,
    entityId: 42,
    name: 'Test',
    dueDate: due,
    amountPaise: 50000,
    trial: trial,
  );

  test('three, one, due day and next-morning overdue are planned at 9', () {
    final plan = buildReminderPlan(
      [target(FinanceReminderType.emi, DateTime(2026, 10, 12))],
      const ReminderPlanSettings(enabled: true),
      now,
    );
    expect(plan.map((item) => item.leadDays).toSet(), {3, 1, 0, -1});
    expect(plan.every((item) => item.when.hour == 9), isTrue);
    expect(plan.map((item) => item.when.day).toSet(), {9, 11, 12, 13});
  });

  test('subscriptions use three and one day, trial uses two', () {
    final plan = buildReminderPlan(
      [
        target(FinanceReminderType.subscription, DateTime(2026, 10, 15)),
        target(
          FinanceReminderType.subscription,
          DateTime(2026, 10, 20),
          trial: true,
        ),
      ],
      const ReminderPlanSettings(enabled: true),
      now,
    );
    expect(plan.map((item) => item.leadDays).toSet(), {3, 1, 2});
    expect(plan.where((item) => item.target.trial).single.when.day, 18);
  });

  test('rolling window excludes distant dates', () {
    final plan = buildReminderPlan(
      [target(FinanceReminderType.money, DateTime(2027, 1, 9))],
      const ReminderPlanSettings(enabled: true),
      now,
    );
    expect(plan, isEmpty);
  });

  test('cancelled targets are removed and IDs remain stable', () {
    final item = target(FinanceReminderType.emi, DateTime(2026, 10, 12));
    final settings = const ReminderPlanSettings(enabled: true);
    final first = buildReminderPlan([item], settings, now);
    final rebuilt = buildReminderPlan([item], settings, now);
    expect(first.map((event) => event.id), rebuilt.map((event) => event.id));
    expect(buildReminderPlan([], settings, now), isEmpty);
    expect(
      buildReminderPlan([item], const ReminderPlanSettings(), now),
      isEmpty,
    );
  });
}
