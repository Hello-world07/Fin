import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/enums.dart';

part 'database.g.dart';

class PaymentMethods extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get label => text().withLength(min: 1, max: 60)();
  TextColumn get kind => text().withDefault(const Constant('Other'))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Emis extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 90)();
  TextColumn get provider => text().nullable()();
  IntColumn get principalPaise => integer()();
  IntColumn get emiAmountPaise => integer()();
  RealColumn get interestRate => real().nullable()();
  TextColumn get interestMethod =>
      textEnum<EmiInterestMethod>().withDefault(const Constant('reducing'))();
  TextColumn get interestPeriod =>
      textEnum<EmiRatePeriod>().withDefault(const Constant('annual'))();
  IntColumn get productPricePaise => integer().nullable()();
  IntColumn get downPaymentPaise => integer().nullable()();
  IntColumn get feesPaise => integer().withDefault(const Constant(0))();
  BoolColumn get contractualEmi =>
      boolean().withDefault(const Constant(false))();
  IntColumn get tenureMonths => integer()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get nextDueDate => dateTime()();
  TextColumn get frequency => textEnum<PaymentFrequency>()();
  TextColumn get type => text().withDefault(const Constant('Loan'))();
  IntColumn get initialPaidInstallments =>
      integer().withDefault(const Constant(0))();
  IntColumn get paymentMethodId =>
      integer().nullable().references(PaymentMethods, #id)();
  TextColumn get status => textEnum<EmiStatus>()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class EmiPayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get emiId =>
      integer().references(Emis, #id, onDelete: KeyAction.cascade)();
  IntColumn get amountPaise => integer()();
  DateTimeColumn get paidOn => dateTime()();
  IntColumn get installmentNumber => integer()();
  BoolColumn get paidEarly => boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().nullable()();
}

class MoneyRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get personName => text().withLength(min: 1, max: 90)();
  TextColumn get direction => textEnum<MoneyDirection>()();
  IntColumn get amountPaise => integer()();
  DateTimeColumn get recordDate => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  IntColumn get paymentMethodId =>
      integer().nullable().references(PaymentMethods, #id)();
  TextColumn get status => textEnum<MoneyStatus>()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class MoneyRepayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get moneyRecordId =>
      integer().references(MoneyRecords, #id, onDelete: KeyAction.cascade)();
  IntColumn get amountPaise => integer()();
  DateTimeColumn get paidOn => dateTime()();
  TextColumn get notes => text().nullable()();
}

class Subscriptions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 90)();
  IntColumn get amountPaise => integer()();
  TextColumn get frequency => textEnum<PaymentFrequency>()();
  DateTimeColumn get nextBillingDate => dateTime()();
  IntColumn get paymentMethodId =>
      integer().nullable().references(PaymentMethods, #id)();
  TextColumn get category => text().nullable()();
  TextColumn get status => textEnum<SubscriptionStatus>()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class ActivityLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => textEnum<ActivityType>()();
  TextColumn get title => text().withLength(min: 1, max: 90)();
  TextColumn get description => text().nullable()();
  TextColumn get entityType => text().nullable()();
  IntColumn get entityId => integer().nullable()();
  DateTimeColumn get occurredAt => dateTime().withDefault(currentDateAndTime)();
}

class CreditCards extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 90)();
  TextColumn get issuer => text().withLength(min: 1, max: 90)();
  TextColumn get lastFour => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class CardStatements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get cardId =>
      integer().references(CreditCards, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get statementDate => dateTime()();
  DateTimeColumn get dueDate => dateTime()();
  IntColumn get balancePaise => integer()();
  IntColumn get minimumDuePaise => integer()();
}

class CardLedgerEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get cardId =>
      integer().references(CreditCards, #id, onDelete: KeyAction.cascade)();
  IntColumn get statementId => integer().nullable().references(
    CardStatements,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get kind =>
      text()(); // purchase, refund, payment, interest, fuelFee, walletFee, annualFee
  TextColumn get description => text().withLength(min: 1, max: 120)();
  IntColumn get amountPaise => integer()();
  DateTimeColumn get occurredOn => dateTime()();
}

class CardEmiConversions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get cardId =>
      integer().references(CreditCards, #id, onDelete: KeyAction.cascade)();
  IntColumn get purchaseEntryId => integer().references(
    CardLedgerEntries,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get principalPaise => integer()();
  IntColumn get monthlyEmiPaise => integer()();
  IntColumn get tenureMonths => integer()();
  DateTimeColumn get firstDueDate => dateTime()();
}

class CardConversionPayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get conversionId => integer().references(
    CardEmiConversions,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get installmentNumber => integer()();
  IntColumn get amountPaise => integer()();
  DateTimeColumn get paidOn => dateTime()();
}

@DriftDatabase(
  tables: [
    PaymentMethods,
    Emis,
    EmiPayments,
    MoneyRecords,
    MoneyRepayments,
    Subscriptions,
    Settings,
    ActivityLogs,
    CreditCards,
    CardStatements,
    CardLedgerEntries,
    CardEmiConversions,
    CardConversionPayments,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.test(super.executor);

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createReadIndexes();
      await _createCardIndexes();
      await batch((batch) {
        batch.insertAll(paymentMethods, [
          PaymentMethodsCompanion.insert(
            label: 'Bank Account',
            kind: const Value('Bank Account'),
          ),
          PaymentMethodsCompanion.insert(
            label: 'UPI',
            kind: const Value('UPI'),
          ),
          PaymentMethodsCompanion.insert(
            label: 'Cash',
            kind: const Value('Cash'),
          ),
          PaymentMethodsCompanion.insert(
            label: 'Credit Card',
            kind: const Value('Credit Card'),
          ),
          PaymentMethodsCompanion.insert(
            label: 'Debit Card',
            kind: const Value('Debit Card'),
          ),
          PaymentMethodsCompanion.insert(
            label: 'Other',
            kind: const Value('Other'),
          ),
        ]);
      });
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(activityLogs);
        await customStatement(
          'DELETE FROM emi_payments WHERE id NOT IN '
          '(SELECT MIN(id) FROM emi_payments GROUP BY emi_id, installment_number)',
        );
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS emi_payments_once_per_installment '
          'ON emi_payments (emi_id, installment_number)',
        );
      }
      if (from < 3) {
        await m.addColumn(emiPayments, emiPayments.paidEarly);
      }
      if (from < 4) {
        await m.addColumn(emis, emis.type);
        await m.addColumn(emis, emis.initialPaidInstallments);
      }
      if (from < 5) await _createReadIndexes();
      if (from < 6) {
        await customStatement(
          'DROP INDEX IF EXISTS emi_payments_once_per_installment',
        );
        await m.alterTable(TableMigration(emiPayments));
        await _createReadIndexes();
      }
      if (from < 7) {
        await m.addColumn(emis, emis.interestMethod);
        await m.addColumn(emis, emis.interestPeriod);
        await m.addColumn(emis, emis.productPricePaise);
        await m.addColumn(emis, emis.downPaymentPaise);
        await m.addColumn(emis, emis.feesPaise);
        await m.addColumn(emis, emis.contractualEmi);
      }
      if (from < 8) {
        await m.createTable(creditCards);
        await m.createTable(cardStatements);
        await m.createTable(cardLedgerEntries);
        await m.createTable(cardEmiConversions);
        await m.createTable(cardConversionPayments);
        await _createCardIndexes();
      }
    },
  );

  Future<void> _createReadIndexes() async {
    for (final statement in [
      'CREATE INDEX IF NOT EXISTS emis_status_due_idx ON emis (status, next_due_date)',
      'CREATE INDEX IF NOT EXISTS money_status_due_idx ON money_records (status, due_date)',
      'CREATE INDEX IF NOT EXISTS subscriptions_status_due_idx ON subscriptions (status, next_billing_date)',
      'CREATE INDEX IF NOT EXISTS emi_payments_emi_idx ON emi_payments (emi_id)',
      'CREATE INDEX IF NOT EXISTS money_repayments_record_idx ON money_repayments (money_record_id)',
    ]) {
      await customStatement(statement);
    }
  }

  Future<void> _createCardIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS card_statements_card_due_idx ON card_statements (card_id, due_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS card_ledger_card_date_idx ON card_ledger_entries (card_id, occurred_on)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS card_conversion_payment_once_idx ON card_conversion_payments (conversion_id, installment_number)',
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'finkeep.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
