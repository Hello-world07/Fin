import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/data/backup_service.dart';
import 'package:personal_finance/src/data/credit_card_repository.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';

void main() {
  test(
    'cards have independent statements, payments, and minimum due',
    () async {
      final db = AppDatabase.test(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = CreditCardRepository(db);
      final first = await repo.addCard('Everyday', 'HDFC', lastFour: '1234');
      final second = await repo.addCard('Travel', 'Axis');
      final date = DateTime(2026, 10, 1);
      final due = DateTime(2026, 10, 20);
      final statement = await repo.addStatement(
        first,
        date,
        due,
        1000000,
        100000,
      );
      await repo.addStatement(second, date, due, 500000, 50000);
      await repo.addEntry(
        first,
        'payment',
        'Card payment',
        40000,
        due,
        statementId: statement,
      );
      final firstStatement = (await repo.watchStatements(first).first).single;
      final firstEntries = await repo.watchEntries(first).first;
      expect(CreditCardRepository.paidFor(firstStatement, firstEntries), 40000);
      expect(
        CreditCardRepository.outstandingFor(firstStatement, firstEntries),
        960000,
      );
      expect((await repo.watchEntries(second).first), isEmpty);
      await expectLater(
        repo.addEntry(
          first,
          'payment',
          'Too much',
          970000,
          due,
          statementId: statement,
        ),
        throwsArgumentError,
      );
    },
  );

  test('fees, finance charges and purchase conversion stay separate', () async {
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = CreditCardRepository(db);
    final card = await repo.addCard('Everyday', 'HDFC');
    final date = DateTime(2026, 10, 1);
    final purchase = await repo.addEntry(
      card,
      'purchase',
      'Phone',
      1200000,
      date,
    );
    await repo.addEntry(card, 'fuelFee', 'Fuel surcharge', 2000, date);
    await repo.addEntry(card, 'walletFee', 'Wallet load fee', 3000, date);
    await repo.addEntry(card, 'annualFee', 'Annual fee', 100000, date);
    await repo.addEntry(card, 'interest', 'Finance charge', 15000, date);
    final conversion = await repo.convertPurchase(
      card,
      purchase,
      110000,
      12,
      DateTime(2026, 11, 1),
    );
    expect(conversion, greaterThan(0));
    await repo.recordConversionPayment(
      conversion,
      1,
      110000,
      DateTime(2026, 11, 1),
    );
    expect(
      (await repo.watchConversionPayments(card).first).single.installmentNumber,
      1,
    );
    await expectLater(
      repo.recordConversionPayment(
        conversion,
        1,
        110000,
        DateTime(2026, 11, 2),
      ),
      throwsStateError,
    );
    expect((await repo.watchEntries(card).first).length, 5);
    expect(
      (await repo.watchConversions(card).first).single.principalPaise,
      1200000,
    );
    expect((await db.select(db.emis).get()), isEmpty);
    await expectLater(
      repo.convertPurchase(card, purchase, 110000, 12, DateTime(2026, 11, 1)),
      throwsStateError,
    );
  });

  test('backup restores card ledger and clear all removes it', () async {
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    final cards = CreditCardRepository(db);
    final card = await cards.addCard('Everyday', 'HDFC');
    final statement = await cards.addStatement(
      card,
      DateTime(2026, 10),
      DateTime(2026, 10, 20),
      100000,
      10000,
    );
    await cards.addEntry(
      card,
      'payment',
      'Paid',
      10000,
      DateTime(2026, 10, 15),
      statementId: statement,
    );
    final backup = LocalBackupService(db);
    final json = await backup.createBackupJson();
    await FinanceRepository(db).clearAllData();
    expect(await cards.watchCards().first, isEmpty);
    await backup.restoreJson(json);
    expect(await cards.watchCards().first, hasLength(1));
    expect(await cards.watchEntries(card).first, hasLength(1));
  });
}
