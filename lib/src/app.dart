import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_theme.dart';
import 'core/app_lock.dart';
import 'core/providers.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/emis/emis_screen.dart';
import 'features/money/money_screen.dart';
import 'features/more/more_screen.dart';
import 'features/subscriptions/subscriptions_screen.dart';

class FinKeepApp extends ConsumerWidget {
  const FinKeepApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FinKeep',
      themeMode: ref.watch(appThemeModeProvider),
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const AppLockGate(child: AppShell()),
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _screens = const [
    DashboardScreen(),
    EmisScreen(),
    MoneyScreen(),
    SubscriptionsScreen(),
    MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    ref.watch(databaseProvider);
    final index = ref.watch(shellIndexProvider);
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: AppTheme.motionDuration,
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeOut,
          child: _screens[index],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) =>
            ref.read(shellIndexProvider.notifier).state = value,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_outlined),
            label: 'EMIs',
          ),
          NavigationDestination(icon: Icon(Icons.swap_horiz), label: 'Money'),
          NavigationDestination(
            icon: Icon(Icons.autorenew),
            label: 'Subs',
            tooltip: 'Subscriptions',
          ),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}
