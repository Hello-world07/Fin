import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/core/formatters.dart';
import 'package:personal_finance/src/core/providers.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/shared/finance_display_widgets.dart';

void main() {
  tearDown(() => privacyAmountsHidden = false);

  test('privacy mode and hide-on-open survive a new session', () async {
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    final first = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    final controller = first.read(privacyModeProvider.notifier);
    await controller.ready;
    await controller.setHideOnOpen(true);
    first.dispose();

    final second = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(second.dispose);
    await second.read(privacyModeProvider.notifier).ready;
    expect(second.read(privacyModeProvider).enabled, isTrue);
    expect(formatMoney(10000000), hiddenAmount);
  });

  testWidgets('hidden AmountText reveals only while pressed', (tester) async {
    privacyAmountsHidden = true;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AmountText(10000000))),
    );
    expect(find.text(hiddenAmount), findsOneWidget);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(AmountText)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('₹1,00,000'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(find.text(hiddenAmount), findsOneWidget);
  });

  test('existing activity and assistant strings mask amounts', () {
    privacyAmountsHidden = true;
    expect(
      hideMoneyInText('Nivas repaid ₹1,00,000'),
      'Nivas repaid $hiddenAmount',
    );
    expect(hideMoneyInText('₹10,000 (Ten thousand)'), hiddenAmount);
    expect(hideMoneyInText('Rs 50 or ₹ 1,000'), '$hiddenAmount or $hiddenAmount');
  });
}
