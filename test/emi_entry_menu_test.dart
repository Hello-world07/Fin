import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/core/app_theme.dart';
import 'package:personal_finance/src/core/providers.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';
import 'package:personal_finance/src/features/emis/emis_screen.dart';
import 'package:personal_finance/src/shared/finance_form_widgets.dart';
import 'package:personal_finance/src/shared/notched_navigation_bar.dart';

void main() {
  testWidgets('EMI add menu opens the chosen form without a second chooser', (
    tester,
  ) async {
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          financeRepositoryProvider.overrideWithValue(FinanceRepository(db)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAddMenu(context, tabIndex: 1),
                child: const Text('Open EMI menu'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open EMI menu'));
    await tester.pumpAndSettle();
    expect(find.text('My personal loan or credit card'), findsOneWidget);
    expect(find.text('Money I gave to someone'), findsOneWidget);
    expect(find.text('Credit card account'), findsNothing);
    expect(find.text('What do you want to track?'), findsNothing);

    await tester.tap(find.text('Money I gave to someone'));
    await tester.pumpAndSettle();
    expect(find.text('TYPE'), findsOneWidget);
    final formScroll = find
        .descendant(
          of: find.byType(EmiFormSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('LENDER'),
      180,
      scrollable: formScroll,
    );
    expect(find.text('LENDER'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('INSTALLMENT TO RECEIVE'),
      180,
      scrollable: formScroll,
    );
    expect(find.text('INSTALLMENT TO RECEIVE'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('PRINCIPAL (OPTIONAL)'),
      180,
      scrollable: formScroll,
    );
    expect(find.text('PRINCIPAL (OPTIONAL)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('AGREEMENT DATE'),
      180,
      scrollable: formScroll,
    );
    expect(find.text('AGREEMENT DATE'), findsOneWidget);
    expect(find.text('What do you want to track?'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('already paid accepts only installment counts within tenure', (
    tester,
  ) async {
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          financeRepositoryProvider.overrideWithValue(FinanceRepository(db)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: EmiFormSheet(initialTenureMonths: 2)),
        ),
      ),
    );

    final formScroll = find
        .descendant(
          of: find.byType(EmiFormSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('EMIS ALREADY PAID'),
      180,
      scrollable: formScroll,
    );
    final paidField = find.descendant(
      of: find.ancestor(
        of: find.text('EMIS ALREADY PAID'),
        matching: find.byType(FilledField),
      ),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(paidField);
    expect(
      find.text('Number of installments already paid (0–2)'),
      findsOneWidget,
    );

    for (final count in ['0', '1', '2']) {
      await tester.enterText(paidField, count);
      await tester.pump();
      expect(find.textContaining('Cannot exceed'), findsNothing);
      expect(find.textContaining('whole-number count'), findsNothing);
    }
    await tester.enterText(paidField, '3');
    await tester.pump();
    expect(find.text('Cannot exceed 2 installments'), findsOneWidget);

    for (final invalid in ['1.5', '₹1,000', '-1']) {
      await tester.enterText(paidField, invalid);
      await tester.pump();
      expect(
        find.text('Enter a whole-number count, not an amount'),
        findsOneWidget,
      );
    }
    await tester.enterText(paidField, '');
    await tester.pump();
    expect(find.text('Enter how many installments are paid'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('product EMI shows its own fields in dark mode', (tester) async {
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          financeRepositoryProvider.overrideWithValue(FinanceRepository(db)),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: EmiFormSheet()),
        ),
      ),
    );
    expect(find.text('PRODUCT PRICE', skipOffstage: false), findsNothing);
    await tester.tap(find.text('Phone / Product'));
    await tester.pump();
    final formScroll = find
        .descendant(
          of: find.byType(EmiFormSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Interest & fees'),
      60,
      scrollable: formScroll,
    );
    tester
        .widget<InkWell>(
          find.ancestor(
            of: find.text('Interest & fees'),
            matching: find.byType(InkWell),
          ),
        )
        .onTap!();
    await tester.pump();
    await tester.drag(formScroll, const Offset(0, 1500));
    await tester.pump();
    for (final label in [
      'PRODUCT PRICE',
      'DOWN PAYMENT (OPTIONAL)',
      'INTEREST METHOD',
      'FEES (OPTIONAL)',
    ]) {
      if (!tester.any(find.text(label))) {
        await tester.scrollUntilVisible(
          find.text(label),
          60,
          scrollable: formScroll,
        );
      }
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
