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
  late AppDatabase database;
  late FinanceRepository repository;

  setUp(() {
    database = AppDatabase.test(NativeDatabase.memory());
    repository = FinanceRepository(database);
  });

  tearDown(() => database.close());

  testWidgets('overpayment stays on the repayment form with a clear warning', (
    tester,
  ) async {
    final id = await repository.saveMoneyRecord(
      MoneyRecordsCompanion.insert(
        personName: 'Sandeep',
        direction: MoneyDirection.given,
        amountPaise: 100000,
        recordDate: DateTime(2026, 10, 6),
        status: MoneyStatus.active,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [financeRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: RepaymentSheet(recordId: id, remainingPaise: 100000),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField).first, '1500');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Repayment cannot be greater than the remaining balance of ₹1,000.',
      ),
      findsOneWidget,
    );
    expect(find.text('Add repayment'), findsOneWidget);
    expect((await repository.moneyDetail(id)).repayments, isEmpty);
  });

  testWidgets('repayment save stays reachable above a small keyboard', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    tester.view.viewPadding = const FakeViewPadding(bottom: 24, top: 24);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [financeRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => openFinanceSheet(
                  context,
                  const RepaymentSheet(recordId: 1, remainingPaise: 100000),
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
    await tester.tap(find.byType(TextFormField).last);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    final save = tester.getRect(find.text('Save'));
    expect(save.bottom, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Money form saves its direction, recent-style fields, and due date',
    (tester) async {
      final methods = await database.select(database.paymentMethods).get();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            financeRepositoryProvider.overrideWithValue(repository),
            moneyRecordsProvider.overrideWith(
              (ref) => Stream<List<MoneyRecordDetail>>.value(const []),
            ),
            paymentMethodsProvider.overrideWith((ref) => Stream.value(methods)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      openFinanceSheet(context, const MoneyFormSheet()),
                  child: const Text('Open money form'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open money form'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I borrowed'));
      await tester.enterText(
        find.ancestor(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is TextField && widget.decoration?.hintText == '0.00',
          ),
          matching: find.byType(TextFormField),
        ),
        '250',
      );
      await tester.enterText(
        find.ancestor(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.decoration?.hintText == 'Select or enter person',
          ),
          matching: find.byType(TextFormField),
        ),
        'Nivas',
      );
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+7 days'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Record'));
      await tester.pumpAndSettle();

      final saved = await database.select(database.moneyRecords).getSingle();
      final now = DateTime.now();
      expect(saved.personName, 'Nivas');
      expect(saved.direction, MoneyDirection.borrowed);
      expect(saved.amountPaise, 25000);
      expect(saved.dueDate, DateTime(now.year, now.month, now.day + 7));
      expect(saved.paymentMethodId, isNotNull);
    },
  );
}
