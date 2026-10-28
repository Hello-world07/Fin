import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/core/app_theme.dart';
import 'package:personal_finance/src/shared/finance_display_widgets.dart';

void main() {
  test('finance palette is shared across light and dark themes', () {
    const navy = Color(0xFF17243A);
    const blue = Color(0xFF2563EB);
    const teal = Color(0xFF0E7F6C);
    const red = Color(0xFFB83240);
    final light = AppTheme.light();
    final dark = AppTheme.dark();

    expect(light.colorScheme.primary, blue);
    expect(light.scaffoldBackgroundColor, const Color(0xFFF4F6F9));
    expect(AppTheme.lightColors.text, navy);
    expect(AppTheme.lightHomePalette.incoming.text, teal);
    expect(AppTheme.lightHomePalette.out.text, red);
    expect(AppTheme.lightNetCard.greenBar, teal);
    expect(AppTheme.lightNetCard.redBar, red);
    expect(dark.colorScheme.primary, AppTheme.darkPrimary);
    expect(AppTheme.darkHomePalette.incoming.text, AppTheme.darkColors.receive);
    expect(AppTheme.darkHomePalette.out.text, AppTheme.darkColors.pay);
  });

  test('finance text and amount colors meet readable contrast', () {
    double contrast(Color a, Color b) {
      final high = math.max(a.computeLuminance(), b.computeLuminance());
      final low = math.min(a.computeLuminance(), b.computeLuminance());
      return (high + .05) / (low + .05);
    }

    for (final tokens in [AppTheme.lightColors, AppTheme.darkColors]) {
      for (final background in [tokens.background, tokens.surface]) {
        expect(contrast(tokens.text, background), greaterThanOrEqualTo(4.5));
        expect(
          contrast(tokens.secondaryText, background),
          greaterThanOrEqualTo(4.5),
        );
        expect(contrast(tokens.receive, background), greaterThanOrEqualTo(4.5));
        expect(contrast(tokens.pay, background), greaterThanOrEqualTo(4.5));
      }
      expect(
        contrast(tokens.mutedText, tokens.fieldFill),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

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
