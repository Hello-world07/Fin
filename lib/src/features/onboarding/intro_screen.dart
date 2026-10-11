import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
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
  bool _finishing = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      final db = ref.read(databaseProvider);
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
    final pages = <(IconData, String, List<String>)>[
      (
        Icons.account_balance_wallet_outlined,
        'Everything you owe and are owed',
        [
          'EMIs with debt-free dates and installments',
          'Money given or borrowed with repayments',
          'Subscriptions with renewals',
        ],
      ),
      (
        Icons.auto_awesome_outlined,
        'Ask FinKeep',
        [
          'Ask about your money',
          'Do quick maths',
          'Cancel, pause or delete by chat with confirmation and voice input',
        ],
      ),
      (
        Icons.notifications_active_outlined,
        'Never miss a payment',
        [
          'Reminders for each section',
          'Privacy mode hides amounts',
          'App lock with PIN or fingerprint',
        ],
      ),
      (
        Icons.shield_outlined,
        'Private by design',
        [
          'Everything stays on this phone',
          'One-tap backup to your own folder',
          'Recycle bin for deleted items',
        ],
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
                  itemCount: pages.length,
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
                            for (final line in pages[index].$3) ...[
                              Text(
                                line,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 10),
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
                  for (var index = 0; index < pages.length; index++)
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
                      : _page == pages.length - 1
                      ? _finish
                      : () => _pages.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        ),
                  child: Text(
                    _page == pages.length - 1 ? 'Get started' : 'Next',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
