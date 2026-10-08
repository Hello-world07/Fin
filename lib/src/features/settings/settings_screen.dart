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
import '../reminders/reminders_screen.dart';
import 'backup_settings_section.dart';
import 'settings_widgets.dart';

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
    final themeMode = ref.watch(appThemeModeProvider);
    final indian = ref.watch(numberGroupingProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 48),
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

        const SettingsSectionHeader('Appearance'),
        Row(
          children: [
            for (final mode in ThemeMode.values)
              Expanded(
                child: _ThemePreview(
                  mode: mode,
                  selected: themeMode == mode,
                  onTap: () =>
                      ref.read(appThemeModeProvider.notifier).setMode(mode),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
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

        const SettingsSectionHeader('Deleted'),
        SettingsRow(
          icon: Icons.delete_outline,
          title: 'Recycle bin',
          subtitle:
              '${counts?.deleted ?? 0} archived ${counts?.deleted == 1 ? 'EMI' : 'EMIs'}',
          onTap: _showDeleted,
        ),

        const SettingsSectionHeader('About'),
        SettingsRow(
          icon: Icons.info_outline,
          title: 'FinKeep',
          subtitle: 'Local-first personal finance',
          onTap: _showAbout,
        ),

        const SizedBox(height: 30),
        SettingsRow(
          icon: Icons.delete_forever_outlined,
          title: 'Clear all data',
          subtitle: 'Permanently remove records and deleted EMIs',
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
    if (age < const Duration(days: 7)) return AppTheme.receive;
    if (age < const Duration(days: 30)) return AppTheme.emi;
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
    await LockDisplayService.setSecure(enabled);
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
    final typed = TextEditingController();
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
                'This permanently removes EMIs, payments, money records, subscriptions, activity and deleted EMIs.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: typed,
                decoration: const InputDecoration(
                  labelText: 'Type DELETE to confirm',
                  filled: true,
                  border: InputBorder.none,
                ),
                onChanged: (_) => setDialogState(() {}),
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
              onPressed: typed.text == 'DELETE'
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
    typed.dispose();
    if (choice == 'backup' && mounted) {
      await Future<void>.delayed(AppTheme.motionDuration);
      if (mounted) await _backUpNow();
    } else if (choice == 'clear') {
      await _run(() => ref.read(financeRepositoryProvider).clearAllData());
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

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({
    required this.mode,
    required this.selected,
    required this.onTap,
  });
  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark =
        mode == ThemeMode.dark ||
        (mode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    final background = dark ? AppTheme.darkBackground : AppTheme.pageBackground;
    final ink = dark ? AppTheme.onHero : AppTheme.primaryText;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          children: [
            Container(
              height: 116,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(8),
                border: selected
                    ? Border.all(color: scheme.primary, width: 2)
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 5,
                    width: 22,
                    decoration: BoxDecoration(
                      color: ink,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 30,
                    decoration: BoxDecoration(
                      color: dark ? AppTheme.heroEnd : AppTheme.selectedFill,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 5,
                    width: 54,
                    color: ink.withValues(alpha: 0.45),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    height: 5,
                    width: 38,
                    color: ink.withValues(alpha: 0.25),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              mode.name[0].toUpperCase() + mode.name.substring(1),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? scheme.primary : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
