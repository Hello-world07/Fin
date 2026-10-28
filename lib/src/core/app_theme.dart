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
  static const emiIdentityFill = Color(0xFF2563EB);
  static Color emiIdentityInkOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF8EB4FF)
      : emiIdentityFill;
  static const motionDuration = Duration(milliseconds: 225);
  static const seed = Color(0xFF2563EB);
  static const heroStart = Color(0xFF17243A);
  static const heroEnd = Color(0xFF233955);
  static const accent = Color(0xFF2563EB);
  static const receive = Color(0xFF0E7F6C);
  static const pay = Color(0xFFB83240);
  static const emi = pay;
  static const subscriptions = seed;
  static const pageBackground = Color(0xFFF4F6F9);
  static const homeCardOutline = Color(0xFFE2E8F0);
  static const primaryText = Color(0xFF17243A);
  static const mutedText = Color(0xFF607188);
  static const fieldMutedText = Color(0xFF586A82);
  static const fieldFill = Color(0xFFEAF1FC);
  static const selectedFill = fieldFill;
  static const darkBackground = Color(0xFF0D1624);
  static const darkPrimary = Color(0xFF8EB4FF);
  static const darkOnPrimary = Color(0xFF091629);
  static const darkDateAmber = Color(0xFFAFC9FF);
  static const darkDateMuted = Color(0xFFACBAD0);
  static const darkDateOverdue = Color(0xFFFF929B);
  static const darkUnpaid = Color(0xFFAFC9FF);
  static const darkUnpaidFill = Color(0xFF20365A);
  static const darkPartial = Color(0xFF8EB4FF);
  static const darkPartialFill = Color(0xFF20365A);
  static const darkOverdue = Color(0xFFFF929B);
  static const darkOverdueFill = Color(0xFF43242E);
  static const darkSettled = Color(0xFF65D9C1);
  static const darkSettledFill = Color(0xFF153A35);
  static const onHero = Color(0xFFFFFFFF);
  static const onHeroMuted = Color(0xB3FFFFFF);
  static const transparent = Color(0x00000000);
  static const avatarColors = <Color>[
    Color(0xFF17243A),
    Color(0xFF2563EB),
    Color(0xFF28496B),
    Color(0xFF36516F),
    Color(0xFF345A83),
    Color(0xFF1E466C),
  ];

  static const lightColors = AppColors(
    background: pageBackground,
    surface: Color(0xFFFFFFFF),
    surfaceContainer: fieldFill,
    surfaceHigh: Color(0xFFFFFFFF),
    outline: homeCardOutline,
    text: primaryText,
    secondaryText: mutedText,
    mutedText: fieldMutedText,
    fieldFill: fieldFill,
    selectedFill: selectedFill,
    receive: receive,
    pay: pay,
    emi: emi,
    subscriptions: subscriptions,
    lime: accent,
    navInactive: mutedText,
    navShadow: Color(0x1017243A),
  );
  static const darkColors = AppColors(
    background: darkBackground,
    surface: Color(0xFF152236),
    surfaceContainer: Color(0xFF1C2C43),
    surfaceHigh: Color(0xFF22334A),
    outline: Color(0xFF304158),
    text: Color(0xFFF3F7FC),
    secondaryText: Color(0xFFB8C5D8),
    mutedText: Color(0xFFAEBBD0),
    fieldFill: Color(0xFF1C2C43),
    selectedFill: Color(0xFF20365A),
    receive: Color(0xFF65D9C1),
    pay: Color(0xFFFF929B),
    emi: Color(0xFFFF929B),
    subscriptions: darkPrimary,
    lime: darkPrimary,
    navInactive: Color(0xFFAEBBD0),
    navShadow: transparent,
  );

  static const lightHomePalette = HomePalette(
    bg: pageBackground,
    surface: Color(0xFFFFFFFF),
    surfaceAlt: fieldFill,
    line: homeCardOutline,
    text: primaryText,
    text2: mutedText,
    text3: fieldMutedText,
    brand: seed,
    onBrand: Color(0xFFFFFFFF),
    incoming: AppTone(receive, receive, Color(0xFFE7F5F0)),
    emiTone: AppTone(pay, pay, Color(0xFFFCEBEC)),
    owe: AppTone(pay, pay, Color(0xFFFCEBEC)),
    bills: AppTone(seed, seed, fieldFill),
    out: AppTone(pay, pay, Color(0xFFFCEBEC)),
    heroStart: heroStart,
    heroEnd: heroEnd,
    heroText: Color(0xFFFFFFFF),
    heroText2: Color(0xFFB6C0D2),
    heroOut: Color(0xFFCBD5E1),
  );
  static const darkHomePalette = HomePalette(
    bg: darkBackground,
    surface: Color(0xFF152236),
    surfaceAlt: Color(0xFF1C2C43),
    line: Color(0xFF304158),
    text: Color(0xFFF3F7FC),
    text2: Color(0xFFB8C5D8),
    text3: Color(0xFFAEBBD0),
    brand: darkPrimary,
    onBrand: darkOnPrimary,
    incoming: AppTone(Color(0xFF65D9C1), Color(0xFF65D9C1), Color(0xFF153A35)),
    emiTone: AppTone(Color(0xFFFF929B), Color(0xFFFF929B), Color(0xFF43242E)),
    owe: AppTone(Color(0xFFFF929B), Color(0xFFFF929B), Color(0xFF43242E)),
    bills: AppTone(darkPrimary, darkPrimary, Color(0xFF20365A)),
    out: AppTone(Color(0xFFFF929B), Color(0xFFFF929B), Color(0xFF43242E)),
    heroStart: Color(0xFF203149),
    heroEnd: Color(0xFF17243A),
    heroText: Color(0xFFFFFFFF),
    heroText2: Color(0xFFB6C0D2),
    heroOut: Color(0xFFCBD5E1),
  );

  static const lightNetCard = NetCardPalette(
    surface: Color(0xFFFFFFFF),
    border: homeCardOutline,
    text: primaryText,
    muted: mutedText,
    greenBar: receive,
    greenText: receive,
    redBar: pay,
    redText: pay,
    mutedRedBar: Color(0xFFE09BA2),
    lentBg: Color(0xFFE7F5F0),
    borrowedBg: Color(0xFFFCEBEC),
    debtBg: fieldFill,
    selectedBg: Color(0xFFFCEBEC),
    shadow: Color(0x1017243A),
  );

  static const darkNetCard = NetCardPalette(
    surface: Color(0xFF152236),
    border: Color(0x14FFFFFF),
    text: Color(0xFFF3F7FC),
    muted: Color(0xFFB8C5D8),
    greenBar: Color(0xFF65D9C1),
    greenText: Color(0xFF65D9C1),
    redBar: Color(0xFFFF929B),
    redText: Color(0xFFFF929B),
    mutedRedBar: Color(0x80FF929B),
    lentBg: Color(0xFF153A35),
    borrowedBg: Color(0xFF43242E),
    debtBg: Color(0xFF1C2C43),
    selectedBg: Color(0xFF43242E),
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
        primary: palette.brand,
        onPrimary: palette.onBrand,
        primaryContainer: palette.surfaceAlt,
        onPrimaryContainer: palette.text,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.onBrand
              : palette.text2,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.brand
              : palette.surfaceAlt,
        ),
        trackOutlineColor: WidgetStatePropertyAll(palette.line),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: palette.brand,
          foregroundColor: palette.onBrand,
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
          primary: dark ? darkPrimary : seed,
          onPrimary: dark ? darkOnPrimary : onHero,
          primaryContainer: tokens.selectedFill,
          onPrimaryContainer: tokens.text,
          secondary: tokens.receive,
          onSecondary: dark ? darkOnPrimary : onHero,
          secondaryContainer: home.incoming.tint,
          onSecondaryContainer: tokens.text,
          tertiary: tokens.emi,
          onTertiary: dark ? darkOnPrimary : onHero,
          surface: tokens.surface,
          onSurface: tokens.text,
          onSurfaceVariant: tokens.secondaryText,
          surfaceContainerLowest: tokens.background,
          surfaceContainerLow: tokens.surface,
          surfaceContainer: tokens.surfaceContainer,
          surfaceContainerHigh: tokens.surfaceHigh,
          surfaceContainerHighest: tokens.surfaceHigh,
          outline: tokens.outline,
          outlineVariant: tokens.outline,
          error: tokens.pay,
          onError: dark ? darkOnPrimary : onHero,
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
      scaffoldBackgroundColor: tokens.background,
      canvasColor: tokens.background,
      disabledColor: tokens.mutedText,
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
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: tokens.surface,
      ),
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      inputDecorationTheme: InputDecorationTheme(
        fillColor: tokens.fieldFill,
        hintStyle: TextStyle(color: tokens.mutedText),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: tokens.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: tokens.surfaceHigh,
        contentTextStyle: TextStyle(color: tokens.text, fontFamily: fontFamily),
        actionTextColor: scheme.primary,
      ),
      dialogTheme: DialogThemeData(
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
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: tokens.surfaceHigh,
        headerForegroundColor: tokens.text,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.surface,
        modalBackgroundColor: tokens.surface,
        surfaceTintColor: transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: tokens.surfaceHigh,
        textStyle: TextStyle(color: tokens.text, fontFamily: fontFamily),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: tokens.surfaceContainer,
        selectedColor: tokens.selectedFill,
        labelStyle: TextStyle(color: tokens.text, fontFamily: fontFamily),
        secondaryLabelStyle: TextStyle(
          color: tokens.text,
          fontFamily: fontFamily,
        ),
        side: BorderSide(color: tokens.outline),
      ),
      switchTheme: SwitchThemeData(
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
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
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
