import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/core/app_theme.dart';
import 'package:personal_finance/src/core/providers.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';
import 'package:personal_finance/src/domain/enums.dart';
import 'package:personal_finance/src/features/emis/emis_screen.dart';
import 'package:personal_finance/src/shared/finance_form_widgets.dart';

void main() {
  testWidgets('method and monthly rate recalculate the EMI in the form', (
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
          home: const Scaffold(
            body: EmiFormSheet(
              initialPrincipal: '20000',
              initialEmiAmount: '10000',
              initialInterestRate: '20',
              initialTenureMonths: 2,
            ),
          ),
        ),
      ),
    );
    final scroll = find
        .descendant(
          of: find.byType(EmiFormSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Per month'),
      160,
      scrollable: scroll,
    );
    tester
        .widget<SegmentedToggle<EmiRatePeriod>>(
          find.byType(SegmentedToggle<EmiRatePeriod>),
        )
        .onSelectionChanged!({EmiRatePeriod.monthly});
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byType(HeroAmountInput),
      -160,
      scrollable: scroll,
    );
    expect(
      tester
          .widget<HeroAmountInput>(
            find.byType(HeroAmountInput, skipOffstage: false),
          )
          .controller
          .text,
      '13090.91',
    );
    await tester.scrollUntilVisible(
      find.text('Flat rate'),
      120,
      scrollable: scroll,
    );
    tester
        .widget<SegmentedToggle<EmiInterestMethod>>(
          find.byType(SegmentedToggle<EmiInterestMethod>),
        )
        .onSelectionChanged!({EmiInterestMethod.flat});
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byType(HeroAmountInput),
      -160,
      scrollable: scroll,
    );
    expect(
      tester
          .widget<HeroAmountInput>(
            find.byType(HeroAmountInput, skipOffstage: false),
          )
          .controller
          .text,
      '14000',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets(
    'locked contract EMI survives rate changes with mismatch warning',
    (tester) async {
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
            home: const Scaffold(
              body: EmiFormSheet(
                initialPrincipal: '20000',
                initialEmiAmount: '14000',
                initialInterestRate: '20',
                initialTenureMonths: 2,
              ),
            ),
          ),
        ),
      );
      final scroll = find
          .descendant(
            of: find.byType(EmiFormSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      tester
          .widget<SwitchListTile>(
            find.byType(SwitchListTile, skipOffstage: false),
          )
          .onChanged!(true);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Per month'),
        130,
        scrollable: scroll,
      );
      tester
          .widget<SegmentedToggle<EmiRatePeriod>>(
            find.byType(SegmentedToggle<EmiRatePeriod>),
          )
          .onSelectionChanged!({EmiRatePeriod.monthly});
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byType(HeroAmountInput),
        -160,
        scrollable: scroll,
      );
      expect(
        tester
            .widget<HeroAmountInput>(
              find.byType(HeroAmountInput, skipOffstage: false),
            )
            .controller
            .text,
        '14000',
      );
      await tester.drag(scroll, const Offset(0, -3000));
      await tester.pump();
      expect(
        find.textContaining('Entered EMI', skipOffstage: false),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}
