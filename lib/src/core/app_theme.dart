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

@immutable
class AppTone {
  const AppTone(this.text, this.graphic, this.tint);

  final Color text;
  final Color graphic;
  final Color tint;

  AppTone lerp(AppTone other, double t) => AppTone(
    Color.lerp(text, other.text, t)!,
    Color.lerp(graphic, other.graphic, t)!,
    Color.lerp(tint, other.tint, t)!,
  );
}

@immutable
class HomePalette extends ThemeExtension<HomePalette> {
  const HomePalette({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.line,
    required this.text,
    required this.text2,
    required this.text3,
    required this.brand,
    required this.onBrand,
    required this.incoming,
    required this.emiTone,
    required this.owe,
    required this.bills,
    required this.out,
    required this.heroStart,
    required this.heroEnd,
    required this.heroText,
    required this.heroText2,
    required this.heroOut,
  });

  final Color bg, surface, surfaceAlt, line, text, text2, text3;
  final Color brand, onBrand, heroStart, heroEnd, heroText, heroText2, heroOut;
  final AppTone incoming, emiTone, owe, bills, out;

  Color get background => bg;
  Color get outline => line;
  Color get secondaryText => text2;
  Color get selectedFill => incoming.tint;
  Color get receive => incoming.graphic;
  Color get pay => owe.graphic;
  Color get emi => emiTone.graphic;
  Color get subscriptions => bills.graphic;

  AppColors get homeColors => AppColors(
    background: bg,
    surface: surface,
    surfaceContainer: surfaceAlt,
    surfaceHigh: surface,
    outline: line,
    text: text,
    secondaryText: text2,
    mutedText: text3,
    fieldFill: surfaceAlt,
    selectedFill: incoming.tint,
    receive: incoming.graphic,
    pay: owe.graphic,
    emi: emiTone.graphic,
    subscriptions: bills.graphic,
    lime: brand,
    navInactive: text3,
    navShadow: AppTheme.transparent,
  );

  @override
  HomePalette copyWith({
    Color? bg,
    surface,
    surfaceAlt,
    line,
    text,
    text2,
    text3,
    Color? brand,
    onBrand,
    heroStart,
    heroEnd,
    heroText,
    heroText2,
    heroOut,
    AppTone? incoming,
    emiTone,
    owe,
    bills,
    out,
  }) => HomePalette(
    bg: bg ?? this.bg,
    surface: surface ?? this.surface,
    surfaceAlt: surfaceAlt ?? this.surfaceAlt,
    line: line ?? this.line,
    text: text ?? this.text,
    text2: text2 ?? this.text2,
    text3: text3 ?? this.text3,
    brand: brand ?? this.brand,
    onBrand: onBrand ?? this.onBrand,
    incoming: incoming ?? this.incoming,
    emiTone: emiTone ?? this.emiTone,
    owe: owe ?? this.owe,
    bills: bills ?? this.bills,
    out: out ?? this.out,
    heroStart: heroStart ?? this.heroStart,
    heroEnd: heroEnd ?? this.heroEnd,
    heroText: heroText ?? this.heroText,
    heroText2: heroText2 ?? this.heroText2,
    heroOut: heroOut ?? this.heroOut,
  );

  @override
  HomePalette lerp(ThemeExtension<HomePalette>? other, double t) {
    if (other is! HomePalette) return this;
    Color blend(Color a, Color b) => Color.lerp(a, b, t)!;
    return HomePalette(
      bg: blend(bg, other.bg),
      surface: blend(surface, other.surface),
      surfaceAlt: blend(surfaceAlt, other.surfaceAlt),
      line: blend(line, other.line),
      text: blend(text, other.text),
      text2: blend(text2, other.text2),
      text3: blend(text3, other.text3),
      brand: blend(brand, other.brand),
      onBrand: blend(onBrand, other.onBrand),
      incoming: incoming.lerp(other.incoming, t),
      emiTone: emiTone.lerp(other.emiTone, t),
      owe: owe.lerp(other.owe, t),
      bills: bills.lerp(other.bills, t),
      out: out.lerp(other.out, t),
      heroStart: blend(heroStart, other.heroStart),
      heroEnd: blend(heroEnd, other.heroEnd),
      heroText: blend(heroText, other.heroText),
      heroText2: blend(heroText2, other.heroText2),
      heroOut: blend(heroOut, other.heroOut),
    );
  }
}

