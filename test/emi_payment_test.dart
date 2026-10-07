import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';
import 'package:personal_finance/src/domain/due_status.dart';
import 'package:personal_finance/src/domain/emi_math.dart';
import 'package:personal_finance/src/domain/emi_payment_rules.dart';
import 'package:personal_finance/src/domain/enums.dart';

void main() {
  late AppDatabase db;
  late FinanceRepository repo;

  setUp(() {
    db = AppDatabase.test(NativeDatabase.memory());
    repo = FinanceRepository(db);
  });

  tearDown(() => db.close());

  Future<int> createEmi({int tenure = 3}) {
    const principalPaise = 300000;
    return repo.saveEmi(
      EmisCompanion.insert(
        name: 'Phone',
        principalPaise: principalPaise,
        emiAmountPaise: principalPaise ~/ tenure,
        tenureMonths: tenure,
        startDate: DateTime(2026, 10, 1),
        nextDueDate: DateTime(2026, 10, 10),
        frequency: PaymentFrequency.monthly,
        status: EmiStatus.active,
      ),
    );
  }

  test('one tap records exactly one EMI payment', () async {
    final id = await createEmi();
    final detailBefore = await repo.emiDetail(id);

    expect(
      await repo.markEmiPaid(id, expectedDueDate: detailBefore.emi.nextDueDate),
      isTrue,
    );
    final detail = await repo.emiDetail(id);

    expect(detail.payments, hasLength(1));
    expect(detail.paidInstallments, 1);
    expect(detail.remainingInstallments, 2);
    expect(
      await repo.markEmiPaid(id, expectedDueDate: detailBefore.emi.nextDueDate),
      isFalse,
    );
    expect((await repo.emiDetail(id)).payments, hasLength(1));
  });

  test('rapid repeated EMI taps create exactly one payment', () async {
    final id = await createEmi();
    final detailBefore = await repo.emiDetail(id);
    final expectedDueDate = detailBefore.emi.nextDueDate;

    final results = await Future.wait([
      for (var i = 0; i < 10; i++)
        repo.markEmiPaid(id, expectedDueDate: expectedDueDate),
    ]);
    final detail = await repo.emiDetail(id);

    expect(results.where((value) => value), hasLength(1));
    expect(detail.payments, hasLength(1));
  });

  test('completed EMI rejects additional payments', () async {
    final id = await createEmi(tenure: 1);
    final detailBefore = await repo.emiDetail(id);

    expect(
      await repo.markEmiPaid(id, expectedDueDate: detailBefore.emi.nextDueDate),
      isTrue,
    );
    expect(
      await repo.markEmiPaid(id, expectedDueDate: detailBefore.emi.nextDueDate),
      isFalse,
    );
    final detail = await repo.emiDetail(id);

    expect(detail.payments, hasLength(1));
    expect(detail.emi.status, EmiStatus.completed);
    expect(detail.remainingInstallments, 0);
  });

  test('next installment can be paid early and is marked in history', () async {
    final id = await createEmi();
    final first = await repo.emiDetail(id);

    expect(
      await repo.markEmiPaid(id, expectedDueDate: first.emi.nextDueDate),
      isTrue,
    );
    final second = await repo.emiDetail(id);

    expect(
      await repo.markEmiPaid(
        id,
        expectedDueDate: second.emi.nextDueDate,
        paidEarly: true,
      ),
      isTrue,
    );
    final detail = await repo.emiDetail(id);

    expect(detail.payments, hasLength(2));
    expect(detail.payments.last.paidEarly, isTrue);
    expect(detail.remainingInstallments, 1);
  });

  test('undo restores first unpaid date and remaining count', () async {
    final id = await createEmi();
    final first = await repo.emiDetail(id);
    expect(
      await repo.markEmiPaid(
        id,
        expectedDueDate: first.nextUnpaidInstallment!.dueDate,
      ),
      isTrue,
    );
    final afterPayment = await repo.emiDetail(id);
    expect(afterPayment.nextUnpaidInstallment!.number, 2);

    expect(
      await repo.revertEmiPayment(id, afterPayment.payments.single.id),
      isTrue,
    );
    final reverted = await repo.emiDetail(id);
    expect(reverted.nextUnpaidInstallment!.number, 1);
    expect(reverted.emi.nextDueDate, first.nextUnpaidInstallment!.dueDate);
    expect(reverted.remainingInstallments, 3);
    expect(reverted.emi.status, EmiStatus.active);
    expect(
      await repo.revertEmiPayment(id, afterPayment.payments.single.id),
      isFalse,
    );
  });

  test('undo final payment reopens a completed EMI', () async {
    final id = await createEmi(tenure: 1);
    final first = await repo.emiDetail(id);
    expect(
      await repo.markEmiPaid(
        id,
        expectedDueDate: first.nextUnpaidInstallment!.dueDate,
      ),
      isTrue,
    );
    final completed = await repo.emiDetail(id);
    expect(completed.emi.status, EmiStatus.completed);
    expect(completed.nextUnpaidInstallment, isNull);

    expect(
      await repo.revertEmiPayment(id, completed.payments.single.id),
      isTrue,
    );
    final reopened = await repo.emiDetail(id);
    expect(reopened.emi.status, EmiStatus.active);
    expect(reopened.nextUnpaidInstallment!.number, 1);
    expect(reopened.remainingInstallments, 1);
  });

  test('undo earlier paid node selects earliest unpaid installment', () async {
    final id = await createEmi();
    for (var index = 0; index < 2; index++) {
      final next = (await repo.emiDetail(id)).nextUnpaidInstallment!;
      expect(await repo.markEmiPaid(id, expectedDueDate: next.dueDate), isTrue);
    }
    final paid = await repo.emiDetail(id);
    expect(await repo.revertEmiPayment(id, paid.payments.first.id), isTrue);
    final reverted = await repo.emiDetail(id);
    expect(reverted.nextUnpaidInstallment!.number, 1);
    expect(reverted.installments[1].isPaid, isTrue);
    expect(reverted.remainingInstallments, 2);
  });

  test('EMI payment window opens five days before due date', () {
    final due = DateTime(2026, 10, 10, 18);

    expect(isWithinEmiPaymentWindow(due, DateTime(2026, 10, 4)), isFalse);
    expect(isWithinEmiPaymentWindow(due, DateTime(2026, 10, 5)), isTrue);
    expect(isWithinEmiPaymentWindow(due, DateTime(2026, 10, 10)), isTrue);
    expect(isWithinEmiPaymentWindow(due, DateTime(2026, 10, 12)), isTrue);
  });

  test(
    'reminders exclude distant dues while Home actions retain them',
    () async {
      final today = dateOnly(DateTime.now());
      final due = today.add(const Duration(days: 27));
      final id = await repo.saveEmi(
        EmisCompanion.insert(
          name: 'Future EMI',
          principalPaise: 100000,
          emiAmountPaise: 100000,
          tenureMonths: 1,
          startDate: due,
          nextDueDate: due,
          frequency: PaymentFrequency.monthly,
          status: EmiStatus.active,
        ),
      );

      expect(
        (await repo.reminders()).where((item) => item.entityId == id),
        isEmpty,
      );
      expect(
        (await repo.reminders(
          attentionOnly: false,
        )).where((item) => item.entityId == id).single.dueAt,
        due,
      );
    },
  );

  test('interest-free EMI schedule rejects contradictory loan values', () {
    final schedule = calculateEmiSchedule(
      principalPaise: 1000000,
      installmentPaise: 5000000,
      tenure: 1,
      annualInterestRate: 0,
    );

    expect(schedule.isConsistent, isFalse);
    expect(schedule.totalRepaymentPaise, 1000000);
    expect(schedule.remainingBalancePaise, 1000000);
    expect(schedule.validationMessage, contains("don't match"));
  });

  test(
    'installment amounts always sum to total payable without overcharging the last',
    () async {
      Future<List<int>> amounts(int totalRupees, int count) async {
        final totalPaise = totalRupees * 100;
        final installmentPaise = ((totalRupees + count - 1) ~/ count) * 100;
        final id = await repo.saveEmi(
          EmisCompanion.insert(
            name: 'Allocation check',
            principalPaise: totalPaise,
            emiAmountPaise: installmentPaise,
            tenureMonths: count,
            startDate: DateTime(2026, 1, 1),
            nextDueDate: DateTime(2026, 1, 1),
            frequency: PaymentFrequency.monthly,
            status: EmiStatus.active,
          ),
        );
        final detail = await repo.emiDetail(id);
        return [
          for (var number = 1; number <= count; number++)
            detail.amountForInstallment(number),
        ];
      }

      expect(await amounts(10000, 2), [500000, 500000]);
      expect(await amounts(10000, 4), [250000, 250000, 250000, 250000]);
      expect(await amounts(10001, 3), [333400, 333400, 333300]);
      expect(await amounts(100000, 4), [2500000, 2500000, 2500000, 2500000]);
      expect(await amounts(10000, 1), [1000000]);
    },
  );

  test('repository blocks inconsistent EMI save', () async {
    await expectLater(
      repo.saveEmi(
        EmisCompanion.insert(
          name: 'Invalid loan',
          principalPaise: 1000000,
          emiAmountPaise: 5000000,
          tenureMonths: 1,
          interestRate: const Value(0),
          startDate: DateTime(2026, 10, 1),
          nextDueDate: DateTime(2026, 11, 1),
          frequency: PaymentFrequency.monthly,
          status: EmiStatus.active,
        ),
      ),
      throwsFormatException,
    );
  });

  test('paid EMI schedule cannot be silently changed but notes can', () async {
    final id = await createEmi();
    final detail = await repo.emiDetail(id);
    expect(
      await repo.markEmiPaid(
        id,
        expectedDueDate: detail.nextUnpaidInstallment!.dueDate,
      ),
      isTrue,
    );
    await expectLater(
      repo.saveEmi(
        EmisCompanion(id: Value(id), startDate: Value(DateTime(2026, 11, 2))),
      ),
      throwsFormatException,
    );
    expect((await repo.emiDetail(id)).emi.startDate, DateTime(2026, 10, 1));
    expect((await repo.emiDetail(id)).payments, hasLength(1));
  });

  test(
    'EMI schedule selects first unpaid installment before any payment',
    () async {
      final id = await repo.saveEmi(
        EmisCompanion.insert(
          name: 'Slice',
          principalPaise: 1000000,
          emiAmountPaise: 500000,
          tenureMonths: 2,
          startDate: DateTime(2026, 11, 1),
          nextDueDate: DateTime(2026, 11, 30),
          frequency: PaymentFrequency.monthly,
          status: EmiStatus.active,
        ),
      );

      final detail = await repo.emiDetail(id);

      expect(detail.nextUnpaidInstallment?.number, 1);
      expect(detail.nextUnpaidInstallment?.dueDate, DateTime(2026, 11, 1));
    },
  );

  test('EMI schedule selects second installment after first is paid', () async {
    final id = await createEmi();
    final first = await repo.emiDetail(id);

    expect(
      await repo.markEmiPaid(id, expectedDueDate: first.emi.nextDueDate),
      isTrue,
    );
    final detail = await repo.emiDetail(id);

    expect(detail.nextUnpaidInstallment?.number, 2);
    expect(detail.nextUnpaidInstallment?.dueDate, DateTime(2026, 11, 1));
  });

  test('EMI schedule has no next unpaid installment when completed', () async {
    final id = await createEmi(tenure: 1);
    final first = await repo.emiDetail(id);

    expect(
      await repo.markEmiPaid(id, expectedDueDate: first.emi.nextDueDate),
      isTrue,
    );
    final detail = await repo.emiDetail(id);

    expect(detail.nextUnpaidInstallment, isA<Null>());
    expect(detail.emi.status, EmiStatus.completed);
  });

  test(
    'EMI stores paid-before-tracking count in the shared schedule',
    () async {
      final id = await repo.saveEmi(
        EmisCompanion.insert(
          name: 'Product plan',
          principalPaise: 300000,
          emiAmountPaise: 100000,
          tenureMonths: 3,
          startDate: DateTime(2026, 11, 1),
          nextDueDate: DateTime(2026, 11, 1),
          frequency: PaymentFrequency.monthly,
          type: const Value('Phone/Product'),
          initialPaidInstallments: const Value(1),
          status: EmiStatus.active,
        ),
      );
      final detail = await repo.emiDetail(id);
      expect(detail.emi.type, 'Phone/Product');
      expect(detail.paidInstallments, 1);
      expect(detail.remainingInstallments, 2);
      expect(detail.progress, closeTo(1 / 3, 0.001));
      expect(detail.nextUnpaidInstallment?.number, 2);
      expect(detail.nextUnpaidInstallment?.dueDate, DateTime(2026, 11, 1));
    },
  );

  test('quarterly EMI schedule advances by calendar quarters', () {
    expect(
      emiInstallmentDueDate(
        DateTime(2026, 1, 31),
        2,
        PaymentFrequency.quarterly,
      ),
      DateTime(2026, 4, 30),
    );
  });

  test('relative due labels cover today tomorrow future and overdue', () {
    final today = DateTime(2026, 10, 5);

    expect(relativeDueText(today, today), 'Due today');
    expect(relativeDueText(DateTime(2026, 10, 6), today), 'Due tomorrow');
    expect(relativeDueText(DateTime(2026, 10, 15), today), 'in 10 days');
    expect(relativeDueText(DateTime(2026, 10, 2), today), 'Overdue by 3 days');
  });

  test(
    'schedule drives payments, stored next due date, and reminders',
    () async {
      final id = await repo.saveEmi(
        EmisCompanion.insert(
          name: 'Slice',
          principalPaise: 1000000,
          emiAmountPaise: 500000,
          tenureMonths: 2,
          startDate: DateTime(2026, 11, 1),
          nextDueDate: DateTime(2026, 11, 30),
          frequency: PaymentFrequency.monthly,
          status: EmiStatus.active,
        ),
      );
      var detail = await repo.emiDetail(id);
      expect(detail.emi.nextDueDate, DateTime(2026, 11, 1));
      expect(detail.nextUnpaidInstallment?.number, 1);
      expect(detail.nextUnpaidInstallment?.dueDate, DateTime(2026, 11, 1));
      expect(detail.amountForInstallment(1), 500000);
      final initialEmiReminders = (await repo.reminders(attentionOnly: false))
          .where((item) => item.entityId == id && item.entityType == 'emi')
          .toList();
      expect(initialEmiReminders, hasLength(2));
      expect(initialEmiReminders.first.installmentNumber, 1);
      expect(initialEmiReminders.first.dueAt, DateTime(2026, 11, 1));
      expect(initialEmiReminders.first.isNextInstallment, isTrue);
      expect(initialEmiReminders.last.installmentNumber, 2);
      expect(initialEmiReminders.last.dueAt, DateTime(2026, 12, 1));
      expect(initialEmiReminders.last.isNextInstallment, isFalse);

      expect(
        await repo.markEmiPaid(
          id,
          expectedDueDate: DateTime(2026, 11, 1),
          expectedInstallmentNumber: 1,
          paidEarly: true,
        ),
        isTrue,
      );
      detail = await repo.emiDetail(id);
      expect(detail.payments.single.paidEarly, isTrue);
      expect(detail.payments.single.amountPaise, 500000);
      expect(detail.nextUnpaidInstallment?.number, 2);
      expect(detail.nextUnpaidInstallment?.dueDate, DateTime(2026, 12, 1));
      expect(detail.emi.nextDueDate, DateTime(2026, 12, 1));
      final nextReminder = (await repo.reminders(
        attentionOnly: false,
      )).singleWhere((item) => item.entityId == id && item.entityType == 'emi');
      expect(nextReminder.installmentNumber, 2);
      expect(nextReminder.dueAt, DateTime(2026, 12, 1));
      expect(nextReminder.isNextInstallment, isTrue);

      expect(
        await repo.markEmiPaid(
          id,
          expectedDueDate: DateTime(2026, 12, 1),
          expectedInstallmentNumber: 2,
          paidEarly: true,
        ),
        isTrue,
      );
      detail = await repo.emiDetail(id);
      expect(detail.payments, hasLength(2));
      expect(detail.emi.status, EmiStatus.completed);
      expect(detail.nextUnpaidInstallment, isA<Null>());
    },
  );

  test('deleting an EMI archives it and preserves payment history', () async {
    final id = await createEmi(tenure: 2);
    final before = await repo.emiDetail(id);
    expect(
      await repo.markEmiPaid(
        id,
        expectedDueDate: before.nextUnpaidInstallment!.dueDate,
        expectedInstallmentNumber: before.nextUnpaidInstallment!.number,
      ),
      isTrue,
    );

    await repo.deleteEmi(id);

    final archived = await (db.select(
      db.emis,
    )..where((emi) => emi.id.equals(id))).getSingle();
    expect(archived.name, 'Phone');
    expect(
      (await (db.select(db.settings)
                ..where((setting) => setting.key.equals('emi.archived.$id')))
              .getSingle())
          .value,
      'true',
    );
    expect((await repo.emiDetail(id)).payments, hasLength(1));
    expect(
      await (db.select(db.emiPayments)..where((p) => p.emiId.equals(id))).get(),
      hasLength(1),
    );
    final activeDetails = await repo.watchEmiDetails().first;
    expect(activeDetails.where((detail) => detail.emi.id == id), isEmpty);
    expect(
      (await repo.reminders()).where((item) => item.entityId == id),
      isEmpty,
    );
  });

  test('monthly installment dates clamp to month end without drifting', () {
    final dates = buildEmiInstallments(
      startDate: DateTime(2027, 1, 31),
      tenure: 3,
      frequency: PaymentFrequency.monthly,
      paidInstallmentNumbers: const {},
    );

    expect(dates.map((item) => item.dueDate), [
      DateTime(2027, 1, 31),
      DateTime(2027, 2, 28),
      DateTime(2027, 3, 31),
    ]);
  });
}
