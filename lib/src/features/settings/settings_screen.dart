import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/app_lock.dart';
import '../../core/app_lock_policy.dart';
import '../../core/app_theme.dart';
import '../../core/providers.dart';
import '../../core/pin_keypad.dart';
import '../../data/database.dart';
import '../../data/repositories.dart';
import '../../app.dart';
import '../reminders/reminders_screen.dart';
import '../activity/activity_screen.dart';
import '../onboarding/intro_screen.dart';
import 'backup_settings_section.dart';
import 'privacy_data_screen.dart';
import 'settings_widgets.dart';

void openSettings(BuildContext context) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const SafeArea(child: SettingsScreen(showHeading: false)),
    ),
  ),
);

class _SettingsCounts {
  const _SettingsCounts(
    this.emis,
    this.money,
    this.subscriptions,
    this.deleted,
  );
  final int emis;
  final int money;
  final int subscriptions;
  final int deleted;
}

final _settingsCountsProvider = StreamProvider<_SettingsCounts>((ref) {
  final db = ref.watch(databaseProvider);
  return db
      .customSelect(
        "SELECT (SELECT COUNT(*) FROM emis) AS emis, "
        "(SELECT COUNT(*) FROM money_records) AS money, "
        "(SELECT COUNT(*) FROM subscriptions) AS subscriptions, "
        "(SELECT COUNT(*) FROM settings WHERE (key LIKE 'emi.archived.%' OR key LIKE 'money.archived.%' OR key LIKE 'subscription.archived.%') AND value = 'true') AS deleted",
        readsFrom: {db.emis, db.moneyRecords, db.subscriptions, db.settings},
      )
      .watchSingle()
      .map(
        (row) => _SettingsCounts(
          row.read<int>('emis'),
          row.read<int>('money'),
          row.read<int>('subscriptions'),
          row.read<int>('deleted'),
        ),
      );
});

