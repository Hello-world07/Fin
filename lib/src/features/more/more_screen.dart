import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/enums.dart';
import '../../shared/calculator_sheet.dart';
import '../../shared/forms.dart';
import '../activity/activity_screen.dart';
import '../emis/emis_screen.dart';
import '../money/money_screen.dart';
import '../reminders/reminders_screen.dart';
import '../settings/settings_screen.dart';
import '../subscriptions/subscriptions_screen.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attention = ref
        .watch(remindersProvider)
        .maybeWhen(data: (items) => items.length, orElse: () => 0);
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calculate_outlined),
            title: const Text('Calculator'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openCalculator(
              context,
              onEmiDraft: (draft) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!context.mounted) return;
                  openFinanceSheet(
                    context,
                    EmiFormSheet(
                      initialEmiAmount: draft.monthlyEmi.toStringAsFixed(2),
                      initialPrincipal: draft.principal.toStringAsFixed(2),
                      initialInterestRate: draft.annualRate.toString(),
                      initialTenureMonths: draft.months,
                    ),
                  );
                });
              },
              onDestination: (destination, amount) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!context.mounted) return;
                  switch (destination) {
                    case CalculatorDestination.emi:
                      openFinanceSheet(
                        context,
                        EmiFormSheet(initialEmiAmount: amount),
                      );
                    case CalculatorDestination.moneyGiven:
                      openFinanceSheet(
                        context,
                        MoneyFormSheet(
                          initialAmount: amount,
                          initialDirection: MoneyDirection.given,
                        ),
                      );
                    case CalculatorDestination.moneyBorrowed:
                      openFinanceSheet(
                        context,
                        MoneyFormSheet(
                          initialAmount: amount,
                          initialDirection: MoneyDirection.borrowed,
                        ),
                      );
                    case CalculatorDestination.subscription:
                      openFinanceSheet(
                        context,
                        SubscriptionFormSheet(initialAmount: amount),
                      );
                  }
                });
              },
            ),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_note_outlined),
            title: const Text('Reminders'),
            subtitle: const Text('Upcoming payments and renewals'),
            trailing: attention > 0
                ? Badge(
                    label: Text('$attention'),
                    child: const Icon(Icons.chevron_right),
                  )
                : const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const RemindersScreen())),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history),
            title: const Text('Activity history'),
            subtitle: const Text('Changes and payments'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ActivityScreen())),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.tune),
            title: const Text('Settings'),
            subtitle: const Text('Appearance, privacy and backups'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Settings')),
                  body: const SafeArea(
                    child: SettingsScreen(showHeading: false),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