@immutable
class NetCardPalette {
  const NetCardPalette({
    required this.surface,
    required this.border,
    required this.text,
    required this.muted,
    required this.greenBar,
    required this.greenText,
    required this.redBar,
    required this.redText,
    required this.mutedRedBar,
    required this.lentBg,
    required this.borrowedBg,
    required this.debtBg,
    required this.selectedBg,
    required this.shadow,
  });

  final Color surface, border, text, muted;
  final Color greenBar, greenText, redBar, redText, mutedRedBar;
  final Color lentBg, borrowedBg, debtBg, selectedBg, shadow;
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
  static const homeCardOutline = Color(0xFFE6ECE9);
  static const primaryText = Color(0xFF0F172A);
  static const mutedText = Color(0xFF64748B);
  static const fieldFill = Color(0xFFF0F4F9);
  static const selectedFill = Color(0xFFECFDF5);
  static const darkBackground = Color(0xFF0B1110);
  static const darkPrimary = Color(0xFF3DDC97);
  static const darkOnPrimary = Color(0xFF04251A);
  static const darkDateAmber = Color(0xFFFBBF24);
  static const darkDateMuted = Color(0xFF9AA7A1);
  static const darkDateOverdue = Color(0xFFFCA5A5);
  static const darkUnpaid = Color(0xFFFBBF24);
  static const darkUnpaidFill = Color(0xFF3B2A07);
  static const darkPartial = Color(0xFF93C5FD);
  static const darkPartialFill = Color(0xFF1E3A5F);
  static const darkOverdue = Color(0xFFFCA5A5);
  static const darkOverdueFill = Color(0xFF4A1D1D);
  static const darkSettled = Color(0xFF86EFAC);
  static const darkSettledFill = Color(0xFF123524);
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
    navInactive: mutedText,
    navShadow: Color(0x09000000),
  );
  static const darkColors = AppColors(
    background: darkBackground,
    surface: Color(0xFF121A17),
    surfaceContainer: Color(0xFF18231F),
    surfaceHigh: Color(0xFF18231F),
    outline: Color(0xFF24312C),
    text: Color(0xFFE8EEEB),
    secondaryText: Color(0xFF9AA7A1),
    mutedText: Color(0xFF7F8E88),
    fieldFill: Color(0xFF1C2622),
    selectedFill: Color(0xFF12372A),
    receive: Color(0xFF4ADE80),
    pay: Color(0xFFF87171),
    emi: Color(0xFFFBBF24),
    subscriptions: Color(0xFFA78BFA),
    lime: accent,
    navInactive: Color(0xFF9AA7A1),
    navShadow: transparent,
  );

  static const lightHomePalette = HomePalette(
    bg: Color(0xFFF5F6F8),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEEF0F4),
    line: Color(0xFFE4E7EC),
    text: Color(0xFF0E1525),
    text2: Color(0xFF4B5565),
    text3: Color(0xFF667085),
    brand: Color(0xFF1D4ED8),
    onBrand: Color(0xFFFFFFFF),
    incoming: AppTone(Color(0xFF1D4ED8), Color(0xFF2563EB), Color(0xFFEFF6FF)),
    emiTone: AppTone(Color(0xFFB45309), Color(0xFFD97706), Color(0xFFFEF3E2)),
    owe: AppTone(Color(0xFF4F46E5), Color(0xFF4F46E5), Color(0xFFECEBFD)),
    bills: AppTone(Color(0xFF0369A1), Color(0xFF0284C7), Color(0xFFE6F3FA)),
    out: AppTone(Color(0xFFB91C1C), Color(0xFFDC2626), Color(0xFFFEF2F2)),
    heroStart: Color(0xFF0E1525),
    heroEnd: Color(0xFF1B2640),
    heroText: Color(0xFFFFFFFF),
    heroText2: Color(0xFFB6C0D2),
    heroOut: Color(0xFFCBD5E1),
  );
  static const darkHomePalette = HomePalette(
    bg: Color(0xFF0B1020),
    surface: Color(0xFF121A2C),
    surfaceAlt: Color(0xFF1A2338),
    line: Color(0xFF243049),
    text: Color(0xFFF2F5FA),
    text2: Color(0xFFA9B4C8),
    text3: Color(0xFF8491A8),
    brand: Color(0xFF60A5FA),
    onBrand: Color(0xFF071F3D),
    incoming: AppTone(Color(0xFF93C5FD), Color(0xFF60A5FA), Color(0xFF172B48)),
    emiTone: AppTone(Color(0xFFFBBF24), Color(0xFFFBBF24), Color(0xFF2E2A1C)),
    owe: AppTone(Color(0xFF818CF8), Color(0xFF818CF8), Color(0xFF1E2347)),
    bills: AppTone(Color(0xFF38BDF8), Color(0xFF38BDF8), Color(0xFF0F2A3A)),
    out: AppTone(Color(0xFFFCA5A5), Color(0xFFF87171), Color(0xFF3A1F22)),
    heroStart: Color(0xFF1A2338),
    heroEnd: Color(0xFF121A2C),
    heroText: Color(0xFFFFFFFF),
    heroText2: Color(0xFFB6C0D2),
    heroOut: Color(0xFFCBD5E1),
  );

  static const lightNetCard = NetCardPalette(
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFE6E8EF),
    text: Color(0xFF0F1320),
    muted: Color(0xFF667085),
    greenBar: Color(0xFF2563EB),
    greenText: Color(0xFF1D4ED8),
    redBar: Color(0xFFDC2626),
    redText: Color(0xFFB91C1C),
    mutedRedBar: Color(0xFFFCA5A5),
    lentBg: Color(0xFFEFF6FF),
    borrowedBg: Color(0xFFFEF2F2),
    debtBg: Color(0xFFF6F7FA),
    selectedBg: Color(0xFFFEF2F2),
    shadow: Color(0x14101828),
  );

  static const darkNetCard = NetCardPalette(
    surface: Color(0xFF151A22),
    border: Color(0x14FFFFFF),
    text: Color(0xFFF4F6FA),
    muted: Color(0xFF8F98A8),
    greenBar: Color(0xFF60A5FA),
    greenText: Color(0xFF93C5FD),
    redBar: Color(0xFFF87171),
    redText: Color(0xFFFCA5A5),
    mutedRedBar: Color(0x80F87171),
    lentBg: Color(0x1F60A5FA),
    borrowedBg: Color(0x1FF87171),
    debtBg: Color(0x0AFFFFFF),
    selectedBg: Color(0x1AF87171),
    shadow: Color(0x40000000),
  );

  static NetCardPalette netCardOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? darkNetCard
      : lightNetCard;

  static AppColors colorsOf(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? lightColors;

  static HomePalette homePaletteOf(BuildContext context) =>
      Theme.of(context).extension<HomePalette>() ?? lightHomePalette;

  static ThemeData neutralControlTheme(BuildContext context) {
    final theme = Theme.of(context);
    final palette = homePaletteOf(context);
    return theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        primary: palette.text,
        onPrimary: palette.bg,
        primaryContainer: palette.surfaceAlt,
        onPrimaryContainer: palette.text,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.bg
              : palette.text2,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.text
              : palette.surfaceAlt,
        ),
        trackOutlineColor: WidgetStatePropertyAll(palette.line),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: palette.text,
          foregroundColor: palette.bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

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
    final home = dark ? darkHomePalette : lightHomePalette;
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness)
        .copyWith(
          primary: dark ? darkPrimary : null,
          onPrimary: dark ? darkOnPrimary : null,
          secondary: dark ? accent : null,
          onSecondary: dark ? darkOnPrimary : null,
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
      extensions: [tokens, home],
      scaffoldBackgroundColor: home.bg,
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
          systemNavigationBarColor: home.bg,
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
          backgroundColor: dark ? darkPrimary : null,
          foregroundColor: dark ? darkOnPrimary : null,
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
