import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/shared/notched_navigation_bar.dart';

void main() {
  for (final (width, bottomInset) in [(360.0, 24.0), (412.0, 48.0)]) {
    testWidgets(
      'notched bar fits ${width.toInt()}dp with ${bottomInset.toInt()}dp inset',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewPadding);
        var selected = 0;
        var asks = 0;
        late double contentPadding;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 800),
                padding: EdgeInsets.only(bottom: bottomInset),
                viewPadding: EdgeInsets.only(bottom: bottomInset),
              ),
              child: StatefulBuilder(
                builder: (context, setState) => Scaffold(
                  extendBody: true,
                  body: Builder(
                    builder: (context) {
                      contentPadding = NotchedNavigationMetrics.contentPadding(
                        context,
                        hasFab: true,
                      );
                      return const SizedBox.expand();
                    },
                  ),
                  bottomNavigationBar: NotchedNavigationBar(
                    selectedIndex: selected,
                    onSelected: (value) => setState(() => selected = value),
                    onAsk: () => asks++,
                  ),
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(contentPadding, 172 + bottomInset);
        expect(NotchedNavigationMetrics.fabBottomPadding, 76);
        expect(find.text('Home'), findsOneWidget);
        expect(find.text('EMIs'), findsOneWidget);
        expect(find.text('Money'), findsOneWidget);
        expect(find.text('Subs'), findsOneWidget);
        await tester.tap(find.text('Subs'));
        await tester.pumpAndSettle();
        expect(selected, 3);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byIcon(Icons.auto_awesome_rounded));
        await tester.pumpAndSettle();
        expect(asks, 1);
      },
    );
  }

  testWidgets('keyboard hides the bar and reduced motion keeps tabs usable', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              bottomNavigationBar: NotchedNavigationBar(
                selectedIndex: selected,
                onSelected: (value) => setState(() => selected = value),
                onAsk: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('EMIs'));
    await tester.pump();
    expect(selected, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(viewInsets: EdgeInsets.only(bottom: 300)),
          child: Scaffold(
            bottomNavigationBar: NotchedNavigationBar(
              selectedIndex: 0,
              onSelected: _noop,
              onAsk: _noop,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Home'), findsNothing);
  });
}

void _noop([int? _]) {}
