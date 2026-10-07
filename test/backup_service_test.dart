import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/data/backup_service.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';
import 'package:personal_finance/src/domain/enums.dart';

void main() {
  late AppDatabase db;
  late FinanceRepository repo;
  late LocalBackupService backup;

  setUp(() {
    db = AppDatabase.test(NativeDatabase.memory());
    repo = FinanceRepository(db);
    backup = LocalBackupService(db);
  });

  tearDown(() => db.close());

  test('round trips all finance tables and preserves history', () async {
    final emiId = await repo.saveEmi(
      EmisCompanion.insert(
        name: 'Phone',
        principalPaise: 1000000,
        emiAmountPaise: 500000,
        tenureMonths: 2,
        startDate: DateTime(2026, 10, 1),
        nextDueDate: DateTime(2026, 10, 1),
        frequency: PaymentFrequency.monthly,
        status: EmiStatus.active,
      ),
    );
    final emi = await repo.emiDetail(emiId);
    await repo.markEmiPaid(
      emiId,
      expectedDueDate: emi.nextUnpaidInstallment!.dueDate,
      expectedInstallmentNumber: 1,
      paidEarly: true,
    );
    final moneyId = await repo.saveMoneyRecord(
      MoneyRecordsCompanion.insert(
        personName: 'Ravi',
        direction: MoneyDirection.given,
        amountPaise: 300000,
        recordDate: DateTime(2026, 10, 1),
        status: MoneyStatus.active,
      ),
    );
    await repo.addRepayment(
      moneyId,
      100000,
      'Part payment',
      DateTime(2026, 10, 2),
    );
    await repo.saveSubscription(
      SubscriptionsCompanion.insert(
        name: 'Music',
        amountPaise: 99900,
        frequency: PaymentFrequency.monthly,
        nextBillingDate: DateTime(2026, 11, 1),
        status: SubscriptionStatus.active,
      ),
    );
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: 'appearance.themeMode', value: 'dark'),
        );
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: 'privacy.appLock.enabled',
            value: 'true',
          ),
        );

    final json = await backup.createBackupJson();
    await repo.clearAllData();
    await backup.restoreJson(json);

    expect((await repo.emiDetail(emiId)).payments.single.paidEarly, isTrue);
    expect(
      (await repo.moneyDetail(moneyId)).repayments.single.amountPaise,
      100000,
    );
    expect((await db.select(db.subscriptions).get()).single.name, 'Music');
    expect((await repo.watchActivity().first), hasLength(greaterThan(0)));
    final settings = await db.select(db.settings).get();
    expect(
      settings.singleWhere((item) => item.key == 'appearance.themeMode').value,
      'dark',
    );
    expect(
      settings
          .singleWhere((item) => item.key == 'privacy.appLock.enabled')
          .value,
      'true',
    );
  });

  test('rejects invalid backup before replacing stored records', () async {
    await repo.saveSubscription(
      SubscriptionsCompanion.insert(
        name: 'Keep me',
        amountPaise: 50000,
        frequency: PaymentFrequency.monthly,
        nextBillingDate: DateTime(2026, 11, 1),
        status: SubscriptionStatus.active,
      ),
    );

    await expectLater(
      backup.restoreJson('{"format":"wrong"}'),
      throwsFormatException,
    );
    expect((await db.select(db.subscriptions).get()).single.name, 'Keep me');
  });

  test('rejects invalid enum values before replacing data', () async {
    await repo.saveSubscription(
      SubscriptionsCompanion.insert(
        name: 'Keep me',
        amountPaise: 50000,
        frequency: PaymentFrequency.monthly,
        nextBillingDate: DateTime(2026, 11, 1),
        status: SubscriptionStatus.active,
      ),
    );
    final backupData =
        jsonDecode(await backup.createBackupJson()) as Map<String, dynamic>;
    final tables = backupData['tables'] as Map<String, dynamic>;
    final subscriptions = tables['subscriptions'] as List<dynamic>;
    (subscriptions.single as Map<String, dynamic>)['status'] = 'not-a-status';

    await expectLater(
      backup.restoreJson(jsonEncode(backupData)),
      throwsFormatException,
    );
    expect((await db.select(db.subscriptions).get()).single.name, 'Keep me');
  });
}
