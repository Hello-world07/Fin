import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/core/app_theme.dart';
import 'package:personal_finance/src/core/providers.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';
import 'package:personal_finance/src/features/emis/emis_screen.dart';
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
    expect(find.text('What do you want to track?'), findsNothing);

    await tester.tap(find.text('Money I gave to someone'));
    await tester.pumpAndSettle();
    expect(find.text('INSTALLMENT TO RECEIVE'), findsOneWidget);
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
      find.text('PRINCIPAL'),
      180,
      scrollable: formScroll,
    );
    expect(find.text('PRINCIPAL'), findsOneWidget);
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
}
