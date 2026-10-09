import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/core/providers.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';
import 'package:personal_finance/src/domain/enums.dart';
import 'package:personal_finance/src/features/money/money_screen.dart';
import 'package:personal_finance/src/shared/forms.dart';

void main() {
  late AppDatabase db;
  late FinanceRepository repo;

  setUp(() {
    db = AppDatabase.test(NativeDatabase.memory());
    repo = FinanceRepository(db);
  });
  tearDown(() => db.close());

  Future<int> create(String person, int amount, DateTime due) =>
      repo.saveMoneyRecord(
        MoneyRecordsCompanion.insert(
          personName: person,
          direction: MoneyDirection.given,
          amountPaise: amount,
          recordDate: DateTime.now(),
          dueDate: Value(due),
          status: MoneyStatus.active,
        ),
      );

  testWidgets('groups by person, sorts overdue first, and updates balances', (
    tester,
  ) async {
    final today = DateTime.now();
    final nivasId = await create(
      'Nivas',
      10000,
      today.add(const Duration(days: 8)),
    );
    await create('nivas', 20000, today.add(const Duration(days: 20)));
    await create('Asha', 5000, today.subtract(const Duration(days: 2)));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [financeRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: MoneyScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Nivas'),
      100,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Nivas'), findsOneWidget);
    expect(find.text('Asha'), findsOneWidget);
    expect(find.textContaining('2 records'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Asha')).dy,
      lessThan(tester.getTopLeft(find.text('Nivas')).dy),
    );

    await repo.addRepayment(nivasId, 5000, 'UPI', today);
    await tester.pumpAndSettle();
    expect(find.text('2 records · Partially paid'), findsOneWidget);
    expect(find.text('₹250'), findsWidgets);

    await tester.tap(find.text('Nivas'));
    await tester.pumpAndSettle();
    expect(find.text('₹250'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(2));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('detail settles in full and shows running balance', (
    tester,
  ) async {
    final id = await create(
      'Nivas',
      10000,
      DateTime.now().add(const Duration(days: 8)),
    );
    await repo.addRepayment(id, 5000, 'UPI', DateTime.now());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [financeRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(home: MoneyDetailScreen(id)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Nivas owes you ₹50'), findsOneWidget);
    expect(find.text('Record created'), findsOneWidget);
    expect(find.text('Repayment received'), findsOneWidget);
    expect(find.text('Send reminder'), findsOneWidget);

    await tester.tap(find.text('Settle fully').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settle fully').last);
    await tester.pumpAndSettle();
    expect((await repo.moneyDetail(id)).summary.remainingAmountPaise, 0);
    expect(find.text('Add repayment'), findsNothing);
    expect(find.text('Repayment received'), findsNWidgets(2));

    final events = await db.select(db.activityLogs).get();
    expect(events.any((event) => event.title == 'Nivas repaid ₹50'), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  test('extend due date updates the record and activity', () async {
    final id = await create('Nivas', 5000, DateTime(2026, 10, 15));
    await repo.updateMoneyDueDate(id, DateTime(2026, 10, 22));
    expect((await repo.moneyDetail(id)).record.dueDate, DateTime(2026, 10, 22));
    final events = await db.select(db.activityLogs).get();
    expect(
      events.any((event) => event.title == "Extended Nivas's due date"),
      isTrue,
    );
  });

  testWidgets('quick full repayment closes the sheet and updates the record', (
    tester,
  ) async {
    final id = await create(
      'Nivas',
      10000,
      DateTime.now().add(const Duration(days: 7)),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [financeRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => openFinanceSheet(
                  context,
                  RepaymentSheet(recordId: id, remainingPaise: 10000),
                ),
                child: const Text('Open repayment'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open repayment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full ₹100'));
    await tester.tap(find.text('Yesterday'));
    await tester.ensureVisible(find.text('UPI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('UPI'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Add repayment'), findsNothing);
    final detail = await repo.moneyDetail(id);
    expect(detail.summary.remainingAmountPaise, 0);
    expect(detail.repayments.single.notes, 'UPI');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
