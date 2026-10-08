import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';
import 'package:personal_finance/src/domain/enums.dart';
import 'package:personal_finance/src/domain/subscription_schedule.dart';

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
