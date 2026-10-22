import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/core/app_theme.dart';
import 'package:personal_finance/src/core/providers.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';
import 'package:personal_finance/src/domain/enums.dart';
import 'package:personal_finance/src/features/emis/emi_overview_screen.dart';

void main() {
  late AppDatabase database;
  late FinanceRepository repository;

  setUp(() {
    database = AppDatabase.test(NativeDatabase.memory());
    repository = FinanceRepository(database);
  });
  tearDown(() => database.close());

  Future<void> pumpScreen(
    WidgetTester tester,
    ThemeMode mode, {
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          financeRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const EmiOverviewScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('empty categories render on a small phone in $mode', (
      tester,
    ) async {
      await pumpScreen(tester, mode);
      expect(find.text('Nothing here yet'), findsOneWidget);
      await tester.tap(find.text('Personal'));
      await tester.pumpAndSettle();
      expect(
        find.text('Personal loans and credit-card installments appear here.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Given to Others'));
      await tester.pumpAndSettle();
      expect(
        find.text('Add an agreement to track repayments from someone else.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  }

  testWidgets('tabs keep Personal and friend agreements separate', (
    tester,
  ) async {
    for (final (name, type) in [
      ('Bank loan', 'Loan'),
      ('Ravi', friendRepaymentType),
    ]) {
      await repository.saveEmi(
        EmisCompanion.insert(
          name: name,
          principalPaise: 200000,
          emiAmountPaise: 100000,
          tenureMonths: 2,
          startDate: DateTime(2026, 11, 1),
          nextDueDate: DateTime(2026, 11, 1),
          frequency: PaymentFrequency.monthly,
          status: EmiStatus.active,
          type: Value(type),
        ),
      );
    }
    await pumpScreen(tester, ThemeMode.light);
    expect(find.text('Bank loan'), findsWidgets);
    expect(find.text('Ravi'), findsWidgets);
    await tester.tap(find.text('Personal'));
    await tester.pumpAndSettle();
    expect(find.text('Bank loan'), findsWidgets);
    expect(find.text('Ravi'), findsNothing);
    await tester.tap(find.text('Given to Others'));
    await tester.pumpAndSettle();
    expect(find.text('Ravi'), findsWidgets);
    expect(find.text('Bank loan'), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Bank loan'), findsWidgets);
    expect(find.text('Ravi'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('populated overview fits a 360dp width at 1.3 text scale', (
    tester,
  ) async {
    await repository.saveEmi(
      EmisCompanion.insert(
        name: 'A long lender agreement name',
        principalPaise: 1000000,
        emiAmountPaise: 500000,
        tenureMonths: 2,
        startDate: DateTime(2026, 11, 1),
        nextDueDate: DateTime(2026, 11, 1),
        frequency: PaymentFrequency.monthly,
        status: EmiStatus.active,
      ),
    );
    await pumpScreen(tester, ThemeMode.dark, textScale: 1.3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('monthly schedule opens the selected month details', (
    tester,
  ) async {
    final due = DateTime(DateTime.now().year, DateTime.now().month + 1, 1);
    await repository.saveEmi(
      EmisCompanion.insert(
        name: 'Month chart loan',
        principalPaise: 1000000,
        emiAmountPaise: 500000,
        tenureMonths: 2,
        startDate: due,
        nextDueDate: due,
        frequency: PaymentFrequency.monthly,
        status: EmiStatus.active,
      ),
    );
    await pumpScreen(tester, ThemeMode.light);
    final monthKey = ValueKey('emi-month-${due.year}-${due.month}');
    await tester.scrollUntilVisible(
      find.byKey(monthKey),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(monthKey));
    await tester.pumpAndSettle();
    expect(find.text('1 unpaid installment'), findsOneWidget);
    expect(find.text('Month chart loan'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('Personal month breakdown excludes expected receipts', (
    tester,
  ) async {
    final due = DateTime(DateTime.now().year, DateTime.now().month + 1, 1);
    await repository.saveEmi(
      EmisCompanion.insert(
        name: 'Personal chart loan',
        principalPaise: 1000000,
        emiAmountPaise: 500000,
        tenureMonths: 2,
        startDate: due,
        nextDueDate: due,
        frequency: PaymentFrequency.monthly,
        status: EmiStatus.active,
      ),
    );
    await pumpScreen(tester, ThemeMode.light);
    await tester.tap(find.text('Personal'));
    await tester.pumpAndSettle();
    final monthKey = ValueKey('emi-month-${due.year}-${due.month}');
    await tester.scrollUntilVisible(
      find.byKey(monthKey),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(monthKey)),
      alignment: 0.5,
    );
    await tester.tap(find.byKey(monthKey));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(
      find.descendant(of: sheet, matching: find.text('To pay')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.textContaining('Receive')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('long-press offers safe edit and delete actions', (tester) async {
    await repository.saveEmi(
      EmisCompanion.insert(
        name: 'Actions loan',
        principalPaise: 100000,
        emiAmountPaise: 100000,
        tenureMonths: 1,
        startDate: DateTime(2026, 11, 1),
        nextDueDate: DateTime(2026, 11, 1),
        frequency: PaymentFrequency.monthly,
        status: EmiStatus.active,
      ),
    );
    await pumpScreen(tester, ThemeMode.light);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -350));
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(Dismissible));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Move to Deleted'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  test('friend reminder uses unpaid amount and due date', () async {
    final id = await repository.saveEmi(
      EmisCompanion.insert(
        name: 'Ravi',
        principalPaise: 200000,
        emiAmountPaise: 100000,
        tenureMonths: 2,
        startDate: DateTime(2026, 11, 1),
        nextDueDate: DateTime(2026, 11, 1),
        frequency: PaymentFrequency.monthly,
        status: EmiStatus.active,
        type: const Value(friendRepaymentType),
      ),
    );
    var detail = await repository.emiDetail(id);
    await repository.recordEmiPayment(
      id,
      expectedDueDate: detail.nextUnpaidInstallment!.dueDate,
      amountPaise: 25000,
    );
    detail = await repository.emiDetail(id);
    final message = friendEmiReminderMessage(detail);
    expect(message, contains('Ravi'));
    expect(message, contains('₹750'));
    expect(message, contains('1 Nov 2026'));
    expect(message, isNot(contains('late fee')));
  });

  testWidgets('completed expansion does not read the scroll offset as a bool', (
    tester,
  ) async {
    for (var index = 0; index < 10; index++) {
      await repository.saveEmi(
        EmisCompanion.insert(
          name: 'Open $index',
          principalPaise: 100000,
          emiAmountPaise: 100000,
          tenureMonths: 1,
          startDate: DateTime(2026, 11, 1),
          nextDueDate: DateTime(2026, 11, 1),
          frequency: PaymentFrequency.monthly,
          status: EmiStatus.active,
        ),
      );
    }
    await repository.saveEmi(
      EmisCompanion.insert(
        name: 'Paid loan',
        principalPaise: 100000,
        emiAmountPaise: 100000,
        tenureMonths: 1,
        startDate: DateTime(2026, 9, 1),
        nextDueDate: DateTime(2026, 9, 1),
        frequency: PaymentFrequency.monthly,
        status: EmiStatus.completed,
        initialPaidInstallments: const Value(1),
      ),
    );
    await pumpScreen(tester, ThemeMode.light);
    await tester.scrollUntilVisible(
      find.text('Completed (1)'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Completed (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Paid loan'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('right swipe confirms one payment and Undo restores it', (
    tester,
  ) async {
    final id = await repository.saveEmi(
      EmisCompanion.insert(
        name: 'Bank swipe',
        principalPaise: 200000,
        emiAmountPaise: 100000,
        tenureMonths: 2,
        startDate: DateTime(2026, 10, 20),
        nextDueDate: DateTime(2026, 10, 20),
        frequency: PaymentFrequency.monthly,
        status: EmiStatus.active,
      ),
    );
    await pumpScreen(tester, ThemeMode.light);
    await tester.scrollUntilVisible(
      find.byType(Dismissible),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.byType(Dismissible)),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Dismissible), const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(find.text('Mark installment paid?'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect((await repository.emiDetail(id)).paidInstallments, 1);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect((await repository.emiDetail(id)).paidInstallments, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
