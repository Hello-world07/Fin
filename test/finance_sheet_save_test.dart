import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/shared/forms.dart';

void main() {
  Future<void> openTestSheet(
    WidgetTester tester,
    Future<void> Function() save,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openFinanceSheet(
                context,
                Builder(
                  builder: (sheetContext) => TextButton(
                    onPressed: () => closeFinanceSheetAndSave(
                      sheetContext,
                      save,
                      errorMessage: 'Save failed',
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('persists after the sheet finishes closing', (tester) async {
    var saves = 0;
    await openTestSheet(tester, () async {
      saves++;
    });

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(saves, 0);
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('shows a snackbar when background persistence fails', (
    tester,
  ) async {
    await openTestSheet(tester, () async {
      throw StateError('storage');
    });

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Save failed'), findsOneWidget);
  });
}
