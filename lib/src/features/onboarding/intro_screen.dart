import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_lock.dart';
import '../../core/notifications.dart';
import '../../core/providers.dart';
import '../../core/pin_keypad.dart';
import '../../data/database.dart';

final introSeenProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final setting = await (db.select(
    db.settings,
  )..where((row) => row.key.equals('intro.seen'))).getSingleOrNull();
  if (setting?.value == 'true') return true;
  final counts = await db
      .customSelect(
        'SELECT (SELECT COUNT(*) FROM emis) + (SELECT COUNT(*) FROM money_records) + '
        '(SELECT COUNT(*) FROM subscriptions) AS total',
      )
      .getSingle();
  return counts.read<int>('total') > 0;
});

class IntroGate extends ConsumerWidget {
  const IntroGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(introSeenProvider)
      .when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, _) => child,
        data: (seen) => seen ? child : const IntroScreen(),
      );
}

class IntroScreen extends ConsumerStatefulWidget {
  const IntroScreen({super.key, this.replay = false});
  final bool replay;

  @override
  ConsumerState<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends ConsumerState<IntroScreen> {
  final _pages = PageController();
  int _page = 0;
  bool _reminders = false;
  bool _lock = false;
  bool _finishing = false;
  String? _pin;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _toggleReminders(bool enabled) async {
    if (enabled && !await LocalReminderService().requestPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Allow notifications to use reminders.'),
          ),
        );
      }
      return;
    }
    if (mounted) setState(() => _reminders = enabled);
  }

  Future<void> _toggleLock(bool enabled) async {
    if (!enabled) {
      setState(() {
        _lock = false;
        _pin = null;
      });
      return;
    }
    final pin = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const PinSetupScreen()));
    if (mounted && pin != null) {
      setState(() {
        _pin = pin;
        _lock = true;
      });
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      final db = ref.read(databaseProvider);
      if (_reminders) {
        final repo = ref.read(financeRepositoryProvider);
        try {
          await repo.saveReminderSettings(
            (await repo.reminderSettings()).copyWith(enabled: true),
          );
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Reminders could not start. Try again in Settings.',
                ),
              ),
            );
          }
        }
      }
      if (_lock && _pin != null) {
        await PinLockService().setPin(_pin!);
        await db
            .into(db.settings)
            .insertOnConflictUpdate(
              SettingsCompanion.insert(
                key: 'privacy.appLock.enabled',
                value: 'true',
              ),
            );
        if (mounted) ref.invalidate(appLockSettingsProvider);
      }
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(key: 'intro.seen', value: 'true'),
          );
      if (!mounted) return;
      if (widget.replay) {
        Navigator.pop(context);
      } else {
        ref.invalidate(introSeenProvider);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not finish setup. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pages = <(IconData, String, String)>[
      (
        Icons.account_balance_wallet_outlined,
        'All your EMIs, money and subscriptions in one place',
        'See what is due and what is left at a glance.',
      ),
      (
        Icons.shield_outlined,
        'Private by design: everything stays on this phone, no account',
        'Your records are stored in private app storage.',
      ),
      (
        Icons.notifications_active_outlined,
        'Never miss a payment, and ask FinKeep anything',
        'Local reminders and the offline assistant are here when you need them.',
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _finishing ? null : _finish,
                  child: const Text('Skip'),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: 3,
                  onPageChanged: (index) => setState(() => _page = index),
                  itemBuilder: (context, index) => LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              pages[index].$1,
                              size: 94,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(height: 28),
                            Text(
                              pages[index].$2,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              pages[index].$3,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium,
                            ),
                            if (index == 2) ...[
                              const SizedBox(height: 22),
                              SwitchListTile(
                                title: const Text('Turn on reminders'),
                                value: _reminders,
                                onChanged: _finishing ? null : _toggleReminders,
                              ),
                              SwitchListTile(
                                title: const Text('Set app lock'),
                                value: _lock,
                                onChanged: _finishing ? null : _toggleLock,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var index = 0; index < 3; index++)
                    Container(
                      width: index == _page ? 18 : 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: index == _page
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _finishing
                      ? null
                      : _page == 2
                      ? _finish
                      : () => _pages.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        ),
                  child: Text(_page == 2 ? 'Get started' : 'Next'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
