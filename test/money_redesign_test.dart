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
import 'package:personal_finance/src/shared/notched_navigation_bar.dart';

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

    final nivasRow = find.byKey(const ValueKey('given:nivas'));
    final ashaRow = find.byKey(const ValueKey('given:asha'));
    await tester.scrollUntilVisible(
      nivasRow,
      100,
      scrollable: find.byType(Scrollable).at(1),
    );

    expect(nivasRow, findsOneWidget);
    expect(ashaRow, findsOneWidget);
    expect(find.textContaining('2 records'), findsWidgets);
    expect(
      tester.getTopLeft(ashaRow).dy,
      lessThan(tester.getTopLeft(nivasRow).dy),
    );

    await repo.addRepayment(nivasId, 5000, 'UPI', today);
    await tester.pumpAndSettle();
    expect(find.text('Partly paid'), findsWidgets);
    expect(find.text('₹250'), findsWidgets);

    await tester.tap(nivasRow);
    await tester.pumpAndSettle();
    expect(find.text('₹250'), findsOneWidget);
    expect(find.byType(ListTile), findsAtLeastNWidgets(2));

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

  testWidgets('filters separate overdue, partial, and settled people', (
    tester,
  ) async {
    final today = DateTime.now();
    final partialId = await create(
      'Partial',
      10000,
      today.add(const Duration(days: 5)),
    );
    await repo.addRepayment(partialId, 4000, null, today);
    await create('Late', 8000, today.subtract(const Duration(days: 1)));
    final settledId = await create(
      'Settled',
      5000,
      today.add(const Duration(days: 8)),
    );
    await repo.addRepayment(settledId, 5000, null, today);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [financeRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: MoneyScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Overdue').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('given:late')), findsOneWidget);
    expect(find.byKey(const ValueKey('given:partial')), findsNothing);

    await tester.tap(find.text('Partially paid').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('given:partial')), findsOneWidget);
    expect(find.byKey(const ValueKey('given:late')), findsNothing);

    await tester.tap(find.text('Settled').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('given:settled')), findsOneWidget);
    expect(find.byKey(const ValueKey('given:partial')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets(
    'Money header aligns and footer clears one navigation bar on a small screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final today = DateTime.now();
      for (var index = 0; index < 5; index++) {
        await create(
          'Given $index',
          10000,
          today.add(Duration(days: index + 1)),
        );
        await repo.saveMoneyRecord(
          MoneyRecordsCompanion.insert(
            personName: 'Borrowed $index',
            direction: MoneyDirection.borrowed,
            amountPaise: 10000,
            recordDate: today,
            dueDate: Value(today.add(Duration(days: index + 1))),
            status: MoneyStatus.active,
          ),
        );
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [financeRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            home: Scaffold(
              extendBody: true,
              body: const MoneyScreen(),
              bottomNavigationBar: NotchedNavigationBar(
                selectedIndex: 2,
                onSelected: (_) {},
                onAsk: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(const ValueKey('title'))).dx, 16);
      expect(tester.getBottomRight(find.byTooltip('Money reminders')).dx, 344);
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -1000),
      );
      await tester.pumpAndSettle();
      final footer = tester
          .widgetList<SliverToBoxAdapter>(find.byType(SliverToBoxAdapter))
          .map((sliver) => sliver.child)
          .whereType<SizedBox>()
          .where((box) => box.height == 148)
          .toList();
      expect(footer, isNotEmpty);
      expect(tester.getTopLeft(find.byKey(const ValueKey('total'))).dx, 16);
      await tester.tap(find.text('Money borrowed'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(const ValueKey('title'))).dx, 16);
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(const ValueKey('total'))).dx, 16);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets('borrowed Settled section remains accessible in dark theme', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final id = await repo.saveMoneyRecord(
      MoneyRecordsCompanion.insert(
        personName: 'Ravi',
        direction: MoneyDirection.borrowed,
        amountPaise: 10000,
        recordDate: DateTime.now(),
        status: MoneyStatus.active,
      ),
    );
    await repo.addRepayment(id, 10000, null, DateTime.now());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [financeRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(theme: ThemeData.dark(), home: const MoneyScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Money borrowed'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey('title'))).dx, 16);
    expect(find.text('Settled'), findsWidgets);
    await tester.tap(find.text('Settled').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('borrowed:ravi')), findsOneWidget);
    expect(tester.takeException(), equals(null));
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
