import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications.dart';
import '../../core/app_theme.dart';
import '../../core/providers.dart';
import '../../domain/reminder_schedule.dart';
import '../../shared/finance_bottom_sheet.dart';

class SectionReminderButton extends ConsumerStatefulWidget {
  const SectionReminderButton({
    super.key,
    required this.type,
    this.dotColor,
    this.dotBorderColor,
  });

  final FinanceReminderType type;
  final Color? dotColor;
  final Color? dotBorderColor;

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
        onPressed: () async {
          if (widget.type == FinanceReminderType.emi) {
            await showDialog<void>(
              context: context,
              builder: (dialog) => Dialog(
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: _SectionReminderSheet(type: widget.type),
              ),
            );
          } else {
            await showFinanceBottomSheet<void>(
              context,
              builder: (_) => _SectionReminderSheet(type: widget.type),
            );
          }
          if (mounted) setState(() => _settings = _load());
        },
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.notifications_outlined),
            if (widget.type != FinanceReminderType.emi &&
                snapshot.data?.enabled == true)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        widget.dotColor ??
                        Theme.of(context).colorScheme.primary,
                    border: widget.dotBorderColor == null
                        ? null
                        : Border.all(color: widget.dotBorderColor!, width: 2),
                  ),
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
  bool _leadExpanded = false;

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

  void _showBatteryTips(BuildContext context) => showDialog<void>(
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
  );

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (widget.type == FinanceReminderType.emi) {
      final colors = AppTheme.homePaletteOf(context);
      final theme = Theme.of(context);
      final neutralTheme = AppTheme.neutralControlTheme(context);
      return Theme(
        data: neutralTheme,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .66,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: colors.surfaceAlt,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          Icons.notifications_outlined,
                          color: colors.text,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'EMI reminders',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: colors.text,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Stay ahead of each installment',
                              style: TextStyle(
                                color: colors.text2,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (settings == null)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    _ReminderSettingRow(
                      title: 'Payment reminders',
                      subtitle: 'Notify me before an installment is due',
                      value: settings.enabled,
                      onChanged: (value) =>
                          _save(settings.copyWith(enabled: value)),
                    ),
                    const Divider(height: 1),
                    _ReminderSettingRow(
                      title: 'Auto-debit balance check',
                      subtitle: '6 PM the day before, grouped by lender',
                      value: _keepBalance,
                      onChanged: settings.enabled ? _saveKeepBalance : null,
                    ),
                    if (_denied)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: ListTile(
                          tileColor: colors.surfaceAlt,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          title: const Text('Notifications are turned off'),
                          subtitle: const Text(
                            'Allow access in Android settings',
                          ),
                          trailing: TextButton(
                            onPressed: () =>
                                LocalReminderService().openPermissionSettings(),
                            child: const Text('Fix'),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Text(
                      'When to notify',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Choose a time that works for you',
                      style: TextStyle(color: colors.text2, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
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
                            selectedColor: colors.text,
                            backgroundColor: colors.surfaceAlt,
                            showCheckmark: false,
                            side: BorderSide.none,
                            labelStyle: TextStyle(
                              color:
                                  settings.hour == hour && settings.minute == 0
                                  ? colors.bg
                                  : colors.text,
                            ),
                            onSelected: (_) =>
                                _save(settings.copyWith(hour: hour, minute: 0)),
                          ),
                        ActionChip(
                          backgroundColor: colors.surfaceAlt,
                          side: BorderSide.none,
                          labelStyle: TextStyle(color: colors.text),
                          label: Text(
                            settings.minute != 0 ||
                                    ![8, 9, 18].contains(settings.hour)
                                ? TimeOfDay(
                                    hour: settings.hour,
                                    minute: settings.minute,
                                  ).format(context)
                                : 'Custom',
                          ),
                          onPressed: () async {
                            final time = await showTimePicker(
                              context: context,
                              builder: (_, child) =>
                                  Theme(data: neutralTheme, child: child!),
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
                    const SizedBox(height: 10),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        'Lead time',
                        style: TextStyle(
                          color: colors.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        [
                          for (final days in [7, 3, 1, 0])
                            if (settings.leadDays.contains(days))
                              days == 0 ? 'Due day' : '$days days before',
                          if (settings.overdueNudge) 'Overdue nudge',
                        ].join(' · '),
                        maxLines: 2,
                        style: TextStyle(color: colors.text2, fontSize: 12),
                      ),
                      trailing: Icon(
                        _leadExpanded ? Icons.expand_less : Icons.expand_more,
                        color: colors.text,
                      ),
                      onTap: () =>
                          setState(() => _leadExpanded = !_leadExpanded),
                    ),
                    if (_leadExpanded) ...[
                      for (final options in [
                        [('7 days before', 7), ('3 days before', 3)],
                        [('1 day before', 1), ('Due day', 0)],
                      ])
                        Row(
                          children: [
                            for (final (label, days) in options)
                              Expanded(
                                child: _ReminderChoice(
                                  label: label,
                                  selected: settings.leadDays.contains(days),
                                  color: colors.text,
                                  onTap: () {
                                    final leads = {...settings.leadDays};
                                    leads.contains(days)
                                        ? leads.remove(days)
                                        : leads.add(days);
                                    _save(settings.copyWith(leadDays: leads));
                                  },
                                ),
                              ),
                          ],
                        ),
                      _ReminderChoice(
                        label: 'Overdue nudge',
                        selected: settings.overdueNudge,
                        color: colors.text,
                        onTap: () => _save(
                          settings.copyWith(
                            overdueNudge: !settings.overdueNudge,
                          ),
                        ),
                      ),
                    ],
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.notifications_active_outlined,
                        color: colors.text,
                      ),
                      title: Text(
                        'Send test reminder',
                        style: TextStyle(
                          color: colors.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      trailing: Icon(Icons.chevron_right, color: colors.text2),
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
                      leading: Icon(
                        Icons.battery_charging_full_outlined,
                        color: colors.text,
                      ),
                      title: Text(
                        'Reminders not arriving?',
                        style: TextStyle(
                          color: colors.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        'Check battery and autostart settings',
                        style: TextStyle(color: colors.text2),
                      ),
                      trailing: Icon(Icons.chevron_right, color: colors.text2),
                      onTap: () => _showBatteryTips(context),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }
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
                onTap: () => _showBatteryTips(context),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReminderSettingRow extends StatelessWidget {
  const _ReminderSettingRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.homePaletteOf(context);
    return SwitchListTile.adaptive(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: TextStyle(
          color: colors.text,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: colors.text2, fontSize: 12),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _ReminderChoice extends StatelessWidget {
  const _ReminderChoice({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    toggled: selected,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank,
              size: 20,
              color: color,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
