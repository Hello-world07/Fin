import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'core/app_theme.dart';
import 'core/app_lock.dart';
import 'core/providers.dart';
import 'core/notifications.dart';
import 'domain/reminder_schedule.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/emis/emis_screen.dart';
import 'features/emis/emi_overview_screen.dart';
import 'features/money/money_screen.dart';
import 'features/subscriptions/subscriptions_screen.dart';
import 'features/onboarding/intro_screen.dart';
import 'features/assistant/ask_finkeep_sheet.dart';
import 'shared/notched_navigation_bar.dart';

class FinKeepApp extends ConsumerWidget {
  const FinKeepApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(amountFormatProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    final privacy = ref.watch(privacyModeProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FinKeep',
      themeMode: themeMode,
      themeAnimationDuration: const Duration(milliseconds: 200),
      themeAnimationCurve: Curves.easeInOut,
      theme: AppTheme.light().copyWith(
        extensions: [
          AppTheme.lightColors,
          AppTheme.lightHomePalette,
          _PrivacyTheme(privacy.enabled),
        ],
      ),
      darkTheme: AppTheme.dark().copyWith(
        extensions: [
          AppTheme.darkColors,
          AppTheme.darkHomePalette,
          _PrivacyTheme(privacy.enabled),
        ],
      ),
      home: const IntroGate(child: AppShell()),
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: AppTheme.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: AppTheme.transparent,
            systemNavigationBarDividerColor: AppTheme.transparent,
            systemNavigationBarContrastEnforced: false,
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
  final _emiOverviewKey = GlobalKey<EmiOverviewScreenState>();
  bool _dockVisible = true;
  double _scrollTravel = 0;

  bool _handleScroll(ScrollUpdateNotification notification) {
    if (notification.metrics.axis != Axis.vertical ||
        notification.dragDetails == null) {
      return false;
    }
    final delta = notification.scrollDelta ?? 0;
    if (delta == 0) return false;
    final clearance = NotchedNavigationMetrics.tabContentPadding(context);
    if (notification.metrics.maxScrollExtent <= clearance + 24 ||
        (delta > 0 && notification.metrics.extentAfter <= 4)) {
      _scrollTravel = 0;
      if (!_dockVisible) setState(() => _dockVisible = true);
      return false;
    }
    if (delta < 0 && !_dockVisible) {
      _scrollTravel = 0;
      setState(() => _dockVisible = true);
      return false;
    }
    if (_scrollTravel.sign != delta.sign) _scrollTravel = 0;
    _scrollTravel += delta;
    if (_scrollTravel.abs() >= 12) {
      final visible = _scrollTravel < 0;
      _scrollTravel = 0;
      if (_dockVisible != visible) setState(() => _dockVisible = visible);
    }
    return false;
  }

  Widget _screenFor(int index) => switch (index) {
    0 => const DashboardScreen(),
    1 => EmiOverviewScreen(key: _emiOverviewKey),
    2 => const MoneyScreen(),
    _ => const SubscriptionsScreen(),
  };

  @override
  void initState() {
    super.initState();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    LocalReminderService().setOpenHandler(_openReminder);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        LocalReminderService().launchLink().then((link) {
          if (mounted && link != null) _openReminder(link);
        }),
      );
      unawaited(_runDeferredStartup());
    });
  }

  Future<void> _runDeferredStartup() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    await _runAutoBackup();
    if (!mounted) return;
    await _primeNotifications();
    if (!mounted) return;
    ref.read(assistantChatControllerProvider);
  }

  void _openReminder(ReminderDeepLink link) {
    if (!mounted) return;
    if (link.type == FinanceReminderType.emi) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => EmiDetailScreen(link.entityId)));
    } else if (link.type == FinanceReminderType.money) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MoneyDetailScreen(link.entityId)),
      );
    } else {
      unawaited(
        ref.read(financeRepositoryProvider).subscription(link.entityId).then((
          item,
        ) {
          if (mounted && item != null) {
            openSubscriptionDetailSheet(context, item);
          }
        }),
      );
    }
  }

  @override
  void dispose() {
    LocalReminderService().setOpenHandler(null);
    super.dispose();
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
    ref.listen(emiOverviewCategoryProvider, (_, _) {
      if (!_dockVisible) {
        setState(() {
          _dockVisible = true;
          _scrollTravel = 0;
        });
      }
    });
    final selected = ref.watch(shellIndexProvider);
    final index = selected >= 4 ? 0 : selected;
    final dockMotion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    _visitedTabs.add(index);
    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || index == 0) return;
        if (index == 1 &&
            _emiOverviewKey.currentState?.goBackWithinEmis() == true) {
          return;
        }
        ref.read(shellIndexProvider.notifier).state = 0;
        setState(() {
          _dockVisible = true;
          _scrollTravel = 0;
        });
      },
      child: Scaffold(
        extendBody: true,
        body: NavigationDockVisibility(
          visible: _dockVisible,
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: _handleScroll,
            child: IndexedStack(
              index: index,
              children: [
                for (var tab = 0; tab < 4; tab++)
                  _visitedTabs.contains(tab)
                      ? TickerMode(
                          enabled: tab == index,
                          child: _screenFor(tab),
                        )
                      : const SizedBox.shrink(),
              ],
            ),
          ),
        ),
        bottomNavigationBar: AnimatedSlide(
          offset: _dockVisible ? Offset.zero : const Offset(0, 1.25),
          duration: dockMotion,
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _dockVisible ? 1 : 0,
            duration: dockMotion,
            child: IgnorePointer(
              ignoring: !_dockVisible,
              child: NotchedNavigationBar(
                selectedIndex: index,
                onSelected: (value) {
                  setState(() {
                    _dockVisible = true;
                    _scrollTravel = 0;
                  });
                  ref.read(shellIndexProvider.notifier).state = value;
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