final _biometricsSupportedProvider = FutureProvider<bool>((ref) async {
  final auth = LocalAuthentication();
  return supportsBiometricUnlock(
    deviceSupported: await auth.isDeviceSupported(),
    canCheckBiometrics: await auth.canCheckBiometrics,
    hasEnrolledBiometric: (await auth.getAvailableBiometrics()).isNotEmpty,
  );
});

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.showHeading = true});
  final bool showHeading;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _pinLock = PinLockService();
  bool _busy = false;
  late Future<({bool enabled, int hour, int minute})> _dailyBrief;

  @override
  void initState() {
    super.initState();
    _dailyBrief = ref.read(financeRepositoryProvider).dailyBriefSettings();
  }

  Future<void> _setDailyBrief({bool? enabled, TimeOfDay? time}) async {
    final current = await _dailyBrief;
    await ref
        .read(financeRepositoryProvider)
        .setDailyBrief(
          enabled: enabled ?? current.enabled,
          hour: time?.hour ?? current.hour,
          minute: time?.minute ?? current.minute,
        );
    if (mounted) {
      setState(
        () => _dailyBrief = ref
            .read(financeRepositoryProvider)
            .dailyBriefSettings(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final counts = ref.watch(_settingsCountsProvider).valueOrNull;
    final backup = ref.watch(backupStatusProvider).valueOrNull;
    final lock =
        ref.watch(appLockSettingsProvider).valueOrNull ??
        const AppLockSettings();
    final biometricsAvailable =
        ref.watch(_biometricsSupportedProvider).valueOrNull ?? false;
    final indian = ref.watch(numberGroupingProvider);
    final privacy = ref.watch(privacyModeProvider);
    final appearance = ref.watch(appThemeModeProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
      children: [
        if (widget.showHeading)
          Text(
            'Settings',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        if (widget.showHeading) const SizedBox(height: 20),
        Text(
          'DATA HEALTH',
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _backupColor(backup?.lastAt),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _backupText(backup?.lastAt),
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            _CountFigure(counts?.emis, 'EMIs'),
            _CountFigure(counts?.money, 'Money'),
            _CountFigure(counts?.subscriptions, 'Subscriptions'),
          ],
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _busy ? null : _backUpNow,
            icon: const Icon(Icons.backup_outlined),
            label: const Text('Back up now'),
          ),
        ),

        const SettingsSectionHeader('Security'),
        SettingsRow(
          icon: Icons.lock_outline,
          title: 'App lock',
          subtitle: lock.enabled ? 'PIN required to open FinKeep' : 'Off',
          trailing: Switch.adaptive(
            value: lock.enabled,
            onChanged: _busy ? null : _toggleLock,
          ),
        ),
        if (lock.enabled) ...[
          SettingsRow(
            icon: Icons.timer_outlined,
            title: 'Auto-lock delay',
            subtitle: 'After leaving FinKeep',
            trailing: PopupMenuButton<AutoLockDelay>(
              tooltip: 'Auto-lock delay',
              initialValue: lock.delay,
              onSelected: (value) =>
                  _setLockOption('privacy.appLock.delay', value.name),
              itemBuilder: (_) => AutoLockDelay.values
                  .map(
                    (value) =>
                        PopupMenuItem(value: value, child: Text(value.label)),
                  )
                  .toList(),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(lock.delay.label),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
          ),
          SettingsRow(
            icon: Icons.fingerprint,
            title: 'Unlock with fingerprint / face',
            subtitle: biometricsAvailable
                ? 'Use enrolled biometrics'
                : 'No enrolled biometrics available',
            trailing: Switch.adaptive(
              value: lock.biometricEnabled && biometricsAvailable,
              onChanged: _busy || !biometricsAvailable
                  ? null
                  : _toggleBiometrics,
            ),
          ),
          if (lock.biometricEnabled && biometricsAvailable)
            SettingsRow(
              icon: Icons.touch_app_outlined,
              title: 'Ask for fingerprint automatically',
              subtitle: 'Off by default; PIN remains available',
              trailing: Switch.adaptive(
                value: lock.autoBiometric,
                onChanged: (value) => _setLockOption(
                  'privacy.appLock.autoBiometric',
                  value.toString(),
                ),
              ),
            ),
          SettingsRow(
            icon: Icons.password_outlined,
            title: 'Change PIN',
            onTap: _busy ? null : _changePin,
          ),
          SettingsRow(
            icon: Icons.visibility_off_outlined,
            title: 'Hide in recent apps and block screenshots',
            subtitle: 'Protect sensitive content on Android',
            trailing: Switch.adaptive(
              value: lock.secureScreen,
              onChanged: _toggleSecureScreen,
            ),
          ),
        ],
        SettingsRow(
          icon: Icons.visibility_off_outlined,
          title: 'Privacy mode',
          subtitle: 'Hide amounts throughout FinKeep',
          trailing: Switch.adaptive(
            value: privacy.enabled,
            onChanged: (value) => ref
                .read(privacyModeProvider.notifier)
                .setEnabled(value, context: context),
          ),
        ),
        SettingsRow(
          icon: Icons.lock_clock_outlined,
          title: 'Hide amounts when the app opens',
          trailing: Switch.adaptive(
            value: privacy.hideOnOpen,
            onChanged: (value) =>
                ref.read(privacyModeProvider.notifier).setHideOnOpen(value),
          ),
        ),
        SettingsRow(
          icon: Icons.verified_user_outlined,
          title: 'Require unlock to reveal amounts',
          subtitle: 'PIN or fingerprint / face · 30-second grace',
          trailing: Switch.adaptive(
            value: privacy.requireUnlock,
            onChanged: (value) => ref
                .read(privacyModeProvider.notifier)
                .setRequireUnlock(value, context),
          ),
        ),

        const SettingsSectionHeader('Backup & data'),
        const BackupSettingsSection(),
        SettingsRow(
          icon: Icons.picture_as_pdf_outlined,
          title: 'Export PDF report',
          onTap: () => _run(
            () => AppLockSession.instance.keepUnlocked(
              () => ref.read(pdfExportProvider).shareExport(),
            ),
          ),
        ),
        SettingsRow(
          icon: Icons.table_view_outlined,
          title: 'Export CSV',
          subtitle: 'Separate EMI, Money and Subscription files',
          onTap: () => _run(
            () => AppLockSession.instance.keepUnlocked(
              () => ref.read(csvExportProvider).shareExport(),
            ),
          ),
        ),

        SettingsRow(
          icon: Icons.numbers_outlined,
          title: 'Number format',
          subtitle: indian
              ? 'Indian grouping · ₹1,00,000'
              : 'International grouping · ₹100,000',
          trailing: PopupMenuButton<bool>(
            tooltip: 'Number format',
            initialValue: indian,
            onSelected: (value) => _run(
              () => ref.read(numberGroupingProvider.notifier).setIndian(value),
            ),
            itemBuilder: (_) => const [
              PopupMenuItem(value: true, child: Text('Indian · ₹1,00,000')),
              PopupMenuItem(
                value: false,
                child: Text('International · ₹100,000'),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.arrow_drop_down),
            ),
          ),
        ),

        const SettingsSectionHeader('Appearance'),
        Row(
          children: [
            for (final mode in ThemeMode.values) ...[
              if (mode != ThemeMode.system) const SizedBox(width: 10),
              Expanded(
                child: _AppearanceTile(
                  mode: mode,
                  selected: appearance == mode,
                  onTap: () =>
                      ref.read(appThemeModeProvider.notifier).setMode(mode),
                ),
              ),
            ],
          ],
        ),

        const SettingsSectionHeader('Notifications'),
        SettingsRow(
          icon: Icons.notifications_outlined,
          title: 'Reminders',
          subtitle: 'Upcoming payments and renewals',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const RemindersScreen()),
          ),
        ),
        FutureBuilder<({bool enabled, int hour, int minute})>(
          future: _dailyBrief,
          builder: (context, snapshot) {
            final setting = snapshot.data;
            return SettingsRow(
              icon: Icons.wb_sunny_outlined,
              title: 'Morning brief',
              subtitle: setting == null
                  ? 'Loading'
                  : 'Daily at ${TimeOfDay(hour: setting.hour, minute: setting.minute).format(context)}',
              trailing: Switch(
                value: setting?.enabled ?? false,
                onChanged: setting == null
                    ? null
                    : (value) => _setDailyBrief(enabled: value),
              ),
              onTap: setting == null
                  ? null
                  : () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(
                          hour: setting.hour,
                          minute: setting.minute,
                        ),
                      );
                      if (picked != null && mounted) {
                        await _setDailyBrief(time: picked);
                      }
                    },
            );
          },
        ),
        SettingsRow(
          icon: Icons.history,
          title: 'Activity history',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ActivityScreen()),
          ),
        ),

        const SettingsSectionHeader('Deleted'),
        SettingsRow(
          icon: Icons.delete_outline,
          title: 'Recycle bin',
          subtitle:
              '${counts?.deleted ?? 0} deleted ${counts?.deleted == 1 ? 'item' : 'items'}',
          onTap: _showDeleted,
        ),

        const SettingsSectionHeader('About'),
        SettingsRow(
          icon: Icons.info_outline,
          title: 'FinKeep',
          subtitle: 'Local-first personal finance',
          onTap: _showAbout,
        ),
        SettingsRow(
          icon: Icons.slideshow_outlined,
          title: 'Replay intro',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const IntroScreen(replay: true),
            ),
          ),
        ),
        SettingsRow(
          icon: Icons.privacy_tip_outlined,
          title: 'Privacy & data',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const PrivacyDataScreen()),
          ),
        ),

        const SizedBox(height: 30),
        SettingsRow(
          icon: Icons.delete_forever_outlined,
          title: 'Clear all data',
          subtitle: 'Permanently remove records and deleted items',
          destructive: true,
          onTap: _confirmClearAll,
        ),
      ],
    );
  }

  Color _backupColor(DateTime? lastAt) {
    final scheme = Theme.of(context).colorScheme;
    if (lastAt == null) return scheme.error;
    final age = DateTime.now().difference(lastAt);
    if (age < const Duration(days: 7)) {
      return AppTheme.colorsOf(context).receive;
    }
    if (age < const Duration(days: 30)) return AppTheme.colorsOf(context).emi;
    return scheme.error;
  }

  String _backupText(DateTime? lastAt) => lastAt == null
      ? 'Never backed up'
      : 'Last backup ${DateFormat('d MMM y, h:mm a').format(lastAt.toLocal())}';

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      _message('Could not complete the action: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backUpNow() => _run(() => showCreateBackupFlow(context, ref));

  Future<bool> _verifyCurrentPin(String title) async =>
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => PinVerifyScreen(title: title)),
      ) ==
      true;

  Future<void> _toggleLock(bool enabled) => _run(() async {
    final db = ref.read(databaseProvider);
    if (enabled) {
      final pin = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const PinSetupScreen()),
      );
      if (pin == null) return;
      await _pinLock.setPin(pin);
      await _writeSetting(db, 'privacy.appLock.enabled', 'true');
      await _writeSetting(db, 'privacy.appLock.biometric', 'false');
    } else {
      if (!await _verifyCurrentPin('Turn off app lock')) return;
      await _writeSetting(db, 'privacy.appLock.enabled', 'false');
      await _writeSetting(db, 'privacy.appLock.biometric', 'false');
      await _pinLock.clearPin();
    }
    ref.invalidate(appLockSettingsProvider);
  });

  Future<void> _toggleBiometrics(bool enabled) => _run(() async {
    if (enabled) {
      final ok = await AppLockSession.instance.keepUnlocked(
        () => LocalAuthentication().authenticate(
          localizedReason: 'Confirm biometric unlock for FinKeep',
          biometricOnly: true,
        ),
      );
      if (!ok) return;
    }
    await _writeSetting(
      ref.read(databaseProvider),
      'privacy.appLock.biometric',
      enabled.toString(),
    );
    if (!enabled) {
      await _writeSetting(
        ref.read(databaseProvider),
        'privacy.appLock.autoBiometric',
        'false',
      );
    }
    ref.invalidate(appLockSettingsProvider);
  });

  Future<void> _toggleSecureScreen(bool enabled) => _run(() async {
    await LockDisplayService.setSecure(
      enabled || ref.read(privacyModeProvider).enabled,
    );
    await _writeSetting(
      ref.read(databaseProvider),
      'privacy.appLock.secureScreen',
      enabled.toString(),
    );
    ref.invalidate(appLockSettingsProvider);
  });

  Future<void> _setLockOption(String key, String value) => _run(() async {
    await _writeSetting(ref.read(databaseProvider), key, value);
    ref.invalidate(appLockSettingsProvider);
  });

  Future<void> _changePin() => _run(() async {
    if (!await _verifyCurrentPin('Change PIN')) return;
    if (!mounted) return;
    final pin = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const PinSetupScreen()),
    );
    if (pin == null) return;
    await _pinLock.setPin(pin);
    _message('PIN changed.');
  });

  Future<void> _showDeleted() async {
    final db = ref.read(databaseProvider);
    final rows = await db
        .customSelect(
          "SELECT 'emi' AS kind, emis.id, emis.name, emis.updated_at AS changed_at FROM emis JOIN settings ON settings.key = 'emi.archived.' || emis.id WHERE settings.value = 'true' "
          "UNION ALL SELECT 'money', money_records.id, money_records.person_name, money_records.updated_at FROM money_records JOIN settings ON settings.key = 'money.archived.' || money_records.id WHERE settings.value = 'true' "
          "UNION ALL SELECT 'subscription', subscriptions.id, subscriptions.name, subscriptions.updated_at FROM subscriptions JOIN settings ON settings.key = 'subscription.archived.' || subscriptions.id WHERE settings.value = 'true' ORDER BY changed_at DESC",
        )
        .get();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recycle bin',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Deleted EMIs, Money records and Subscriptions can be restored.',
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView.builder(
                    itemCount: rows.isEmpty ? 1 : rows.length,
                    itemBuilder: (context, index) {
                      if (rows.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text('Nothing in Deleted')),
                        );
                      }
                      final row = rows[index];
                      final kind = row.read<String>('kind');
                      return SettingsRow(
                        icon: switch (kind) {
                          'money' => Icons.swap_horiz,
                          'subscription' => Icons.autorenew,
                          _ => Icons.account_balance_outlined,
                        },
                        title: row.read<String>('name'),
                        subtitle: switch (kind) {
                          'money' => 'Money record',
                          'subscription' => 'Subscription',
                          _ => 'EMI',
                        },
                        trailing: TextButton(
                          onPressed: () async {
                            final repo = ref.read(financeRepositoryProvider);
                            final id = row.read<int>('id');
                            switch (kind) {
                              case 'money':
                                await repo.restoreMoneyRecord(id);
                              case 'subscription':
                                await repo.restoreSubscriptionById(id);
                              default:
                                await repo.restoreEmi(id);
                            }
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                            _message('${row.read<String>('name')} restored.');
                          },
                          child: const Text('Restore'),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAbout() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    showAboutDialog(
      context: context,
      applicationName: 'FinKeep',
      applicationVersion: '${info.version}+${info.buildNumber}',
    );
  }

  Future<void> _confirmClearAll() async {
    var confirmation = '';
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Clear all data?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This permanently removes EMIs, money records, subscriptions, activity and deleted items.',
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Type DELETE to confirm',
                  filled: true,
                  border: InputBorder.none,
                ),
                onChanged: (value) =>
                    setDialogState(() => confirmation = value),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 'backup'),
              icon: const Icon(Icons.backup_outlined),
              label: const Text('Back up first'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: confirmation == 'DELETE'
                  ? () => Navigator.pop(dialogContext, 'clear')
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Clear data'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'backup' && mounted) {
      await Future<void>.delayed(AppTheme.motionDuration);
      if (mounted) await _backUpNow();
    } else if (choice == 'clear') {
      final repository = ref.read(financeRepositoryProvider);
      final previousRouteClosed = ModalRoute.of(
        context,
      )?.completed.then((_) {});
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => _ClearingScreen(
            repository: repository,
            previousRouteClosed: previousRouteClosed,
          ),
        ),
        (_) => false,
      );
    }
  }

  Future<void> _writeSetting(AppDatabase db, String key, String value) => db
      .into(db.settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }
}

