import 'package:drift/drift.dart';
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

  test('editing only EMI notes preserves and saves the record', () async {
    final id = await repository.saveEmi(
      EmisCompanion.insert(
        name: 'Slice',
        principalPaise: 1000000,
        emiAmountPaise: 500000,
        tenureMonths: 2,
        startDate: DateTime(2026, 11),
        nextDueDate: DateTime(2026, 11),
        frequency: PaymentFrequency.monthly,
        status: EmiStatus.active,
      ),
    );

    await repository.saveEmi(
      EmisCompanion(id: Value(id), notes: const Value('Updated note')),
    );

    expect((await repository.emiDetail(id)).emi.notes, 'Updated note');
  });

  test('editing only money record notes preserves and saves it', () async {
    final id = await repository.saveMoneyRecord(
      MoneyRecordsCompanion.insert(
        personName: 'Nivas',
        direction: MoneyDirection.given,
        amountPaise: 5000,
        recordDate: DateTime(2026, 10, 8),
        status: MoneyStatus.active,
      ),
    );

    await repository.saveMoneyRecord(
      MoneyRecordsCompanion(id: Value(id), notes: const Value('Updated note')),
    );

    expect((await repository.moneyDetail(id)).record.notes, 'Updated note');
  });

  test('editing only subscription notes preserves and saves it', () async {
    final id = await repository.saveSubscription(
      SubscriptionsCompanion.insert(
        name: 'Wifi',
        amountPaise: 60000,
        frequency: PaymentFrequency.monthly,
        nextBillingDate: DateTime(2026, 11, 1),
        status: SubscriptionStatus.active,
      ),
    );

    await repository.saveSubscription(
      SubscriptionsCompanion(id: Value(id), notes: const Value('Updated note')),
    );

    expect((await repository.subscription(id))?.notes, 'Updated note');
  });
}
