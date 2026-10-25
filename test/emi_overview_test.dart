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
    Size size = const Size(360, 800),
    Key? screenKey,
  }) async {
    await tester.binding.setSurfaceSize(size);
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
          home: EmiOverviewScreen(key: screenKey),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Back steps through EMI sections before leaving All', (
    tester,
  ) async {
    final screenKey = GlobalKey<EmiOverviewScreenState>();
    await pumpScreen(tester, ThemeMode.light, screenKey: screenKey);
    await tester.ensureVisible(find.text('Completed'));
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(screenKey.currentState!.goBackWithinEmis(), isTrue);
    await tester.pumpAndSettle();
    expect(
      find.text('Add an agreement to track repayments from someone else.'),
      findsOneWidget,
    );
    expect(screenKey.currentState!.goBackWithinEmis(), isTrue);
    await tester.pumpAndSettle();
    expect(
      find.text('Personal loans and credit-card installments appear here.'),
      findsOneWidget,
    );
    expect(screenKey.currentState!.goBackWithinEmis(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(screenKey.currentState!.goBackWithinEmis(), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

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
      await tester.tap(find.text('Given to others'));
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

  testWidgets('given EMI timing appears only after recorded payments', (
    tester,
  ) async {
    final id = await repository.saveEmi(
      EmisCompanion.insert(
        name: 'Friend repayment',
        principalPaise: 300000,
        emiAmountPaise: 100000,
        tenureMonths: 3,
        startDate: DateTime(2026, 11, 1),
        nextDueDate: DateTime(2026, 11, 1),
        frequency: PaymentFrequency.monthly,
        status: EmiStatus.active,
        type: const Value(friendRepaymentType),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          financeRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: EmiAgreementDetailScreen(id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final chart = find.byKey(const ValueKey('emi-payment-timing-chart'));
    expect(chart, findsNothing);
    for (final (number, paidOn) in [
      (1, DateTime(2026, 11, 1)),
      (2, DateTime(2026, 12, 3)),
    ]) {
      await database
          .into(database.emiPayments)
          .insert(
            EmiPaymentsCompanion.insert(
              emiId: id,
              amountPaise: 100000,
              paidOn: paidOn,
              installmentNumber: number,
            ),
          );
    }
    await tester.pumpAndSettle();
    expect(chart, findsOneWidget);
    expect(tester.getSize(chart).width, greaterThan(0));
    expect(tester.getSize(chart).height, greaterThan(0));
    expect(find.text('Payment timing'), findsOneWidget);
    expect(
      find.textContaining('1 of 2 installments received on time'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

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
    await tester.ensureVisible(find.text('Given to others'));
    await tester.tap(find.text('Given to others'));
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
    final loadChart = find.byKey(const ValueKey('emi-month-load-chart'));
    expect(loadChart, findsOneWidget);
    expect(tester.getSize(loadChart).width, greaterThan(0));
    expect(tester.getSize(loadChart).height, 108);
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
    await tester.longPress(find.text('Actions loan').last);
    await tester.pumpAndSettle();
    expect(find.text('View history'), findsOneWidget);
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

  testWidgets('completed agreements appear only in the Completed tab', (
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
    expect(find.text('Paid loan'), findsNothing);
    await tester.tap(find.text('Personal'));
    await tester.pumpAndSettle();
    expect(find.text('Paid loan'), findsNothing);
    await tester.ensureVisible(find.text('Completed'));
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(find.text('Paid loan'), findsOneWidget);
    await tester.tap(find.text('Paid loan'));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);
    expect(find.text('Undo payment'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('Completed row shows the recorded final payment', (tester) async {
    final due = DateTime(2026, 10, 20);
    final id = await repository.saveEmi(
      EmisCompanion.insert(
        name: 'Finished loan',
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
      await repository.recordEmiPayment(
        id,
        expectedDueDate: due,
        paidOn: DateTime(2026, 10, 25),
      ),
      isTrue,
    );
    await pumpScreen(tester, ThemeMode.dark, textScale: 1.3);
    await tester.ensureVisible(find.text('Completed'));
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Completed 25 Oct 2026'), findsOneWidget);
    expect(find.textContaining('Last payment ₹1,000'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('Mark paid confirms one payment and Undo restores it', (
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
      find.text('Bank swipe').last,
      200,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('Bank swipe').last),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More actions').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark paid'));
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

  testWidgets('All keeps later EMIs reachable without expanding groups', (
    tester,
  ) async {
    final due = DateTime(DateTime.now().year, DateTime.now().month + 1, 1);
    for (var index = 1; index <= 9; index++) {
      await repository.saveEmi(
        EmisCompanion.insert(
          name: 'Agreement $index',
          principalPaise: 100000,
          emiAmountPaise: 100000,
          tenureMonths: 1,
          startDate: due,
          nextDueDate: due,
          frequency: PaymentFrequency.monthly,
          status: EmiStatus.active,
        ),
      );
    }
    await pumpScreen(tester, ThemeMode.light);
    final list = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Agreement 9'),
      250,
      scrollable: list,
    );
    expect(find.text('Agreement 9'), findsOneWidget);
    expect(find.textContaining('Show all'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('EMI reminders stay scrollable on a short phone', (tester) async {
    await pumpScreen(tester, ThemeMode.light, size: const Size(320, 568));
    await tester.tap(find.byTooltip('EMI reminders'));
    await tester.pumpAndSettle();
    expect(find.text('EMI reminders'), findsOneWidget);
    expect(find.text('Lead time'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('saved EMI notes are visible without opening Edit', (
    tester,
  ) async {
    await repository.saveEmi(
      EmisCompanion.insert(
        name: 'Note agreement',
        principalPaise: 1200000,
        emiAmountPaise: 100000,
        tenureMonths: 12,
        startDate: DateTime(DateTime.now().year, DateTime.now().month + 1, 1),
        nextDueDate: DateTime(DateTime.now().year, DateTime.now().month + 1, 1),
        frequency: PaymentFrequency.monthly,
        status: EmiStatus.active,
        notes: const Value('Reference ABC-123'),
      ),
    );
    await pumpScreen(tester, ThemeMode.light);
    await tester.scrollUntilVisible(
      find.text('Note agreement').last,
      250,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Note agreement').last);
    await tester.pumpAndSettle();
    expect(find.text('Your note'), findsOneWidget);
    expect(find.text('Reference ABC-123'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
