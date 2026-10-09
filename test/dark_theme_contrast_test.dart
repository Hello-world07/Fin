import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/core/app_theme.dart';

void main() {
  test('dark primary text pairs meet WCAG AA contrast', () {
    final theme = AppTheme.dark();
    final tokens = AppTheme.darkColors;
    final scheme = theme.colorScheme;
    final pairs = <(Color, Color)>[
      (tokens.text, tokens.background),
      (tokens.text, tokens.surface),
      (tokens.text, tokens.surfaceContainer),
      (scheme.onPrimary, scheme.primary),
      (tokens.mutedText, tokens.fieldFill),
    ];
    for (final (foreground, background) in pairs) {
      final high = math.max(
        foreground.computeLuminance(),
        background.computeLuminance(),
      );
      final low = math.min(
        foreground.computeLuminance(),
        background.computeLuminance(),
      );
      expect((high + 0.05) / (low + 0.05), greaterThanOrEqualTo(4.5));
    }
  });
}
