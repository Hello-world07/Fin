import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';
import 'package:personal_finance/src/domain/enums.dart';
import 'package:personal_finance/src/domain/money_math.dart';

void main() {
  test('recurring frequencies convert to monthly totals in integer paise', () {
    expect(monthlyEquivalentPaise(120000, PaymentFrequency.yearly), 10000);
    expect(monthlyEquivalentPaise(10000, PaymentFrequency.monthly), 10000);
    expect(monthlyEquivalentPaise(3000, PaymentFrequency.weekly), 13000);
    expect(monthlyEquivalentPaise(10000, PaymentFrequency.once), 0);
  });

  test('given 10000 and received 4000 leaves 6000 remaining', () {
    final summary = calculateRepaymentSummary(
      originalAmountPaise: 1000000,
      repaymentAmountsPaise: [400000],
    );

    expect(summary.remainingAmountPaise, 600000);
    expect(summary.status, MoneyStatus.active);
  });

  test('borrowed 10000 and paid 6000 leaves 4000 remaining', () {
    final summary = calculateRepaymentSummary(
      originalAmountPaise: 1000000,
      repaymentAmountsPaise: [600000],
    );

    expect(summary.remainingAmountPaise, 400000);
    expect(summary.status, MoneyStatus.active);
  });

  test('full repayment results in zero remaining and settled', () {
    final summary = calculateRepaymentSummary(
      originalAmountPaise: 1000000,
      repaymentAmountsPaise: [250000, 750000],
    );

    expect(summary.remainingAmountPaise, 0);
    expect(summary.status, MoneyStatus.settled);
  });

  test('repository rejects repayment above remaining amount', () async {
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = FinanceRepository(db);
    final id = await repo.saveMoneyRecord(
      MoneyRecordsCompanion.insert(
        personName: 'Asha',
        direction: MoneyDirection.borrowed,
        amountPaise: 100000,
        recordDate: DateTime(2026, 10, 1),
        status: MoneyStatus.active,
      ),
    );
    await repo.addRepayment(id, 60000, null, DateTime(2026, 10, 2));

    await expectLater(
      repo.addRepayment(id, 40001, null, DateTime(2026, 10, 3)),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('remaining'),
        ),
      ),
    );
    expect((await repo.moneyDetail(id)).summary.remainingAmountPaise, 40000);
  });

  test('dashboard money totals match remaining Money records', () async {
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = FinanceRepository(db);
    for (final (person, direction, amount) in [
      ('Asha', MoneyDirection.given, 250000),
      ('Ravi', MoneyDirection.borrowed, 175000),
    ]) {
      await repo.saveMoneyRecord(
        MoneyRecordsCompanion.insert(
          personName: person,
          direction: direction,
          amountPaise: amount,
          recordDate: DateTime(2026, 10, 1),
          status: MoneyStatus.active,
        ),
      );
    }

    final dashboard = await repo.watchDashboard().first;
    final records = await repo.moneyDetails();
    expect(
      dashboard.comingToMePaise,
      records
          .where((item) => item.record.direction == MoneyDirection.given)
          .fold<int>(0, (sum, item) => sum + item.summary.remainingAmountPaise),
    );
    expect(
      dashboard.needToPayPaise,
      records
          .where((item) => item.record.direction == MoneyDirection.borrowed)
          .fold<int>(0, (sum, item) => sum + item.summary.remainingAmountPaise),
    );
  });

  test(
    'monthly dashboard total includes normalized active subscriptions',
    () async {
      final db = AppDatabase.test(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = FinanceRepository(db);
      final today = DateTime.now();
      for (final (label, amount, frequency) in [
        ('Annual plan', 1200000, PaymentFrequency.yearly),
        ('Weekly plan', 5000, PaymentFrequency.weekly),
        ('One-time plan', 500000, PaymentFrequency.once),
      ]) {
        await repo.saveSubscription(
          SubscriptionsCompanion.insert(
            name: label,
            amountPaise: amount,
            frequency: frequency,
            nextBillingDate: today,
            status: SubscriptionStatus.active,
          ),
        );
      }

      final summary = await repo.watchDashboard().first;
      expect(summary.monthlySubscriptionsPaise, 121667);
      expect(summary.monthlyOutflowPaise, 121667);
    },
  );

  test(
    'dashboard rolls recurring billing forward and excludes undated money',
    () async {
      final db = AppDatabase.test(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = FinanceRepository(db);
      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);
      for (final (person, due, amount) in [
        ('Overdue', todayOnly.subtract(const Duration(days: 2)), 12500),
        ('Soon', todayOnly.add(const Duration(days: 5)), 8000),
        ('No due date', null, 6000),
      ]) {
        await repo.saveMoneyRecord(
          MoneyRecordsCompanion.insert(
            personName: person,
            direction: MoneyDirection.borrowed,
            amountPaise: amount,
            recordDate: todayOnly,
            dueDate: Value(due),
            status: MoneyStatus.active,
          ),
        );
      }
      await repo.saveSubscription(
        SubscriptionsCompanion.insert(
          name: 'Overdue plan',
          amountPaise: 5000,
          frequency: PaymentFrequency.monthly,
          nextBillingDate: todayOnly.subtract(const Duration(days: 1)),
          status: SubscriptionStatus.active,
        ),
      );

      final summary = await repo.watchDashboard().first;
      final actions = await repo.reminders(attentionOnly: false);
      expect(summary.upcomingPayments, 2);
      expect(summary.upcomingSubscriptions, 0);
      expect(summary.monthlyMoneyToPayPaise, 20500);
      expect(summary.monthlyOutflowPaise, 25500);
      expect(actions.where((item) => item.entityType == 'money'), hasLength(2));
      final nextSubscription = actions.singleWhere(
        (item) => item.entityType == 'subscription',
      );
      expect(
        nextSubscription.dueAt.isAfter(todayOnly.add(const Duration(days: 14))),
        isTrue,
      );
      expect(
        actions.any((item) => item.title.contains('No due date')),
        isFalse,
      );
      expect(
        actions.any((item) => item.status == ReminderStatus.overdue),
        isTrue,
      );
    },
  );

  test('dashboard stream refreshes after saving a subscription', () async {
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = FinanceRepository(db);
    final first = await repo.watchDashboard().first;
    final updatedFuture = repo
        .watchDashboard()
        .firstWhere((summary) => summary.monthlySubscriptionsPaise == 1500)
        .timeout(const Duration(seconds: 2));
    await repo.saveSubscription(
      SubscriptionsCompanion.insert(
        name: 'Live update',
        amountPaise: 1500,
        frequency: PaymentFrequency.monthly,
        nextBillingDate: DateTime.now(),
        status: SubscriptionStatus.active,
      ),
    );
    final updated = await updatedFuture;
    expect(first.monthlySubscriptionsPaise, 0);
    expect(updated.monthlySubscriptionsPaise, 1500);
  });

  test('money list stream refreshes when a repayment is inserted', () async {
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = FinanceRepository(db);
    final id = await repo.saveMoneyRecord(
      MoneyRecordsCompanion.insert(
        personName: 'Nivas',
        direction: MoneyDirection.given,
        amountPaise: 100000,
        recordDate: DateTime(2026, 10, 5),
        status: MoneyStatus.active,
      ),
    );
    final seen = <int>[];
    final subscription = repo.watchMoneyRecords().listen((records) {
      if (records.isNotEmpty) {
        seen.add(records.single.summary.remainingAmountPaise);
      }
    });
    await Future<void>.delayed(Duration.zero);
    await repo.addRepayment(id, 40000, null, DateTime(2026, 10, 5));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await subscription.cancel();

    expect(seen, contains(60000));
  });

  test('editing cannot change direction or undercut repayments', () async {
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = FinanceRepository(db);
    final id = await repo.saveMoneyRecord(
      MoneyRecordsCompanion.insert(
        personName: 'Asha',
        direction: MoneyDirection.given,
        amountPaise: 100000,
        recordDate: DateTime(2026, 10, 1),
        status: MoneyStatus.active,
      ),
    );
    await repo.addRepayment(id, 50000, null, DateTime(2026, 10, 2));

    await expectLater(
      repo.saveMoneyRecord(
        MoneyRecordsCompanion(id: Value(id), amountPaise: const Value(40000)),
      ),
      throwsFormatException,
    );
    await expectLater(
      repo.saveMoneyRecord(
        MoneyRecordsCompanion(
          id: Value(id),
          direction: const Value(MoneyDirection.borrowed),
        ),
      ),
      throwsFormatException,
    );
    expect((await repo.moneyDetail(id)).record.direction, MoneyDirection.given);
    expect((await repo.moneyDetail(id)).summary.remainingAmountPaise, 50000);
  });
}
