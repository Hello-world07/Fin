import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/core/providers.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';
import 'package:personal_finance/src/features/assistant/assistant_commands.dart';
import 'package:personal_finance/src/features/assistant/assistant_engine.dart';
import 'package:personal_finance/src/features/assistant/ask_finkeep_sheet.dart';
import 'package:personal_finance/src/features/money/money_screen.dart';

class _StubEngine implements AssistantEngine {
  int calls = 0;

  @override
  Future<AssistantReply> ask(String question, ConversationContext ctx) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    return const AssistantReply(
      'Here is your local summary.',
      rows: [AssistantRow('To receive', '₹100')],
      chart: AssistantChart(
        kind: AssistantChartKind.bar,
        fraction: 0.5,
        label: 'EMI share',
      ),
      actions: [AssistantAction('Open EMIs', AssistantDestination.emis)],
    );
  }
}

class _DraftEngine implements AssistantEngine {
  @override
  Future<AssistantReply> ask(String question, ConversationContext ctx) async =>
      const AssistantReply(
        'Opening the Money form with ₹500. Check it and tap Save.',
        openForm: AssistantFormDraft(
          kind: AssistantFormKind.moneyGiven,
          amountPaise: 50000,
          name: 'Nivas',
        ),
      );
}

void main() {
  testWidgets('command opens a prefilled form without saving', (tester) async {
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          assistantEngineProvider.overrideWithValue(_DraftEngine()),
          moneyRecordsProvider.overrideWith(
            (ref) => Stream.value(<MoneyRecordDetail>[]),
          ),
          paymentMethodsProvider.overrideWith(
            (ref) => Stream.value(<PaymentMethod>[]),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => openAskFinKeep(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'I gave Nivas 500');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(MoneyFormSheet), findsOneWidget);
    expect(find.text('Nivas'), findsWidgets);
    expect(await db.select(db.moneyRecords).get(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close').last);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
  testWidgets(
    'chat suggestions, rich reply, clear, and keyboard remain usable',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [assistantEngineProvider.overrideWithValue(_StubEngine())],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => openAskFinKeep(context),
                  child: const Text('Open assistant'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open assistant'));
      await tester.pumpAndSettle();
      expect(find.text('Ask FinKeep'), findsOneWidget);
      expect(find.text('My financial status'), findsOneWidget);
      expect(
        find.text('Answers use only data on this phone. Not financial advice.'),
        findsOneWidget,
      );

      await tester.tap(find.text('My financial status'));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(find.text('Here is your local summary.'), findsOneWidget);
      expect(find.text('₹100'), findsOneWidget);
      expect(find.text('Open EMIs'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear chat'));
      await tester.pumpAndSettle();
      expect(find.text('Here is your local summary.'), findsNothing);
      await tester.tap(find.byType(TextField));
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Send'), findsOneWidget);
    },
  );

  for (final (size, keyboardHeight) in [
    (const Size(360, 640), 280.0),
    (const Size(640, 360), 180.0),
  ]) {
    testWidgets('input stays visible with keyboard at $size', (tester) async {
      final engine = _StubEngine();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [assistantEngineProvider.overrideWithValue(engine)],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => openAskFinKeep(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
      await tester.pumpAndSettle();
      final field = find.byType(TextField);
      expect(
        tester.getBottomLeft(field).dy,
        lessThanOrEqualTo(size.height - keyboardHeight),
      );
      await tester.enterText(field, 'What is due?');
      expect(find.text('What is due?'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(engine.calls, 1);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
