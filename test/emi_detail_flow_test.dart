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
  late AppDatabase database;
  late FinanceRepository repository;

  setUp(() {
    database = AppDatabase.test(NativeDatabase.memory());
    repository = FinanceRepository(database);
  });
  tearDown(() => database.close());

  testWidgets('early payment confirmation and history use the same schedule', (
    tester,
  ) async {
    final emiId = await repository.saveEmi(
      EmisCompanion.insert(
        name: 'slice',
        principalPaise: 1000000,
        emiAmountPaise: 500000,
        tenureMonths: 2,
        startDate: DateTime(2026, 11, 1),
        nextDueDate: DateTime(2026, 11, 30),
        frequency: PaymentFrequency.monthly,
        status: EmiStatus.active,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [financeRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: EmiDetailScreen(emiId)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mark November 2026 paid'), findsOneWidget);
    expect(find.text('Pay early'), findsOneWidget);
    await tester.tap(find.text('Pay early'));
    await tester.pumpAndSettle();
    expect(find.textContaining('due 01 Nov 2026'), findsOneWidget);
    expect(find.text('18 Dec 2026'), findsNothing);
    await tester.tap(find.text('Mark paid'));
    await tester.pumpAndSettle();

    expect(find.text('Scheduled: 01 Nov 2026'), findsOneWidget);
    expect(find.text('Paid early'), findsOneWidget);
    expect(find.text('Mark December 2026 paid'), findsOneWidget);
    expect(find.textContaining('due 01 Dec 2026'), findsNothing);

    await tester.tap(find.text('Pay early'));
    await tester.pumpAndSettle();
    expect(find.textContaining('due 01 Dec 2026'), findsOneWidget);
    await tester.tap(find.text('Mark paid'));
    await tester.pumpAndSettle();

    expect(find.text('Mark December 2026 paid'), findsNothing);
    expect(find.text('Scheduled: 01 Dec 2026'), findsOneWidget);
    expect((await repository.emiDetail(emiId)).payments, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
