import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/core/app_theme.dart';
import 'package:personal_finance/src/core/formatters.dart';
import 'package:personal_finance/src/core/providers.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/domain/enums.dart';
import 'package:personal_finance/src/features/subscriptions/subscriptions_screen.dart';
import 'package:personal_finance/src/shared/calculator_sheet.dart';
import 'package:personal_finance/src/shared/forms.dart';
import 'package:personal_finance/src/shared/finance_form_widgets.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.test(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> openForm(
    WidgetTester tester, {
    ThemeData? theme,
    String? initialAmount,
    bool fromCalculator = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: theme ?? AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  if (fromCalculator) {
                    openCalculator(
                      context,
                      initial: '250+249',
                      onDestination: (destination, amount) {
                        if (destination == CalculatorDestination.subscription) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            openFinanceSheet(
                              context,
                              SubscriptionFormSheet(initialAmount: amount),
                            );
                          });
                        }
                      },
                    );
                  } else {
                    openFinanceSheet(
                      context,
                      SubscriptionFormSheet(initialAmount: initialAmount),
                    );
                  }
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Finder input(String hint) => find.ancestor(
    of: find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.hintText == hint,
    ),
    matching: find.byType(TextFormField),
  );

  Future<void> reveal(WidgetTester tester, Finder field) async {
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
  }

  testWidgets('required values block saving and errors stay beside fields', (
    tester,
  ) async {
    await openForm(tester);
    await tester.tap(find.text('Save Subscription'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a subscription name'), findsOneWidget);
    expect(find.text('Enter an amount'), findsOneWidget);
    expect(await db.select(db.subscriptions).get(), isEmpty);
    await tester.enterText(input('Subscription name'), '   ');
    for (final invalid in [
      '0',
      '-1',
      'abc',
      'NaN',
      'Infinity',
      '0.001',
      '1e308',
    ]) {
      await tester.enterText(input('0.00'), invalid);
      await tester.tap(find.text('Save Subscription'));
      await tester.pumpAndSettle();
      expect(find.text('Enter an amount greater than zero'), findsOneWidget);
      expect(await db.select(db.subscriptions).get(), isEmpty);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'selections, date navigation and multiline notes persist correctly',
    (tester) async {
      await openForm(tester, initialAmount: '499');
      await tester.enterText(input('Subscription name'), 'Stream');
      final frequency = find.byType(SegmentedButton<PaymentFrequency>);
      await reveal(tester, frequency);
      await tester.tap(find.text('Yearly').last);
      await tester.pumpAndSettle();
      final status = find.byType(SegmentedButton<SubscriptionStatus>);
      await reveal(tester, status);
      await tester.tap(find.text('Paused').last);
      await tester.pumpAndSettle();
      final date = find.byType(DateTile);
      await reveal(tester, date);
      await tester.tap(
        find.descendant(of: date, matching: find.byType(InkWell)).first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final now = DateTime.now();
      final selectedDate = DateTime(now.year, now.month + 1, 15);
      expect(find.text(formatDate(selectedDate)), findsOneWidget);
      await tester.drag(find.byType(ListView).last, const Offset(0, -700));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Music'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.enterText(
        input('Optional notes'),
        'First line\nSecond line\nThird line',
      );
      await tester.tap(find.text('Save Subscription'));
      await tester.pumpAndSettle();
      final item = await db.select(db.subscriptions).getSingle();
      expect(item.name, 'Stream');
      expect(item.amountPaise, 49900);
      expect(item.frequency, PaymentFrequency.yearly);
      expect(item.status, SubscriptionStatus.paused);
      expect(item.nextBillingDate, selectedDate);
      expect(item.category, 'Streaming');
      expect(item.notes, 'First line\nSecond line\nThird line');
      expect(find.byType(SubscriptionFormSheet), findsNothing);
    },
  );

  testWidgets(
    'calculator destination transfers amount and inline calculator remains usable',
    (tester) async {
      await openForm(tester, fromCalculator: true);
      await tester.ensureVisible(find.text('Use this amount'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this amount'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(ActionChip, 'Subscription'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, 'Subscription'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(input('0.00')).controller!.text,
        '499',
      );
      await tester.tap(find.byTooltip('Calculator'));
      await tester.pumpAndSettle();
      expect(find.byType(CalculatorSheet), findsOneWidget);
      await tester.tap(find.text('AC'));
      await tester.tap(find.text('5'));
      await tester.tap(find.text('0'));
      await tester.tap(find.text('0'));
      await tester.ensureVisible(find.text('Use Amount'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use Amount'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(input('0.00')).controller!.text,
        '500',
      );
    },
  );

  testWidgets('defaults save successfully without category or notes', (
    tester,
  ) async {
    await openForm(tester, initialAmount: '499');
    await tester.enterText(input('Subscription name'), 'Software');
    await tester.tap(find.text('Save Subscription'));
    await tester.pumpAndSettle();
    final item = await db.select(db.subscriptions).getSingle();
    expect(item.frequency, PaymentFrequency.monthly);
    expect(item.status, SubscriptionStatus.active);
    expect(formatDate(item.nextBillingDate), formatDate(DateTime.now()));
    expect(item.category, isNull);
    expect(item.notes, isNull);
  });

  for (final dark in [false, true]) {
    for (final size in [const Size(360, 640), const Size(412, 915)]) {
      testWidgets(
        'field spacing and keyboard accessibility ${dark ? 'dark' : 'light'} $size',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          tester.view.viewPadding = const FakeViewPadding(bottom: 24, top: 24);
          addTearDown(tester.view.reset);
          await openForm(
            tester,
            theme: dark ? AppTheme.dark() : AppTheme.light(),
          );
          for (final label in ['AMOUNT', 'NAME *', 'FREQUENCY', 'STATUS']) {
            expect(find.text(label), findsOneWidget);
          }
          await tester.drag(find.byType(ListView).last, const Offset(0, -1000));
          await tester.pumpAndSettle();
          expect(find.text('NOTES'), findsOneWidget);
          final notes = input('Optional notes');
          expect(notes, findsOneWidget);
          await tester.tap(notes);
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pumpAndSettle();
          await tester.enterText(notes, 'One\nTwo\nThree');
          final saveRect = tester.getRect(find.text('Save Subscription'));
          expect(saveRect.bottom, lessThanOrEqualTo(size.height - 280 - 20));
          expect(saveRect.height, greaterThan(0));
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('Close'));
          await tester.pumpAndSettle();
          expect(find.byType(SubscriptionFormSheet), findsNothing);
        },
      );
    }
  }
}