class _AppearanceTile extends StatelessWidget {
  const _AppearanceTile({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final current = Theme.of(context).colorScheme;
    final preview = mode == ThemeMode.dark
        ? AppTheme.darkColors
        : AppTheme.lightColors;
    final ring = current.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          children: [
            Container(
              height: 82,
              width: 54,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: preview.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? ring : current.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 7,
                    width: 28,
                    decoration: BoxDecoration(
                      color: preview.text,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: preview.surface,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        if (mode == ThemeMode.system) ...[
                          const SizedBox(width: 2),
                          Expanded(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppTheme.darkColors.surface,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    height: 5,
                    width: 35,
                    decoration: BoxDecoration(
                      color: mode == ThemeMode.system
                          ? AppTheme.darkColors.receive
                          : preview.receive,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Text(
              switch (mode) {
                ThemeMode.system => 'System',
                ThemeMode.light => 'Light',
                ThemeMode.dark => 'Dark',
              },
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? ring : current.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountFigure extends StatelessWidget {
  const _CountFigure(this.count, this.label);
  final int? count;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${count ?? '–'}',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class _ClearingScreen extends ConsumerStatefulWidget {
  const _ClearingScreen({
    required this.repository,
    required this.previousRouteClosed,
  });

  final FinanceRepository repository;
  final Future<void>? previousRouteClosed;

  @override
  ConsumerState<_ClearingScreen> createState() => _ClearingScreenState();
}

class _ClearingScreenState extends ConsumerState<_ClearingScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _clear());
  }

  Future<void> _clear() async {
    try {
      await widget.previousRouteClosed;
      if (!mounted) return;
      await widget.repository.clearAllData();
      if (!mounted) return;
      final container = ProviderScope.containerOf(context, listen: false);
      ref.read(shellIndexProvider.notifier).state = 0;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const AppShell()),
        (_) => false,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        container.invalidate(dashboardProvider);
        container.invalidate(emisProvider);
        container.invalidate(moneyRecordsProvider);
        container.invalidate(subscriptionsProvider);
        container.invalidate(activityProvider);
        container.invalidate(dashboardActivityProvider);
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: _error == null
          ? const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Clearing...'),
              ],
            )
          : Text('Could not clear data: $_error'),
    ),
  );
}
