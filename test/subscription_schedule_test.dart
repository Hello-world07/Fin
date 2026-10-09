import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';
import 'package:personal_finance/src/domain/enums.dart';
import 'package:personal_finance/src/domain/subscription_schedule.dart';
import 'package:personal_finance/src/domain/due_status.dart';

void main() {
  test('monthly billing remains anchored across short months', () {
    expect(
      nextSubscriptionBillingDate(
        DateTime(2026, 1, 31),
        PaymentFrequency.monthly,
        DateTime(2026, 2, 15),
      ),
      DateTime(2026, 2, 28),
    );
    expect(
      nextSubscriptionBillingDate(
        DateTime(2026, 1, 31),
        PaymentFrequency.monthly,
        DateTime(2026, 3, 1),
      ),
      DateTime(2026, 3, 31),
    );
  });

  test('weekly, quarterly and yearly billing roll forward', () {
    expect(
      nextSubscriptionBillingDate(
        DateTime(2026, 1, 1),
        PaymentFrequency.weekly,
        DateTime(2026, 1, 8),
      ),
      DateTime(2026, 1, 8),
    );
    expect(
      nextSubscriptionBillingDate(
        DateTime(2026, 1, 31),
        PaymentFrequency.quarterly,
        DateTime(2026, 5, 1),
      ),
      DateTime(2026, 7, 31),
    );
    expect(
      nextSubscriptionBillingDate(
        DateTime(2024, 2, 29),
        PaymentFrequency.yearly,
        DateTime(2027, 3, 1),
      ),
      DateTime(2028, 2, 29),
    );
    expect(
      nextSubscriptionBillingDate(
        DateTime(2026, 1, 1),
        PaymentFrequency.once,
        DateTime(2026, 2, 1),
      ),
      DateTime(2026, 1, 1),
    );
  });

  test('30-day occurrences preserve the original month-end anchor', () {
    expect(
      subscriptionOccurrences(
        DateTime(2026, 1, 31),
        PaymentFrequency.monthly,
        DateTime(2026, 2, 1),
        DateTime(2026, 3, 31),
      ),
      [DateTime(2026, 2, 28), DateTime(2026, 3, 31)],
    );
  });

  test('the shared next date produces the same countdown', () {
    final today = DateTime(2026, 10, 8);
    final due = nextSubscriptionBillingDate(
      DateTime(2026, 9, 18),
      PaymentFrequency.monthly,
      today,
    );
    expect(due, DateTime(2026, 10, 18));
    expect(relativeDueText(due, today), 'in 10 days');
  });

  test('an overdue one-time charge is not an upcoming renewal', () {
    expect(
      subscriptionOccurrences(
        DateTime(2026, 10, 1),
        PaymentFrequency.once,
        DateTime(2026, 10, 8),
        DateTime(2026, 11, 8),
      ),
      isEmpty,
    );
    expect(
      relativeDueText(DateTime(2026, 10, 1), DateTime(2026, 10, 8)),
      'Overdue by 7 days',
    );
  });

  test('price changes retain prior entries', () async {
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = FinanceRepository(db);
    final id = await repo.saveSubscription(
      SubscriptionsCompanion.insert(
        name: 'Wifi',
        amountPaise: 49900,
        frequency: PaymentFrequency.monthly,
        nextBillingDate: DateTime(2026, 11, 1),
        status: SubscriptionStatus.active,
      ),
    );
    await repo.saveSubscription(
      SubscriptionsCompanion(id: Value(id), amountPaise: const Value(64900)),
    );
    await repo.saveSubscription(
      SubscriptionsCompanion(id: Value(id), amountPaise: const Value(69900)),
    );
    final history = (await repo.subscriptionExtra(id)).priceHistory;
    expect(history, hasLength(2));
    expect(history.first.fromPaise, 49900);
    expect(history.last.toPaise, 69900);
  });

  test('cancel at cycle end remains active until the due date', () async {
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = FinanceRepository(db);
    final now = DateTime.now();
    final anchor = DateTime(now.year, now.month, now.day + 10);
    final id = await repo.saveSubscription(
      SubscriptionsCompanion.insert(
        name: 'Wifi',
        amountPaise: 50000,
        frequency: PaymentFrequency.monthly,
        nextBillingDate: anchor,
        status: SubscriptionStatus.active,
      ),
    );
    await repo.cancelSubscription(id, atCycleEnd: true, reason: 'Not using');
    expect((await repo.subscription(id))!.status, SubscriptionStatus.active);
    expect((await repo.subscriptionExtra(id)).cancelAt, anchor);
    await repo.refreshSubscriptionTransitions(
      now: anchor.subtract(const Duration(days: 1)),
    );
    expect((await repo.subscription(id))!.status, SubscriptionStatus.active);
    await repo.refreshSubscriptionTransitions(now: anchor);
    expect((await repo.subscription(id))!.status, SubscriptionStatus.cancelled);
  });

  test(
    'pause resumes at the selected date and manual resume clears it',
    () async {
      final db = AppDatabase.test(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = FinanceRepository(db);
      final until = DateTime(2027, 1, 10);
      final id = await repo.saveSubscription(
        SubscriptionsCompanion.insert(
          name: 'Music',
          amountPaise: 10000,
          frequency: PaymentFrequency.monthly,
          nextBillingDate: DateTime(2026, 11, 1),
          status: SubscriptionStatus.active,
        ),
      );
      await repo.pauseSubscription(id, until: until);
      expect((await repo.subscription(id))!.status, SubscriptionStatus.paused);
      await repo.refreshSubscriptionTransitions(
        now: until.subtract(const Duration(days: 1)),
      );
      expect((await repo.subscription(id))!.status, SubscriptionStatus.paused);
      await repo.refreshSubscriptionTransitions(now: until);
      expect((await repo.subscription(id))!.status, SubscriptionStatus.active);
      expect((await repo.subscriptionExtra(id)).pauseUntil, isNull);
      await repo.pauseSubscription(
        id,
        until: until.add(const Duration(days: 30)),
      );
      await repo.resumeSubscription(id);
      expect((await repo.subscriptionExtra(id)).pauseUntil, isNull);
    },
  );

  test(
    'unchanged subscriptions do not log activity; edits are descriptive',
    () async {
      final db = AppDatabase.test(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = FinanceRepository(db);
      final due = DateTime(2026, 11, 1);
      final id = await repo.saveSubscription(
        SubscriptionsCompanion.insert(
          name: 'Wifi',
          amountPaise: 50000,
          frequency: PaymentFrequency.monthly,
          nextBillingDate: due,
          status: SubscriptionStatus.active,
        ),
      );
      final initialCount = (await db.select(db.activityLogs).get()).length;
      await repo.saveSubscription(
        SubscriptionsCompanion(
          id: Value(id),
          name: const Value('Wifi'),
          amountPaise: const Value(50000),
          frequency: const Value(PaymentFrequency.monthly),
          nextBillingDate: Value(due),
          status: const Value(SubscriptionStatus.active),
        ),
      );
      await repo.setSubscriptionStatus(id, SubscriptionStatus.active);
      expect((await db.select(db.activityLogs).get()).length, initialCount);
      await repo.setSubscriptionStatus(id, SubscriptionStatus.paused);
      await repo.saveSubscription(
        SubscriptionsCompanion(id: Value(id), amountPaise: const Value(60000)),
      );
      final titles = (await db.select(db.activityLogs).get())
          .map((entry) => entry.title)
          .toList();
      expect(titles, contains('Wifi paused'));
      expect(titles, contains('Wifi price changed to ₹600'));
      final saved = (await repo.subscription(id))!;
      await repo.deleteSubscription(id);
      expect(await repo.subscription(id), isNull);
      await repo.restoreSubscription(saved);
      expect((await repo.subscription(id))!.amountPaise, 60000);
    },
  );
}
