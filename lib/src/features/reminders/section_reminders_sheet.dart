import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications.dart';
import '../../core/providers.dart';
import '../../domain/reminder_schedule.dart';
import '../../shared/finance_bottom_sheet.dart';

class SectionReminderButton extends ConsumerStatefulWidget {
  const SectionReminderButton({super.key, required this.type});

  final FinanceReminderType type;

  @override
  ConsumerState<SectionReminderButton> createState() =>
      _SectionReminderButtonState();
}

class _SectionReminderButtonState extends ConsumerState<SectionReminderButton> {
  late Future<ReminderPlanSettings> _settings = _load();

  Future<ReminderPlanSettings> _load() =>
      ref.read(financeRepositoryProvider).reminderSettingsFor(widget.type);

  @override
  Widget build(BuildContext context) => FutureBuilder<ReminderPlanSettings>(
    future: _settings,
    builder: (context, snapshot) => SizedBox.square(
      dimension: 44,
      child: IconButton(
        tooltip: '${_label(widget.type)} reminders',
        onPressed: () {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            await showFinanceBottomSheet<void>(
              context,
              builder: (_) => _SectionReminderSheet(type: widget.type),
            );
            if (mounted) setState(() => _settings = _load());
          });
        },
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.notifications_outlined),
            if (snapshot.data?.enabled == true)
              Positioned(
                top: 0,
                right: 0,
                child: CircleAvatar(
                  radius: 3,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

String _label(FinanceReminderType type) => switch (type) {
  FinanceReminderType.emi => 'EMI',
  FinanceReminderType.money => 'Money',
  FinanceReminderType.subscription => 'Subscription',
};

class _SectionReminderSheet extends ConsumerStatefulWidget {
  const _SectionReminderSheet({required this.type});
  final FinanceReminderType type;

  @override
  ConsumerState<_SectionReminderSheet> createState() =>
      _SectionReminderSheetState();
}

class _SectionReminderSheetState extends ConsumerState<_SectionReminderSheet> {
  ReminderPlanSettings? _settings;
  bool _keepBalance = true;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repository = ref.read(financeRepositoryProvider);
    final value = await repository.reminderSettingsFor(widget.type);
    final keepBalance = widget.type == FinanceReminderType.emi
        ? await repository.emiKeepBalanceEnabled()
        : true;
    if (mounted) {
      setState(() {
        _settings = value;
        _keepBalance = keepBalance;
      });
    }
  }

  Future<void> _saveKeepBalance(bool value) async {
    await ref.read(financeRepositoryProvider).saveEmiKeepBalanceEnabled(value);
    if (mounted) setState(() => _keepBalance = value);
  }

  Future<void> _save(ReminderPlanSettings next) async {
    if (next.enabled && _settings?.enabled != true) {
      final allowed = await LocalReminderService().requestPermission();
      if (!allowed) {
        if (mounted) setState(() => _denied = true);
        return;
      }
    }
    await ref
        .read(financeRepositoryProvider)
        .saveReminderSettingsFor(widget.type, next);
    if (mounted) {
      setState(() {
        _settings = next;
        _denied = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.75,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              '${_label(widget.type)} reminders',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (settings == null)
              const Center(child: CircularProgressIndicator())
            else ...[
              SwitchListTile(
                title: const Text('Reminders'),
                value: settings.enabled,
                onChanged: (value) => _save(settings.copyWith(enabled: value)),
              ),
              if (widget.type == FinanceReminderType.emi)
                SwitchListTile(
                  title: const Text('Keep-balance reminder'),
                  subtitle: const Text(
                    '6 PM the day before an auto-debit, grouped by lender',
                  ),
                  value: _keepBalance,
                  onChanged: settings.enabled ? _saveKeepBalance : null,
                ),
              if (_denied)
                ListTile(
                  title: const Text('Notification permission is off'),
                  trailing: TextButton(
                    onPressed: () =>
                        LocalReminderService().openPermissionSettings(),
                    child: const Text('Open settings'),
                  ),
                ),
              const SizedBox(height: 12),
              Text('Time', style: Theme.of(context).textTheme.titleSmall),
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
                      selected: settings.hour == hour && settings.minute == 0,
                      onSelected: (_) =>
                          _save(settings.copyWith(hour: hour, minute: 0)),
                    ),
                  ActionChip(
                    label: const Text('Custom'),
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
              const SizedBox(height: 14),
              Text('Remind me', style: Theme.of(context).textTheme.titleSmall),
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
                      onSelected: (selected) {
                        final leads = {...settings.leadDays};
                        selected ? leads.add(days) : leads.remove(days);
                        _save(settings.copyWith(leadDays: leads));
                      },
                    ),
                  if (widget.type != FinanceReminderType.subscription)
                    FilterChip(
                      label: const Text('Overdue nudge'),
                      selected: settings.overdueNudge,
                      onSelected: (value) =>
                          _save(settings.copyWith(overdueNudge: value)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('Send test notification'),
                onTap: () async {
                  if (await LocalReminderService().permissionGranted()) {
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
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.battery_alert_outlined),
                title: const Text('Not arriving? Battery tips'),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: const Text('Battery settings'),
                    content: const Text(
                      'Allow unrestricted battery use and autostart for FinKeep. On Realme/Oppo and Xiaomi, check app battery and autostart settings. On Samsung, remove FinKeep from sleeping apps.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialog),
                        child: const Text('Close'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(dialog);
                          LocalReminderService().openBatterySettings();
                        },
                        child: const Text('Open settings'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
