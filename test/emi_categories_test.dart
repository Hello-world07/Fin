import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';
import 'package:personal_finance/src/domain/enums.dart';

void main() {
  late AppDatabase database;
  late FinanceRepository repository;

  setUp(() {
    database = AppDatabase.test(NativeDatabase.memory());
    repository = FinanceRepository(database);
  });
  tearDown(() => database.close());

  Future<int> create(String name, {bool friend = false}) => repository.saveEmi(
    EmisCompanion.insert(
      name: name,
      principalPaise: 300000,
      emiAmountPaise: 100000,
      tenureMonths: 3,
      startDate: DateTime(2026, 10, 1),
      nextDueDate: DateTime(2026, 10, 1),
      frequency: PaymentFrequency.monthly,
      status: EmiStatus.active,
      type: friend ? const Value(friendRepaymentType) : const Value('Loan'),
    ),
  );

  test('personal and friend schedules and payments stay independent', () async {
    final personalId = await create('Bank loan');
    final friendId = await create('Ravi', friend: true);
    final friendBefore = await repository.emiDetail(friendId);
    final personalBefore = await repository.emiDetail(personalId);

    expect(
      await repository.markEmiPaid(
        personalId,
        expectedDueDate: personalBefore.nextUnpaidInstallment!.dueDate,
      ),
      isTrue,
    );
    final friendAfter = await repository.emiDetail(friendId);
    expect(
      friendAfter.remainingBalancePaise,
      friendBefore.remainingBalancePaise,
    );
    expect(friendAfter.paidInstallments, 0);
    expect(friendAfter.nextUnpaidInstallment!.number, 1);
    expect(friendAfter.category, EmiCategory.givenToFriends);
    expect(
      (await repository.emiDetail(personalId)).remainingBalancePaise,
      200000,
    );
  });

  test('friend EMI subtype stays in Given to Others', () async {
    final id = await repository.saveEmi(
      EmisCompanion.insert(
        name: 'Ravi card',
        principalPaise: 300000,
        emiAmountPaise: 100000,
        tenureMonths: 3,
        startDate: DateTime(2026, 10, 1),
        nextDueDate: DateTime(2026, 10, 1),
        frequency: PaymentFrequency.monthly,
        status: EmiStatus.active,
        type: const Value('$friendRepaymentType:Credit Card'),
      ),
    );
    expect(
      friendRepaymentSubtype((await repository.emiDetail(id)).emi.type),
      'Credit Card',
    );
    expect(
      (await repository.emiDetail(id)).category,
      EmiCategory.givenToFriends,
    );
    expect(
      (await repository.watchEmiDetails(includeFriends: false).first).any(
        (detail) => detail.emi.id == id,
      ),
      isFalse,
    );
  });

  test(
    'friend reminder uses its contact or an existing Money contact',
    () async {
      final id = await create('Ravi', friend: true);
      await database
          .into(database.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: 'money.phone.ravi',
              value: '9876543210',
            ),
          );
      expect(await repository.friendEmiPhone(id, 'Ravi'), '9876543210');
      await repository.saveFriendEmiPhone(id, '+91 9000000000');
      expect(await repository.friendEmiPhone(id, 'Ravi'), '+91 9000000000');
      await repository.saveFriendEmiPhone(id, null);
      expect(await repository.friendEmiPhone(id, 'Ravi'), '9876543210');
    },
  );

  test(
    'two partial receipts keep the installment open until fully paid',
    () async {
      final id = await create('Ravi', friend: true);
      final first = (await repository.emiDetail(id)).nextUnpaidInstallment!;
      expect(
        await repository.recordEmiPayment(
          id,
          expectedDueDate: first.dueDate,
          amountPaise: 25000,
          requestKey: 'first-receipt',
        ),
        isTrue,
      );
      var detail = await repository.emiDetail(id);
      expect(detail.remainingBalancePaise, 275000);
      expect(detail.paidInstallments, 0);
      expect(detail.nextUnpaidInstallment!.number, 1);

      expect(
        await repository.recordEmiPayment(
          id,
          expectedDueDate: first.dueDate,
          amountPaise: 75000,
          requestKey: 'second-receipt',
        ),
        isTrue,
      );
      detail = await repository.emiDetail(id);
      expect(detail.payments, hasLength(2));
      expect(detail.paidInstallments, 1);
      expect(detail.remainingBalancePaise, 200000);
      expect(detail.nextUnpaidInstallment!.number, 2);
    },
  );

  test('retry key and overpayment cannot create duplicate receipts', () async {
    final id = await create('Ravi', friend: true);
    final due = (await repository.emiDetail(id)).nextUnpaidInstallment!.dueDate;
    expect(
      await repository.recordEmiPayment(
        id,
        expectedDueDate: due,
        amountPaise: 40000,
        requestKey: 'retry-1',
      ),
      isTrue,
    );
    expect(
      await repository.recordEmiPayment(
        id,
        expectedDueDate: due,
        amountPaise: 40000,
        requestKey: 'retry-1',
      ),
      isFalse,
    );
    expect(
      await repository.recordEmiPayment(
        id,
        expectedDueDate: due,
        amountPaise: 70000,
        requestKey: 'retry-2',
      ),
      isFalse,
    );
    expect((await repository.emiDetail(id)).payments, hasLength(1));
  });

  test('full early settlement preserves prior partial receipts', () async {
    final personal = await create('Bank loan');
    final friend = await create('Ravi', friend: true);
    final due = (await repository.emiDetail(
      friend,
    )).nextUnpaidInstallment!.dueDate;
    await repository.recordEmiPayment(
      friend,
      expectedDueDate: due,
      amountPaise: 25000,
    );
    expect(
      await repository.settleEmiEarly(friend, expectedRemainingPaise: 275000),
      isTrue,
    );
    final settled = await repository.emiDetail(friend);
    expect(settled.remainingBalancePaise, 0);
    expect(settled.paidInstallments, 3);
    expect(settled.emi.status, EmiStatus.completed);
    expect(settled.payments, hasLength(4));
    expect(
      await repository.settleEmiEarly(friend, expectedRemainingPaise: 275000),
      isFalse,
    );
    expect(
      (await repository.emiDetail(personal)).remainingBalancePaise,
      300000,
    );
  });

  test(
    'notes edit keeps history and deletion archives only that agreement',
    () async {
      final personal = await create('Bank loan');
      final friend = await create('Ravi', friend: true);
      final due = (await repository.emiDetail(
        friend,
      )).nextUnpaidInstallment!.dueDate;
      await repository.recordEmiPayment(
        friend,
        expectedDueDate: due,
        amountPaise: 20000,
      );
      await repository.saveEmi(
        EmisCompanion(
          id: Value(friend),
          notes: const Value('Agreed over phone'),
        ),
      );
      expect((await repository.emiDetail(friend)).payments, hasLength(1));
      await repository.deleteEmi(friend);
      expect(
        (await repository.watchEmiDetails(includeFriends: true).first).map(
          (item) => item.emi.id,
        ),
        contains(personal),
      );
      expect(
        (await repository.watchEmiDetails(includeFriends: true).first).map(
          (item) => item.emi.id,
        ),
        isNot(contains(friend)),
      );
      await repository.restoreEmi(friend);
      expect(
        (await repository.watchEmiDetails(includeFriends: true).first).map(
          (item) => item.emi.id,
        ),
        contains(friend),
      );
    },
  );

  test('old v5 records migrate without losing rows or payment history', () async {
    final directory = await Directory.systemTemp.createTemp(
      'finkeep-emi-migration-',
    );
    final file = File('${directory.path}/legacy.sqlite');
    try {
      final original = AppDatabase.test(NativeDatabase(file));
      await original
          .into(original.emis)
          .insert(
            EmisCompanion.insert(
              name: 'Existing personal loan',
              principalPaise: 200000,
              emiAmountPaise: 100000,
              tenureMonths: 2,
              startDate: DateTime(2026, 11, 1),
              nextDueDate: DateTime(2026, 11, 1),
              frequency: PaymentFrequency.monthly,
              status: EmiStatus.active,
            ),
          );
      await original.customStatement('DROP TABLE emi_payments');
      await original.customStatement(
        'CREATE TABLE emi_payments ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'emi_id INTEGER NOT NULL REFERENCES emis (id) ON DELETE CASCADE, '
        'amount_paise INTEGER NOT NULL, paid_on INTEGER NOT NULL, '
        'installment_number INTEGER NOT NULL, paid_early INTEGER NOT NULL DEFAULT 0, '
        'notes TEXT, UNIQUE (emi_id, installment_number))',
      );
      await original.customStatement(
        'INSERT INTO emi_payments '
        '(emi_id, amount_paise, paid_on, installment_number) '
        'VALUES (1, 100000, 1793491200, 1)',
      );
      for (final column in [
        'interest_method',
        'interest_period',
        'product_price_paise',
        'down_payment_paise',
        'fees_paise',
        'contractual_emi',
      ]) {
        await original.customStatement('ALTER TABLE emis DROP COLUMN $column');
      }
      await original.customStatement('PRAGMA user_version = 5');
      await original.close();

      final migrated = AppDatabase.test(NativeDatabase(file));
      try {
        final loan = await migrated.select(migrated.emis).getSingle();
        final payments = await migrated.select(migrated.emiPayments).get();
        expect(loan.name, 'Existing personal loan');
        expect(loan.type, 'Loan');
        expect(loan.interestMethod, EmiInterestMethod.reducing);
        expect(loan.interestPeriod, EmiRatePeriod.annual);
        expect(loan.feesPaise, 0);
        expect(payments, hasLength(1));
        await migrated
            .into(migrated.emiPayments)
            .insert(
              EmiPaymentsCompanion.insert(
                emiId: loan.id,
                amountPaise: 100,
                paidOn: DateTime(2026, 11, 2),
                installmentNumber: 1,
              ),
            );
        expect(await migrated.select(migrated.emiPayments).get(), hasLength(2));
      } finally {
        await migrated.close();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
