import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceContainer,
    required this.surfaceHigh,
    required this.outline,
    required this.text,
    required this.secondaryText,
    required this.mutedText,
    required this.fieldFill,
    required this.selectedFill,
    required this.receive,
    required this.pay,
    required this.emi,
    required this.subscriptions,
    required this.lime,
    required this.navInactive,
    required this.navShadow,
  });

  final Color background, surface, surfaceContainer, surfaceHigh, outline;
  final Color text, secondaryText, mutedText, fieldFill, selectedFill;
  final Color receive, pay, emi, subscriptions, lime;
  final Color navInactive, navShadow;

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceContainer,
    Color? surfaceHigh,
    Color? outline,
    Color? text,
    Color? secondaryText,
    Color? mutedText,
    Color? fieldFill,
    Color? selectedFill,
    Color? receive,
    Color? pay,
    Color? emi,
    Color? subscriptions,
    Color? lime,
    Color? navInactive,
    Color? navShadow,
  }) => AppColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceContainer: surfaceContainer ?? this.surfaceContainer,
    surfaceHigh: surfaceHigh ?? this.surfaceHigh,
    outline: outline ?? this.outline,
    text: text ?? this.text,
    secondaryText: secondaryText ?? this.secondaryText,
    mutedText: mutedText ?? this.mutedText,
    fieldFill: fieldFill ?? this.fieldFill,
    selectedFill: selectedFill ?? this.selectedFill,
    receive: receive ?? this.receive,
    pay: pay ?? this.pay,
    emi: emi ?? this.emi,
    subscriptions: subscriptions ?? this.subscriptions,
    lime: lime ?? this.lime,
    navInactive: navInactive ?? this.navInactive,
    navShadow: navShadow ?? this.navShadow,
  );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color blend(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: blend(background, other.background),
      surface: blend(surface, other.surface),
      surfaceContainer: blend(surfaceContainer, other.surfaceContainer),
      surfaceHigh: blend(surfaceHigh, other.surfaceHigh),
      outline: blend(outline, other.outline),
      text: blend(text, other.text),
      secondaryText: blend(secondaryText, other.secondaryText),
      mutedText: blend(mutedText, other.mutedText),
      fieldFill: blend(fieldFill, other.fieldFill),
      selectedFill: blend(selectedFill, other.selectedFill),
      receive: blend(receive, other.receive),
      pay: blend(pay, other.pay),
      emi: blend(emi, other.emi),
      subscriptions: blend(subscriptions, other.subscriptions),
      lime: blend(lime, other.lime),
      navInactive: blend(navInactive, other.navInactive),
      navShadow: blend(navShadow, other.navShadow),
    );
  }
}

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
  static const darkBackground = Color(0xFF0E1412);
  static const onHero = Color(0xFFFFFFFF);
  static const onHeroMuted = Color(0xB3FFFFFF);
  static const transparent = Color(0x00000000);

  static const lightColors = AppColors(
    background: pageBackground,
    surface: Color(0xFFFFFFFF),
    surfaceContainer: fieldFill,
    surfaceHigh: Color(0xFFFFFFFF),
    outline: Color(0xFFDDE5E1),
    text: primaryText,
    secondaryText: mutedText,
    mutedText: mutedText,
    fieldFill: fieldFill,
    selectedFill: selectedFill,
    receive: receive,
    pay: pay,
    emi: emi,
    subscriptions: subscriptions,
    lime: accent,
    navInactive: Color(0xFF94A3B8),
    navShadow: Color(0x09000000),
  );
  static const darkColors = AppColors(
    background: darkBackground,
    surface: Color(0xFF151D1A),
    surfaceContainer: Color(0xFF1C2622),
    surfaceHigh: Color(0xFF243029),
    outline: Color(0xFF33413B),
    text: Color(0xFFE8EEEB),
    secondaryText: Color(0xFFA9B7B1),
    mutedText: Color(0xFF7F8E88),
    fieldFill: Color(0xFF1C2622),
    selectedFill: Color(0xFF12372A),
    receive: Color(0xFF34D399),
    pay: Color(0xFFFB7185),
    emi: Color(0xFFFBBF24),
    subscriptions: Color(0xFFA78BFA),
    lime: accent,
    navInactive: Color(0xFF7F8E88),
    navShadow: transparent,
  );

  static AppColors colorsOf(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? lightColors;

  static Color heroTextOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? darkColors.text
      : onHero;

  static Color heroMutedOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? darkColors.text
      : onHeroMuted;

  static ThemeData light() => _base(Brightness.light);

  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final tokens = dark ? darkColors : lightColors;
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness)
        .copyWith(
          primary: dark ? const Color(0xFF3DDC97) : null,
          onPrimary: dark ? const Color(0xFF04261B) : null,
          secondary: dark ? accent : null,
          onSecondary: dark ? const Color(0xFF04261B) : null,
          secondaryContainer: dark ? tokens.selectedFill : null,
          onSecondaryContainer: dark ? tokens.text : null,
          surface: dark ? tokens.surface : null,
          onSurface: dark ? tokens.text : null,
          onSurfaceVariant: dark ? tokens.secondaryText : null,
          surfaceContainerLowest: dark ? tokens.background : null,
          surfaceContainerLow: dark ? tokens.surface : null,
          surfaceContainer: dark ? tokens.surfaceContainer : null,
          surfaceContainerHigh: dark ? tokens.surfaceHigh : null,
          surfaceContainerHighest: dark ? tokens.surfaceHigh : null,
          outline: dark ? tokens.outline : null,
          outlineVariant: dark ? tokens.outline : null,
          primaryContainer: dark ? tokens.selectedFill : null,
          onPrimaryContainer: dark ? tokens.text : null,
          error: dark ? const Color(0xFFFF6B6B) : null,
          onError: dark ? darkBackground : null,
        );
    final textColor = tokens.text;
    final textTheme = _textTheme(
      ThemeData(brightness: brightness).textTheme,
      textColor,
    );
    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: scheme,
      extensions: [tokens],
      scaffoldBackgroundColor: tokens.background,
      canvasColor: dark ? tokens.background : null,
      disabledColor: dark ? tokens.mutedText : null,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: tokens.background,
        surfaceTintColor: transparent,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: transparent,
          statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          statusBarBrightness: dark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: tokens.background,
          systemNavigationBarIconBrightness: dark
              ? Brightness.light
              : Brightness.dark,
        ),
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
        fillColor: dark ? tokens.fieldFill : null,
        hintStyle: dark ? TextStyle(color: tokens.mutedText) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      snackBarTheme: dark
          ? SnackBarThemeData(
              backgroundColor: tokens.surfaceHigh,
              contentTextStyle: TextStyle(
                color: tokens.text,
                fontFamily: fontFamily,
              ),
              actionTextColor: scheme.primary,
            )
          : null,
      dialogTheme: dark
          ? DialogThemeData(
              backgroundColor: tokens.surfaceHigh,
              titleTextStyle: TextStyle(
                color: tokens.text,
                fontFamily: fontFamily,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              contentTextStyle: TextStyle(
                color: tokens.secondaryText,
                fontFamily: fontFamily,
              ),
            )
          : null,
      datePickerTheme: dark
          ? DatePickerThemeData(
              backgroundColor: tokens.surfaceHigh,
              headerForegroundColor: tokens.text,
            )
          : null,
      bottomSheetTheme: dark
          ? BottomSheetThemeData(
              backgroundColor: tokens.surface,
              modalBackgroundColor: tokens.surface,
              surfaceTintColor: transparent,
            )
          : null,
      popupMenuTheme: dark
          ? PopupMenuThemeData(
              color: tokens.surfaceHigh,
              textStyle: TextStyle(color: tokens.text, fontFamily: fontFamily),
            )
          : null,
      chipTheme: dark
          ? ChipThemeData(
              backgroundColor: tokens.surfaceContainer,
              selectedColor: tokens.selectedFill,
              labelStyle: TextStyle(color: tokens.text, fontFamily: fontFamily),
              secondaryLabelStyle: TextStyle(
                color: tokens.text,
                fontFamily: fontFamily,
              ),
              side: BorderSide(color: tokens.outline),
            )
          : null,
      switchTheme: dark
          ? SwitchThemeData(
              thumbColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? scheme.onPrimary
                    : tokens.secondaryText,
              ),
              trackColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? scheme.primary
                    : tokens.surfaceContainer,
              ),
            )
          : null,
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
