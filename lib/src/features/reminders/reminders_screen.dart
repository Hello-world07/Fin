import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../data/repositories.dart';
import '../../domain/enums.dart';
import '../../domain/emi_payment_rules.dart';
import '../../shared/forms.dart';
import '../../shared/async_view.dart';
import '../../shared/empty_state.dart';
import '../emis/emis_screen.dart';
import '../money/money_screen.dart';
import '../subscriptions/subscriptions_screen.dart';

class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: AsyncView(
        value: ref.watch(remindersProvider),
        builder: (items) {
          final active = items
              .where((item) => item.status != ReminderStatus.completed)
              .toList();
          if (active.isEmpty) {
            return const EmptyState(
              icon: Icons.event_available_outlined,
              title: 'Nothing due',
              message:
                  'Overdue items and payments due within 5 days will appear here.',
            );
          }
          final today = dateOnly(DateTime.now());
          final groups = <String, List<ReminderItem>>{
            'Overdue': active
                .where((item) => item.status == ReminderStatus.overdue)
                .toList(),
            'Due today': active
                .where((item) => item.status == ReminderStatus.dueToday)
                .toList(),
            'Due tomorrow': active
                .where(
                  (item) =>
                      item.status == ReminderStatus.upcoming &&
                      dateOnly(item.dueAt).difference(today).inDays == 1,
                )
                .toList(),
            'Due soon · within 5 days': active
                .where(
                  (item) =>
                      item.status == ReminderStatus.upcoming &&
                      dateOnly(item.dueAt).difference(today).inDays >= 2 &&
                      !dateOnly(
                        item.dueAt,
                      ).isAfter(today.add(emiPaymentWindow)),
                )
                .toList(),
          };
          final rows = <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Text(
                'Showing overdue items and payments due within 5 days.',
              ),
            ),
            for (final group in groups.entries)
              if (group.value.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 4),
                  child: Text(
                    group.key,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                for (final item in group.value) ...[
                  _ReminderTile(item: item),
                  const Divider(height: 1),
                ],
              ],
          ];
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: rows,
          );
        },
      ),
    );
  }
}

class _ReminderTile extends ConsumerStatefulWidget {
  const _ReminderTile({required this.item});

  final ReminderItem item;

  @override
  ConsumerState<_ReminderTile> createState() => _ReminderTileState();
}

class _ReminderTileState extends ConsumerState<_ReminderTile> {
  bool _paying = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final color = switch (item.status) {
      ReminderStatus.overdue => Theme.of(context).colorScheme.error,
      ReminderStatus.dueToday => Theme.of(context).colorScheme.primary,
      ReminderStatus.upcoming => Theme.of(context).colorScheme.secondary,
      ReminderStatus.completed => Theme.of(context).colorScheme.outline,
    };
    final canPay =
        item.entityType == 'emi' &&
        item.isNextInstallment &&
        isWithinEmiPaymentWindow(item.dueAt, DateTime.now());
    final isPaying = _paying;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      leading: Icon(_icon, color: color),
      title: Text(
        '${switch (item.entityType) {
          'emi' => 'EMI',
          'money' => 'Money',
          _ => 'Subscription',
        }} · ${item.title}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${formatMoney(item.amountPaise)} · Due ${formatDate(item.dueAt)}'
        '${item.installmentNumber == null ? '' : ' · installment ${item.installmentNumber}'}',
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            item.subtitle.split(' · ').first,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
          if (canPay)
            TextButton(
              onPressed: isPaying
                  ? null
                  : () async {
                      if (_paying) return;
                      setState(() => _paying = true);
                      try {
                        final ok = await ref
                            .read(financeRepositoryProvider)
                            .markEmiPaid(
                              item.entityId,
                              expectedDueDate: item.dueAt,
                              expectedInstallmentNumber: item.installmentNumber,
                            );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? 'EMI payment recorded.'
                                    : 'This installment was already recorded or is no longer payable.',
                              ),
                            ),
                          );
                        }
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Could not record this payment.'),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _paying = false);
                      }
                    },
              child: Text(isPaying ? 'Saving...' : 'Mark paid'),
            ),
        ],
      ),
      onTap: () {
        if (item.entityType == 'emi') {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => EmiDetailScreen(item.entityId)),
          );
        } else if (item.entityType == 'money') {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => MoneyDetailScreen(item.entityId)),
          );
        } else {
          openFinanceSheet(
            context,
            FutureBuilder(
              future: ref
                  .read(financeRepositoryProvider)
                  .subscription(item.entityId),
              builder: (context, snapshot) =>
                  snapshot.connectionState != ConnectionState.done
                  ? const SafeArea(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    )
                  : snapshot.data == null
                  ? const SafeArea(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'This subscription is no longer available.',
                        ),
                      ),
                    )
                  : SubscriptionFormSheet(subscription: snapshot.data),
            ),
          );
        }
      },
    );
  }

  IconData get _icon => switch (widget.item.entityType) {
    'emi' => Icons.account_balance_outlined,
    'money' => Icons.swap_horiz,
    _ => Icons.autorenew,
  };
}
