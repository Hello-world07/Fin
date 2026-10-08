import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/shared/calculator_sheet.dart';
import 'package:personal_finance/src/shared/calculator_modes.dart';

void main() {
  testWidgets('calculator updates only its display and returns the result', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await openCalculator(context, amountLabel: 'Amount');
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7'));
    await tester.tap(find.text('+'));
    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();
    expect(find.text('₹12'), findsOneWidget);
    await tester.ensureVisible(find.text('Use Amount'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use Amount'));
    await tester.pumpAndSettle();
    expect(result, '12');
  });

  testWidgets('history reuses a result and destination receives an amount', (
    tester,
  ) async {
    CalculatorDestination? destination;
    String? amount;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openCalculator(
                context,
                onDestination: (kind, value) {
                  destination = kind;
                  amount = value;
                },
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AC'));
    await tester.tap(find.text('2'));
    await tester.tap(find.text('+'));
    await tester.tap(find.text('3'));
    await tester.ensureVisible(find.text('='));
    await tester.pumpAndSettle();
    await tester.tap(find.text('='));
    await tester.pumpAndSettle();
    expect(find.text('2+3 = 5'), findsOneWidget);
    await tester.ensureVisible(find.text('Use this amount'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this amount'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ActionChip, 'EMI'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'EMI'));
    await tester.pumpAndSettle();
    expect(destination, CalculatorDestination.emi);
    expect(amount, '5');
  });

  testWidgets('EMI mode passes all entered values to the Add EMI draft', (
    tester,
  ) async {
    CalculatorEmiDraft? draft;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  openCalculator(context, onEmiDraft: (value) => draft = value),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EMI'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '120000');
    await tester.enterText(fields.at(1), '0');
    await tester.enterText(fields.at(2), '12');
    await tester.pumpAndSettle();
    expect(find.text('₹10,000'), findsOneWidget);
    await tester.ensureVisible(find.text('Add this as EMI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add this as EMI'));
    await tester.pumpAndSettle();
    expect(draft?.principal, 120000);
    expect(draft?.annualRate, 0);
    expect(draft?.months, 12);
    expect(draft?.monthlyEmi, 10000);
  });
}
