import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:personal_finance/src/core/app_theme.dart';
import 'package:personal_finance/src/core/providers.dart';
import 'package:personal_finance/src/data/backup_service.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';
import 'package:personal_finance/src/domain/enums.dart';
import 'package:personal_finance/src/features/dashboard/dashboard_screen.dart';

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('Home categories and monthly chart fit 360dp in $mode', (
      tester,
    ) async {
      final db = AppDatabase.test(NativeDatabase.memory());
      final repo = FinanceRepository(db);
      addTearDown(db.close);
      final due = DateTime.now().add(const Duration(days: 1));
      for (final (name, type) in [
        ('Bank', 'Loan'),
        ('Ravi', friendRepaymentType),
      ]) {
        await repo.saveEmi(
          EmisCompanion.insert(
            name: name,
            principalPaise: 200000,
            emiAmountPaise: 100000,
            tenureMonths: 2,
            startDate: due,
            nextDueDate: due,
            frequency: PaymentFrequency.monthly,
            status: EmiStatus.active,
            type: Value(type),
          ),
        );
      }
      await tester.binding.setSurfaceSize(const Size(360, 800));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            financeRepositoryProvider.overrideWithValue(repo),
            backupStatusProvider.overrideWith(
              (ref) async => const BackupStatus(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: mode,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: const DashboardScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Personal EMI debt'), findsOneWidget);
      expect(find.text('Given-to-others EMI'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Monthly outlook'),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Monthly outlook'), findsOneWidget);
      final month = DateTime.now();
      final column = find.byKey(
        ValueKey('home-month-${month.year}-${month.month}'),
      );
      await tester.ensureVisible(column);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'after chart scroll');
      await tester.tap(column);
      await tester.pumpAndSettle();
      expect(find.text(DateFormat('MMMM yyyy').format(month)), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'after month sheet');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Next 5 weeks'),
        -260,
        scrollable: find.byType(Scrollable).first,
      );
      final forecastWeek = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'forecast-week-',
            ),
      );
      expect(forecastWeek, findsNWidgets(5));
      await tester.ensureVisible(forecastWeek.first);
      await tester.pumpAndSettle();
      await tester.tap(forecastWeek.first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'after week flyout');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  }
}
