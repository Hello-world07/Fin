import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/core/providers.dart';
import 'package:personal_finance/src/core/app_theme.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';
import 'package:personal_finance/src/domain/enums.dart';
import 'package:personal_finance/src/features/money/money_screen.dart';
import 'package:personal_finance/src/shared/finance_form_widgets.dart';
import 'package:personal_finance/src/shared/forms.dart';

void main() {
  late AppDatabase database;
  late FinanceRepository repository;

  setUp(() {
    database = AppDatabase.test(NativeDatabase.memory());
    repository = FinanceRepository(database);
  });

  tearDown(() => database.close());

  testWidgets('Money edit saves from Details and date tiles match on a phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    final id = await repository.saveMoneyRecord(
      MoneyRecordsCompanion.insert(
        personName: 'Sandeep',
        direction: MoneyDirection.given,
        amountPaise: 120000,
        recordDate: DateTime(2026, 10, 28),
        dueDate: Value(DateTime(2026, 11, 8)),
        status: MoneyStatus.active,
      ),
    );
    final record = await (database.select(
      database.moneyRecords,
    )..where((row) => row.id.equals(id))).getSingle();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          financeRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    openFinanceSheet(context, MoneyFormSheet(record: record)),
                child: const Text('Edit money'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit money'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('02 · Dates & contact'));
    await tester.pumpAndSettle();
    final dateTiles = find.byType(DateTile);
    expect(dateTiles, findsNWidgets(2));
    expect(tester.getSize(dateTiles.at(0)), tester.getSize(dateTiles.at(1)));
    await tester.tap(find.text('01 · Details'));
    await tester.pumpAndSettle();
    final nameField = find.ancestor(
      of: find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Select or enter person',
      ),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(nameField, 'Sandeep Rao');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    final saved = await (database.select(
      database.moneyRecords,
    )..where((row) => row.id.equals(id))).getSingle();
    expect(saved.personName, 'Sandeep Rao');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  test('UPI link keeps the payee and exact rupee amount', () {
    final uri = buildMoneyUpiUri(
      upiId: 'friend@upi',
      payeeName: 'Sandeep Rao',
      amountPaise: 123456,
    );
    expect(uri.scheme, 'upi');
    expect(uri.host, 'pay');
    expect(uri.queryParameters['pa'], 'friend@upi');
    expect(uri.queryParameters['pn'], 'Sandeep Rao');
    expect(uri.queryParameters['am'], '1234.56');
    expect(uri.queryParameters['cu'], 'INR');
    expect(
      () => buildMoneyUpiUri(
        upiId: '1234567890',
        payeeName: 'Sandeep',
        amountPaise: 100,
      ),
      throwsArgumentError,
    );
  });

  testWidgets('opening UPI does not record a borrowed repayment', (
    tester,
  ) async {
    final id = await repository.saveMoneyRecord(
      MoneyRecordsCompanion.insert(
        personName: 'Sandeep',
        direction: MoneyDirection.borrowed,
        amountPaise: 123456,
        recordDate: DateTime.now(),
        status: MoneyStatus.active,
      ),
    );
    String? launchedUri;
    const channel = MethodChannel('finkeep/upi');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          launchedUri = (call.arguments as Map)['uri'] as String;
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          financeRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: const MoneyScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Money borrowed'));
    await tester.pumpAndSettle();
    final pay = find.text('Pay');
    await tester.ensureVisible(pay);
    await tester.tap(pay);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'friend@upi');
    await tester.tap(find.text('Choose UPI app'));
    await tester.pumpAndSettle();
    expect(Uri.parse(launchedUri!).queryParameters['am'], '1234.56');
    expect(
      (await repository.moneyDetail(id)).summary.remainingAmountPaise,
      123456,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('Money keeps settled people in their filter and swipes tabs', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);
    final today = DateTime.now();
    final settledId = await repository.saveMoneyRecord(
      MoneyRecordsCompanion.insert(
        personName: 'Settled person',
        direction: MoneyDirection.given,
        amountPaise: 10000,
        recordDate: today,
        status: MoneyStatus.active,
      ),
    );
    await repository.addRepayment(settledId, 10000, null, today);
    await repository.saveMoneyRecord(
      MoneyRecordsCompanion.insert(
        personName: 'Open person',
        direction: MoneyDirection.given,
        amountPaise: 20000,
        recordDate: today,
        status: MoneyStatus.active,
      ),
    );
    await repository.saveMoneyRecord(
      MoneyRecordsCompanion.insert(
        personName: 'Borrowed person',
        direction: MoneyDirection.borrowed,
        amountPaise: 30000,
        recordDate: today,
        status: MoneyStatus.active,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          financeRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(theme: AppTheme.dark(), home: const MoneyScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('given:settled person')), findsNothing);
    expect(find.text('Money given'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Money borrowed'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

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
            databaseProvider.overrideWithValue(database),
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
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      final upiField = find.ancestor(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.hintText == 'name@bank',
        ),
        matching: find.byType(TextFormField),
      );
      await tester.ensureVisible(upiField);
      await tester.enterText(upiField, 'nivas@upi');
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+7 days'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save record'));
      await tester.pumpAndSettle();

      final saved = await database.select(database.moneyRecords).getSingle();
      final now = DateTime.now();
      expect(saved.personName, 'Nivas');
      expect(saved.direction, MoneyDirection.borrowed);
      expect(saved.amountPaise, 25000);
      expect(saved.dueDate, DateTime(now.year, now.month, now.day + 7));
      expect(saved.paymentMethodId, isNotNull);
      final savedUpi = (await database.select(database.settings).get())
          .singleWhere((row) => row.key == 'money.upi.nivas');
      expect(savedUpi.value, 'nivas@upi');
    },
  );

  testWidgets('Money steps preview without allowing an incomplete save', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          financeRepositoryProvider.overrideWithValue(repository),
          moneyRecordsProvider.overrideWith(
            (ref) => Stream<List<MoneyRecordDetail>>.value(const []),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    openFinanceSheet(context, const MoneyFormSheet()),
                child: const Text('Open form'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();
    final detailsHeight = tester
        .getSize(find.byKey(const ValueKey('money-form-sheet')))
        .height;
    expect(detailsHeight, lessThan(680));
    await tester.tap(find.text('03 · Review'));
    await tester.pumpAndSettle();
    expect(find.text('Check before saving'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('money-form-sheet'))).height,
      lessThan(680),
    );
    await tester.tap(find.text('Save record'));
    await tester.pumpAndSettle();
    expect(find.text('Select or enter person'), findsOneWidget);
    expect(await database.select(database.moneyRecords).get(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('missing-phone reminder goes away without a swipe', (
    tester,
  ) async {
    final id = await repository.saveMoneyRecord(
      MoneyRecordsCompanion.insert(
        personName: 'G1',
        direction: MoneyDirection.given,
        amountPaise: 10000,
        recordDate: DateTime.now(),
        status: MoneyStatus.active,
      ),
    );
    final detail = await repository.moneyDetail(id);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          financeRepositoryProvider.overrideWithValue(repository),
          moneyRecordsProvider.overrideWith((ref) => Stream.value([detail])),
        ],
        child: MaterialApp(home: const MoneyScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remind'));
    await tester.pumpAndSettle();
    expect(find.text('Add a phone number for G1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Add a phone number for G1'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
