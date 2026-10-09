import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../core/notifications.dart';
import '../../data/repositories.dart';
import '../../domain/reminder_schedule.dart';
import '../../domain/enums.dart';
import '../../domain/emi_payment_rules.dart';
import '../../shared/forms.dart';
import '../../shared/async_view.dart';
import '../../shared/empty_state.dart';
import '../emis/emis_screen.dart';
import '../money/money_screen.dart';
import '../subscriptions/subscriptions_screen.dart';

class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key});

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen> {
  ReminderPlanSettings? _settings;
  bool _permissionGranted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await ref
        .read(financeRepositoryProvider)
        .reminderSettings();
    final granted = await LocalReminderService().permissionGranted();
    if (mounted) {
      setState(() {
        _settings = settings;
        _permissionGranted = granted;
      });
    }
  }

  Future<void> _save(ReminderPlanSettings next) async {
    if (next.enabled && _settings?.enabled != true) {
      final granted = await LocalReminderService().requestPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Allow notifications to turn reminders on.'),
            ),
          );
        }
        await _load();
        return;
      }
    }
    if (!mounted) return;
    await ref.read(financeRepositoryProvider).saveReminderSettings(next);
    if (mounted) {
      setState(() {
        _settings = next;
        _permissionGranted = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: Column(
        children: [
          if (settings != null)
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        title: const Text('Reminders'),
                        value: settings.enabled,
                        onChanged: (value) =>
                            _save(settings.copyWith(enabled: value)),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Time',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final (label, hour) in [
                            ('8 AM', 8),
                            ('9 AM', 9),
                            ('6 PM', 18),
                          ])
                            ChoiceChip(
                              label: Text(label),
                              selected:
                                  settings.hour == hour && settings.minute == 0,
                              onSelected: (_) => _save(
                                settings.copyWith(hour: hour, minute: 0),
                              ),
                            ),
                          ActionChip(
                            label: Text(
                              settings.minute == 0 &&
                                      [8, 9, 18].contains(settings.hour)
                                  ? 'Custom'
                                  : '${settings.hour.toString().padLeft(2, '0')}:${settings.minute.toString().padLeft(2, '0')}',
                            ),
                            onPressed: () async {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay(
                                  hour: settings.hour,
                                  minute: settings.minute,
                                ),
                              );
                              if (time != null && mounted) {
                                await _save(
                                  settings.copyWith(
                                    hour: time.hour,
                                    minute: time.minute,
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Remind me',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final (label, days) in [
                            ('7 days', 7),
                            ('3 days', 3),
                            ('1 day', 1),
                            ('Due day', 0),
                          ])
                            FilterChip(
                              label: Text(label),
                              selected: settings.leadDays.contains(days),
                              onSelected: (value) {
                                final leads = {...settings.leadDays};
                                value ? leads.add(days) : leads.remove(days);
                                _save(settings.copyWith(leadDays: leads));
                              },
                            ),
                          FilterChip(
                            label: const Text('Overdue nudge'),
                            selected: settings.overdueNudge,
                            onSelected: (value) =>
                                _save(settings.copyWith(overdueNudge: value)),
                          ),
                        ],
                      ),
                      SwitchListTile(
                        title: const Text('EMIs'),
                        value: settings.emis,
                        onChanged: (value) =>
                            _save(settings.copyWith(emis: value)),
                      ),
                      SwitchListTile(
                        title: const Text('Money'),
                        value: settings.money,
                        onChanged: (value) =>
                            _save(settings.copyWith(money: value)),
                      ),
                      SwitchListTile(
                        title: const Text('Subscriptions'),
                        value: settings.subscriptions,
                        onChanged: (value) =>
                            _save(settings.copyWith(subscriptions: value)),
                      ),
                      ListTile(
                        title: const Text('Notification permission'),
                        subtitle: Text(
                          _permissionGranted ? 'Allowed' : 'Not allowed',
                        ),
                        trailing: _permissionGranted
                            ? const Icon(Icons.check_circle_outline)
                            : TextButton(
                                onPressed: () async {
                                  await LocalReminderService()
                                      .openPermissionSettings();
                                  await _load();
                                },
                                child: const Text('Fix'),
                              ),
                      ),
                      ListTile(
                        title: const Text('Send test notification'),
                        leading: const Icon(
                          Icons.notifications_active_outlined,
                        ),
                        onTap: () async {
                          if (await LocalReminderService()
                              .permissionGranted()) {
                            await LocalReminderService().showTest();
                          } else if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Allow notifications first.'),
                              ),
                            );
                          }
                        },
                      ),
                      ListTile(
                        title: const Text('Reminders not arriving?'),
                        leading: const Icon(Icons.battery_alert_outlined),
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Battery settings'),
                            content: const Text(
                              'Allow unrestricted battery use and autostart for FinKeep. On Realme/Oppo and Xiaomi, check app battery and autostart settings. On Samsung, remove FinKeep from sleeping apps.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: const Text('Close'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(dialogContext);
                                  LocalReminderService().openBatterySettings();
                                },
                                child: const Text('Open settings'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: AsyncView(
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
                            dateOnly(item.dueAt).difference(today).inDays >=
                                2 &&
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
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
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
          ),
        ],
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
