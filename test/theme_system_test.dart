import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/core/app_theme.dart';
import 'package:personal_finance/src/shared/finance_display_widgets.dart';

void main() {
  testWidgets('bundles every Plus Jakarta Sans weight', (tester) async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
    final family = manifest.cast<Map<String, dynamic>>().singleWhere(
      (entry) => entry['family'] == AppTheme.fontFamily,
    );
    final fonts = (family['fonts'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(fonts.map((font) => font['weight']), [400, 500, 600, 700, 800]);
    for (final font in fonts) {
      expect(
        (await rootBundle.load(font['asset'] as String)).lengthInBytes,
        greaterThan(0),
      );
    }
  });

  test('light and dark text themes use the same bundled family', () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final styles = [
        theme.textTheme.displayLarge,
        theme.textTheme.displayMedium,
        theme.textTheme.displaySmall,
        theme.textTheme.headlineLarge,
        theme.textTheme.headlineMedium,
        theme.textTheme.headlineSmall,
        theme.textTheme.titleLarge,
        theme.textTheme.titleMedium,
        theme.textTheme.titleSmall,
        theme.textTheme.bodyLarge,
        theme.textTheme.bodyMedium,
        theme.textTheme.bodySmall,
        theme.textTheme.labelLarge,
        theme.textTheme.labelMedium,
        theme.textTheme.labelSmall,
      ];
      for (final style in styles) {
        expect(style?.fontFamily, AppTheme.fontFamily);
        expect(
          style?.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
      }
      expect(theme.appBarTheme.titleTextStyle?.fontFamily, AppTheme.fontFamily);
    }
  });

  testWidgets('AmountText formats Indian grouping with the app font', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: AmountText(10000000)),
      ),
    );
    final amount = tester.widget<Text>(find.text('₹1,00,000'));
    expect(amount.style?.fontFamily, AppTheme.fontFamily);
    expect(
      amount.style?.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
  });
}
