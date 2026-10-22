import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/core/providers.dart';
import 'package:personal_finance/src/core/app_theme.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';
import 'package:personal_finance/src/domain/enums.dart';
import 'package:personal_finance/src/features/emis/emis_screen.dart';

void main() {
  testWidgets('EMI income percentage follows the persisted income setting', (
    tester,
  ) async {
    final database = AppDatabase.test(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = FinanceRepository(database);
    final today = DateUtils.dateOnly(DateTime.now());
    await repository.saveEmi(
      EmisCompanion.insert(
        name: 'Phone',
        principalPaise: 440000,
        emiAmountPaise: 220000,
        tenureMonths: 2,
        startDate: today,
        nextDueDate: today,
        frequency: PaymentFrequency.monthly,
        status: EmiStatus.active,
      ),
    );

    Future<void> saveIncome(String value) => database
        .into(database.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: 'emi.monthlyIncomePaise', value: value),
        );

    await saveIncome('1000000');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          financeRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: EmisScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('22%'), findsOneWidget);

    await saveIncome('0');
    await tester.pumpAndSettle();
    expect(find.text('+ Add'), findsOneWidget);

    await saveIncome('2000000');
    await tester.pumpAndSettle();
    expect(find.text('11%'), findsOneWidget);

    await saveIncome('440000');
    await tester.pumpAndSettle();
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('Very high'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets(
    'cancelled EMI swipe returns smoothly without recording payment',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 720);
      addTearDown(tester.view.reset);
      final database = AppDatabase.test(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = FinanceRepository(database);
      final today = DateUtils.dateOnly(DateTime.now());
      final id = await repository.saveEmi(
        EmisCompanion.insert(
          name: 'Phone',
          principalPaise: 440000,
          emiAmountPaise: 220000,
          tenureMonths: 2,
          startDate: today,
          nextDueDate: today,
          frequency: PaymentFrequency.monthly,
          status: EmiStatus.active,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            financeRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: EmisScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final name = find.text('Phone');
      final originalX = tester.getTopLeft(name).dx;
      final gesture = await tester.startGesture(tester.getCenter(name));
      await gesture.moveBy(const Offset(90, 0));
      await tester.pump();
      expect(tester.getTopLeft(name).dx, greaterThan(originalX + 20));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getTopLeft(name).dx, lessThan(originalX + 70));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(name).dx, closeTo(originalX, 1));
      expect((await repository.emiDetail(id)).payments, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets('EMI summary and rows fit small light and dark layouts', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = AppDatabase.test(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = FinanceRepository(database);
    final today = DateUtils.dateOnly(DateTime.now());
    await repository.saveEmi(
      EmisCompanion.insert(
        name: 'Phone installment',
        principalPaise: 440000,
        emiAmountPaise: 220000,
        tenureMonths: 2,
        startDate: today,
        nextDueDate: today,
        frequency: PaymentFrequency.monthly,
        status: EmiStatus.active,
      ),
    );
    for (final width in [360.0, 412.0]) {
      tester.view.physicalSize = Size(width, 760);
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(database),
              financeRepositoryProvider.overrideWithValue(repository),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
              home: const EmisScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${width}dp, ${dark ? 'dark' : 'light'}',
        );
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets(
    'accepted early swipe confirms before recording one installment',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 720);
      addTearDown(tester.view.reset);
      final database = AppDatabase.test(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = FinanceRepository(database);
      final due = DateUtils.dateOnly(
        DateTime.now().add(const Duration(days: 20)),
      );
      final id = await repository.saveEmi(
        EmisCompanion.insert(
          name: 'Phone',
          principalPaise: 440000,
          emiAmountPaise: 220000,
          tenureMonths: 2,
          startDate: due,
          nextDueDate: due,
          frequency: PaymentFrequency.monthly,
          status: EmiStatus.active,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            financeRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: EmisScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Phone')),
      );
      await gesture.moveBy(const Offset(260, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Pay early?'), findsOneWidget);
      expect((await repository.emiDetail(id)).payments, isEmpty);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Mark paid'),
        ),
      );
      await tester.pumpAndSettle();
      expect((await repository.emiDetail(id)).payments, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}
