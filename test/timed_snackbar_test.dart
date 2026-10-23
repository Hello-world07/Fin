import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/shared/timed_snackbar.dart';

void main() {
  testWidgets('undo message closes after its window with accessibility on', (
    tester,
  ) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messengerKey,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
          child: child!,
        ),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    showTimedSnackBar(
      messengerKey.currentState!,
      SnackBar(
        content: const Text('Moved to Deleted'),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(label: 'Undo', onPressed: () {}),
      ),
    );
    await tester.pump();
    expect(find.text('Moved to Deleted'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Moved to Deleted'), findsNothing);
  });
}
