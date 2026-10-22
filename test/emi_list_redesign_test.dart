import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/core/providers.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';
import 'package:personal_finance/src/domain/enums.dart';
import 'package:personal_finance/src/features/emis/emis_screen.dart';

void main() {
  testWidgets('active and completed tabs use the installment schedule', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.reset);
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = FinanceRepository(db);
    Future<int> create(String name, int tenure, DateTime due) => repo.saveEmi(
      EmisCompanion.insert(
        name: name,
        principalPaise: tenure * 500000,
        emiAmountPaise: 500000,
        tenureMonths: tenure,
        startDate: due,
        nextDueDate: due,
        frequency: PaymentFrequency.monthly,
        status: EmiStatus.active,
      ),
    );

    final sliceId = await create('Slice', 2, DateTime(2026, 11, 1));
    await create('Bike', 3, DateTime(2026, 10, 20));
    final doneId = await create('Old phone', 1, DateTime(2026, 9, 1));
    final done = await repo.emiDetail(doneId);
    await repo.markEmiPaid(
      doneId,
      expectedDueDate: done.nextUnpaidInstallment!.dueDate,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          financeRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: EmisScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Active 2'), findsOneWidget);
    expect(find.text('Completed 1'), findsOneWidget);
    expect(find.text('Slice'), findsOneWidget);
    expect(find.text('Bike'), findsOneWidget);
    expect(find.text('Old phone'), findsNothing);
    expect(find.text('Sun 1 Nov'), findsOneWidget);

    final first = (await repo.emiDetail(sliceId)).nextUnpaidInstallment!;
    await repo.markEmiPaid(sliceId, expectedDueDate: first.dueDate);
    await tester.pumpAndSettle();
    expect(find.text('Sun 1 Nov'), findsNothing);
    expect(find.text('Tue 1 Dec'), findsOneWidget);

    final second = (await repo.emiDetail(sliceId)).nextUnpaidInstallment!;
    await repo.markEmiPaid(sliceId, expectedDueDate: second.dueDate);
    await tester.pumpAndSettle();
    expect(find.text('Active 1'), findsOneWidget);
    expect(find.text('Completed 2'), findsOneWidget);
    expect(find.text('Slice'), findsNothing);

    await tester.tap(find.text('Completed 2'));
    await tester.pumpAndSettle();
    expect(find.text('Old phone'), findsOneWidget);
    expect(find.text('Slice'), findsOneWidget);
    expect(find.text('All 1 paid'), findsOneWidget);
    expect(find.text('All 2 paid'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
