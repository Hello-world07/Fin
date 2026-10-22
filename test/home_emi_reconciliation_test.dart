import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';
import 'package:personal_finance/src/domain/emi_affordability.dart';
import 'package:personal_finance/src/domain/enums.dart';
import 'package:personal_finance/src/features/dashboard/home_overview.dart';

void main() {
  test(
    'Home separates lender debt and friend receivables and uses unpaid dues',
    () async {
      final db = AppDatabase.test(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = FinanceRepository(db);
      Future<int> addEmi(String name, {required bool friend}) => repo.saveEmi(
        EmisCompanion.insert(
          name: name,
          principalPaise: 300000,
          emiAmountPaise: 100000,
          tenureMonths: 3,
          startDate: DateTime(2026, 10, 20),
          nextDueDate: DateTime(2026, 10, 20),
          frequency: PaymentFrequency.monthly,
          status: EmiStatus.active,
          type: Value(friend ? friendRepaymentType : 'Loan'),
        ),
      );
      final lenderId = await addEmi('Bank', friend: false);
      final friendId = await addEmi('Ravi', friend: true);
      final lenderDue = (await repo.emiDetail(lenderId)).nextUnpaidInstallment!;
      final friendDue = (await repo.emiDetail(friendId)).nextUnpaidInstallment!;
      await repo.recordEmiPayment(
        lenderId,
        expectedDueDate: lenderDue.dueDate,
        amountPaise: 50000,
      );
      await repo.recordEmiPayment(
        friendId,
        expectedDueDate: friendDue.dueDate,
        amountPaise: 25000,
      );
      await repo.saveMoneyRecord(
        MoneyRecordsCompanion.insert(
          personName: 'Mina',
          direction: MoneyDirection.given,
          amountPaise: 500000,
          recordDate: DateTime(2026, 10, 1),
          dueDate: Value(DateTime(2026, 10, 25)),
          status: MoneyStatus.active,
        ),
      );
      await repo.saveMoneyRecord(
        MoneyRecordsCompanion.insert(
          personName: 'Amit',
          direction: MoneyDirection.borrowed,
          amountPaise: 100000,
          recordDate: DateTime(2026, 10, 1),
          dueDate: Value(DateTime(2026, 10, 27)),
          status: MoneyStatus.active,
        ),
      );
      await db
          .into(db.subscriptions)
          .insert(
            SubscriptionsCompanion.insert(
              name: 'Music',
              amountPaise: 60000,
              frequency: PaymentFrequency.monthly,
              nextBillingDate: DateTime(2026, 10, 28),
              status: SubscriptionStatus.active,
            ),
          );
      final overview = HomeOverview.build(
        [await repo.emiDetail(lenderId), await repo.emiDetail(friendId)],
        await repo.moneyDetails(),
        await db.select(db.subscriptions).get(),
        DateTime(2026, 10, 19),
      );
      expect(overview.emiRemaining, 250000);
      expect(overview.friendRemaining, 275000);
      expect(overview.toCollect, 500000);
      expect(overview.toPay, 100000);
      expect(overview.totalDebt, 350000);
      expect(overview.next30OutgoingTotal, 210000);
      expect(overview.next30Outgoing.every((item) => !item.incoming), isTrue);
      expect(
        overview.dues
            .singleWhere(
              (item) =>
                  item.type == 'emi' && item.date == DateTime(2026, 10, 20),
            )
            .amount,
        50000,
      );
      expect(
        overview.dues
            .singleWhere(
              (item) =>
                  item.type == 'friendEmi' &&
                  item.date == DateTime(2026, 10, 20),
            )
            .amount,
        75000,
      );
      expect(overview.months.first.incoming, 575000);
      expect(overview.months.first.outgoing, 210000);
      expect(
        overview.months.first.items.fold<int>(
          0,
          (sum, item) => sum + item.amount,
        ),
        785000,
      );
      expect(overview.personalDueThisMonth, 100000);
    },
  );

  test('missing and invalid income never yields an affordability label', () {
    expect(personalEmiIncomePercent(100000, null), isNull);
    expect(personalEmiIncomePercent(100000, 0), isNull);
    expect(personalEmiIncomePercent(100000, -1), isNull);
    expect(personalEmiIncomeZone(null), 'Add income');
    expect(personalEmiIncomePercent(100000, 500000), 20);
    expect(personalEmiIncomeZone(20), 'Comfortable');
    expect(personalEmiIncomeZone(45), 'High');
  });

  test(
    'paused EMI balances remain visible without generating due items',
    () async {
      final db = AppDatabase.test(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = FinanceRepository(db);
      for (final (name, type) in [
        ('Paused lender', 'Loan'),
        ('Paused friend', friendRepaymentType),
      ]) {
        await repo.saveEmi(
          EmisCompanion.insert(
            name: name,
            principalPaise: 100000,
            emiAmountPaise: 100000,
            tenureMonths: 1,
            startDate: DateTime(2026, 10, 20),
            nextDueDate: DateTime(2026, 10, 20),
            frequency: PaymentFrequency.monthly,
            status: EmiStatus.paused,
            type: Value(type),
          ),
        );
      }
      final overview = HomeOverview.build(
        await repo.watchEmiDetails(includeFriends: true).first,
        const [],
        const [],
        DateTime(2026, 10, 19),
      );
      expect(overview.emiRemaining, 100000);
      expect(overview.friendRemaining, 100000);
      expect(overview.dues, isEmpty);
      expect(overview.debtFreeDate, isNull);
      expect(overview.months.first.items, isEmpty);
    },
  );
}
