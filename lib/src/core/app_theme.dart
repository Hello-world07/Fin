import 'package:flutter/material.dart';

class AppTheme {
  static const fontFamily = 'Plus Jakarta Sans';
  static const motionDuration = Duration(milliseconds: 225);
  static const seed = Color(0xFF059669);
  static const heroStart = Color(0xFF0B3D3A);
  static const heroEnd = Color(0xFF0F6B5C);
  static const accent = Color(0xFFC6F432);
  static const receive = Color(0xFF10B981);
  static const pay = Color(0xFFF43F5E);
  static const emi = Color(0xFFF59E0B);
  static const subscriptions = Color(0xFF7C3AED);
  static const pageBackground = Color(0xFFF6F8F7);
  static const primaryText = Color(0xFF0F172A);
  static const mutedText = Color(0xFF64748B);
  static const fieldFill = Color(0xFFF0F4F9);
  static const selectedFill = Color(0xFFECFDF5);
  static const darkBackground = Color(0xFF0E1512);
  static const onHero = Color(0xFFFFFFFF);
  static const onHeroMuted = Color(0xB3FFFFFF);
  static const transparent = Color(0x00000000);

  static ThemeData light() =>
      _base(Brightness.light).copyWith(scaffoldBackgroundColor: pageBackground);

  static ThemeData dark() =>
      _base(Brightness.dark).copyWith(scaffoldBackgroundColor: darkBackground);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final textColor = brightness == Brightness.light
        ? primaryText
        : scheme.onSurface;
    final textTheme = _textTheme(
      ThemeData(brightness: brightness).textTheme,
      textColor,
    );
    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: brightness == Brightness.light
            ? pageBackground
            : darkBackground,
        surfaceTintColor: transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: textColor,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      listTileTheme: const ListTileThemeData(minVerticalPadding: 10),
      navigationBarTheme: NavigationBarThemeData(
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base, Color color) {
    TextStyle style(TextStyle? value) => (value ?? const TextStyle()).copyWith(
      fontFamily: fontFamily,
      color: color,
      letterSpacing: 0,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return TextTheme(
      displayLarge: style(base.displayLarge),
      displayMedium: style(base.displayMedium),
      displaySmall: style(base.displaySmall),
      headlineLarge: style(base.headlineLarge),
      headlineMedium: style(base.headlineMedium),
      headlineSmall: style(base.headlineSmall),
      titleLarge: style(base.titleLarge),
      titleMedium: style(base.titleMedium),
      titleSmall: style(base.titleSmall),
      bodyLarge: style(base.bodyLarge),
      bodyMedium: style(base.bodyMedium),
      bodySmall: style(base.bodySmall),
      labelLarge: style(base.labelLarge),
      labelMedium: style(base.labelMedium),
      labelSmall: style(base.labelSmall),
    );
  }
}
