import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/shared/notched_navigation_bar.dart';

void main() {
  testWidgets('dock clearance stays stable while visibility changes', (
    tester,
  ) async {
    Future<double> paddingFor(bool visible) async {
      var padding = 0.0;
      await tester.pumpWidget(
        MaterialApp(
          home: NavigationDockVisibility(
            visible: visible,
            child: Builder(
              builder: (context) {
                padding = NotchedNavigationMetrics.tabContentPadding(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      return padding;
    }

    final visiblePadding = await paddingFor(true);
    final hiddenPadding = await paddingFor(false);
    expect(hiddenPadding, visiblePadding);
  });

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
                      contentPadding =
                          NotchedNavigationMetrics.tabContentPadding(context);
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
        expect(contentPadding, 92 + bottomInset);
        expect(NotchedNavigationMetrics.fabBottomPadding, 76);
        expect(find.byTooltip('Home'), findsOneWidget);
        expect(find.byTooltip('EMIs'), findsOneWidget);
        expect(find.byTooltip('Money'), findsOneWidget);
        expect(find.byTooltip('Bills'), findsOneWidget);
        await tester.tap(find.byTooltip('Bills'));
        await tester.pumpAndSettle();
        expect(selected, 3);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Ask FinKeep'));
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
    await tester.tap(find.byTooltip('EMIs'));
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
