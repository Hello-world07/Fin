import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'core/app_theme.dart';
import 'core/app_lock.dart';
import 'core/providers.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/emis/emis_screen.dart';
import 'features/money/money_screen.dart';
import 'features/subscriptions/subscriptions_screen.dart';
import 'features/assistant/ask_finkeep_sheet.dart';
import 'shared/notched_navigation_bar.dart';

class FinKeepApp extends ConsumerWidget {
  const FinKeepApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(numberGroupingProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    final privacy = ref.watch(privacyModeProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FinKeep',
      themeMode: themeMode,
      themeAnimationDuration: const Duration(milliseconds: 200),
      themeAnimationCurve: Curves.easeInOut,
      theme: AppTheme.light().copyWith(
        extensions: [AppTheme.lightColors, _PrivacyTheme(privacy.enabled)],
      ),
      darkTheme: AppTheme.dark().copyWith(
        extensions: [AppTheme.darkColors, _PrivacyTheme(privacy.enabled)],
      ),
      home: const AppShell(),
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        final background = AppTheme.colorsOf(context).background;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: AppTheme.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: background,
            systemNavigationBarIconBrightness: dark
                ? Brightness.light
                : Brightness.dark,
          ),
          child: AppLockGate(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}

class _PrivacyTheme extends ThemeExtension<_PrivacyTheme> {
  const _PrivacyTheme(this.enabled);
  final bool enabled;

  @override
  _PrivacyTheme copyWith({bool? enabled}) =>
      _PrivacyTheme(enabled ?? this.enabled);

  @override
  _PrivacyTheme lerp(ThemeExtension<_PrivacyTheme>? other, double t) =>
      t < 0.5 ? this : (other ?? this) as _PrivacyTheme;
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _visitedTabs = <int>{0};

  Widget _screenFor(int index) => switch (index) {
    0 => const DashboardScreen(),
    1 => const EmisScreen(),
    2 => const MoneyScreen(),
    _ => const SubscriptionsScreen(),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SchedulerBinding.instance.scheduleTask(() {
        if (!mounted) return;
        ref.read(assistantChatControllerProvider);
        unawaited(_primeNotifications());
        unawaited(_runAutoBackup());
      }, Priority.idle);
    });
  }

  Future<void> _primeNotifications() async {
    try {
      await ref
          .read(financeRepositoryProvider)
          .primeSubscriptionNotifications();
    } catch (_) {
      // Reminders can be retried without delaying startup.
    }
  }

  Future<void> _runAutoBackup() async {
    try {
      await ref.read(financeRepositoryProvider).refreshDailyBrief();
    } catch (_) {
      // A reminder failure must not block startup or backup.
    }
    try {
      await ref.read(localBackupProvider).runAutoBackupIfDue();
      if (mounted) ref.invalidate(backupStatusProvider);
    } catch (_) {
      // Automatic backup must never interrupt app startup.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(databaseProvider);
    final selected = ref.watch(shellIndexProvider);
    final index = selected >= 4 ? 0 : selected;
    _visitedTabs.add(index);
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: index,
        children: [
          for (var tab = 0; tab < 4; tab++)
            _visitedTabs.contains(tab)
                ? TickerMode(enabled: tab == index, child: _screenFor(tab))
                : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NotchedNavigationBar(
        selectedIndex: index,
        onSelected: (value) =>
            ref.read(shellIndexProvider.notifier).state = value,
        onAsk: () => openAskFinKeep(context),
      ),
    );
  }
}
