import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/app_lock.dart';
import '../../core/providers.dart';
import '../../data/database.dart';

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
    final themeMode = ref.watch(appThemeModeProvider);
    final lockSettings =
        ref.watch(appLockSettingsProvider).valueOrNull ??
        const AppLockSettings();
    final biometricsSupported =
        ref.watch(_biometricsSupportedProvider).valueOrNull ?? false;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        if (widget.showHeading) ...[
          Text(
            'Settings',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 24),
        ],
        _SectionTitle('Privacy'),
        const SizedBox(height: 4),
        const Text(
          'Your data is stored only on this device. Uninstalling FinKeep or losing this device can permanently remove your records. Create a backup before changing devices.',
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.lock_outline),
          title: const Text('App lock'),
          subtitle: const Text('Require your PIN when you return to FinKeep'),
          value: lockSettings.enabled,
          onChanged: _busy ? null : _toggleLock,
        ),
        if (lockSettings.enabled && biometricsSupported)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Biometric unlock'),
            subtitle: const Text('Use an enrolled fingerprint or face unlock'),
            value: lockSettings.biometricEnabled,
            onChanged: _busy ? null : _toggleBiometrics,
          ),
        if (lockSettings.enabled && !biometricsSupported)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.fingerprint),
            title: Text('Biometrics unavailable'),
            subtitle: Text('PIN unlock remains available on this device.'),
          ),
        if (lockSettings.enabled)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.password_outlined),
            title: const Text('Change PIN'),
            onTap: _busy ? null : _changePin,
          ),
        const SizedBox(height: 20),
        _SectionTitle('Appearance'),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('System')),
            ButtonSegment(value: ThemeMode.light, label: Text('Light')),
            ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
          ],
          selected: {themeMode},
          onSelectionChanged: (value) =>
              ref.read(appThemeModeProvider.notifier).setMode(value.single),
        ),
        const SizedBox(height: 24),
        _SectionTitle('Data'),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: const Text('Export PDF report'),
          subtitle: const Text('Readable summaries for sharing or printing'),
          onTap: () => AppLockSession.instance.keepUnlocked(
            () => ref.read(pdfExportProvider).shareExport(),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.save_alt_outlined),
          title: const Text('Create local backup'),
          subtitle: const Text(
            'Saved on this device. No cloud account required.',
          ),
          onTap: _createBackup,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.restore_outlined),
          title: const Text('Restore from backup'),
          subtitle: const Text(
            'Replace device records from a FinKeep backup file',
          ),
          onTap: _restoreBackup,
        ),
        const SizedBox(height: 12),
        _SectionTitle('About'),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.info_outline),
          title: Text('FinKeep'),
          subtitle: Text(
            'Version 1.0.0 · Local-first personal finance tracker',
          ),
        ),
        const SizedBox(height: 20),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.delete_forever_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(
            'Clear all data',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          subtitle: const Text('Permanently remove all records and activity'),
          onTap: _confirmClearAll,
        ),
      ],
    );
  }

  Future<void> _toggleLock(bool enabled) async {
    setState(() => _busy = true);
    try {
      final db = ref.read(databaseProvider);
      if (enabled) {
        final pin = await showDialog<String>(
          context: context,
          builder: (_) => const _PinSetupDialog(),
        );
        if (pin == null) return;
        await _pinLock.setPin(pin);
        await _writeSetting(db, 'privacy.appLock.enabled', 'true');
        await _writeSetting(db, 'privacy.appLock.biometric', 'false');
      } else {
        final pin = await showDialog<String>(
          context: context,
          builder: (_) => const _PinConfirmDialog(),
        );
        if (pin == null) return;
        if (!await _pinLock.verifyPin(pin)) {
          _showMessage('The PIN was not correct. App lock remains on.');
          return;
        }
        await _writeSetting(db, 'privacy.appLock.enabled', 'false');
        await _writeSetting(db, 'privacy.appLock.biometric', 'false');
        await _pinLock.clearPin();
      }
      ref.invalidate(appLockSettingsProvider);
    } catch (error) {
      _showMessage('Could not update app lock: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleBiometrics(bool enabled) async {
    if (enabled) {
      try {
        final authenticated = await AppLockSession.instance.keepUnlocked(
          () => LocalAuthentication().authenticate(
            localizedReason: 'Confirm biometric unlock for FinKeep',
            biometricOnly: true,
          ),
        );
        if (!authenticated) return;
      } catch (_) {
        _showMessage('Biometric unlock is unavailable on this device.');
        return;
      }
    }
    await _writeSetting(
      ref.read(databaseProvider),
      'privacy.appLock.biometric',
      enabled ? 'true' : 'false',
    );
    ref.invalidate(appLockSettingsProvider);
  }

  Future<void> _createBackup() async {
    try {
      await AppLockSession.instance.keepUnlocked(
        () => ref.read(localBackupProvider).shareBackup(),
      );
    } catch (error) {
      _showMessage('Could not create the backup: $error');
    }
  }

  Future<void> _changePin() async {
    final current = await showDialog<String>(
      context: context,
      builder: (_) => const _PinConfirmDialog(),
    );
    if (current == null || !mounted) return;
    if (!await _pinLock.verifyPin(current)) {
      _showMessage('The PIN was not correct.');
      return;
    }
    if (!mounted) return;
    final replacement = await showDialog<String>(
      context: context,
      builder: (_) => const _PinSetupDialog(),
    );
    if (replacement == null) return;
    await _pinLock.setPin(replacement);
    _showMessage('PIN changed.');
  }

  Future<void> _restoreBackup() async {
    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace current data?'),
        content: const Text(
          'Restoring replaces the records and activity on this device with the selected backup. Export a backup first if you need the current data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose backup'),
          ),
        ],
      ),
    );
    if (replace != true) return;
    try {
      final restored = await AppLockSession.instance.keepUnlocked(
        () => ref.read(localBackupProvider).pickAndRestore(),
      );
      if (!restored) return;
      ref.invalidate(appLockSettingsProvider);
      _showMessage('Backup restored.');
    } on FormatException catch (error) {
      _showMessage(error.message.toString());
    } catch (error) {
      _showMessage('Could not restore that backup: $error');
    }
  }

  Future<void> _confirmClearAll() async {
    final typed = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Clear all data?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This permanently deletes your EMIs, payments, money records, repayments, subscriptions and activity. This cannot be undone.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: typed,
                decoration: const InputDecoration(
                  labelText: 'Type DELETE to confirm',
                ),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context, false);
                _createBackup();
              },
              icon: const Icon(Icons.save_alt_outlined),
              label: const Text('Create backup first'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: typed.text == 'DELETE'
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Clear all data'),
            ),
          ],
        ),
      ),
    );
    typed.dispose();
    if (ok == true) await ref.read(financeRepositoryProvider).clearAllData();
  }

  Future<void> _writeSetting(AppDatabase db, String key, String value) async {
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: value),
        );
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

final _biometricsSupportedProvider = FutureProvider<bool>((ref) async {
  final auth = LocalAuthentication();
  return supportsBiometricUnlock(
    deviceSupported: await auth.isDeviceSupported(),
    canCheckBiometrics: await auth.canCheckBiometrics,
    hasEnrolledBiometric: (await auth.getAvailableBiometrics()).isNotEmpty,
  );
});

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
  );
}

class _PinSetupDialog extends StatefulWidget {
  const _PinSetupDialog();

  @override
  State<_PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<_PinSetupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _showPin = false;
  bool _showConfirm = false;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Set a PIN'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Choose 4 to 6 digits. Your PIN is stored only as a salted hash in secure device storage.',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _pin,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            obscureText: !_showPin,
            maxLength: 6,
            decoration: InputDecoration(
              labelText: 'PIN',
              counterText: '',
              suffixIcon: IconButton(
                tooltip: _showPin ? 'Hide PIN' : 'Show PIN',
                onPressed: () => setState(() => _showPin = !_showPin),
                icon: Icon(_showPin ? Icons.visibility_off : Icons.visibility),
              ),
            ),
            validator: (value) =>
                value != null && RegExp(r'^\d{4,6}$').hasMatch(value)
                ? null
                : 'Enter 4 to 6 digits',
          ),
          TextFormField(
            controller: _confirm,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            obscureText: !_showConfirm,
            maxLength: 6,
            decoration: InputDecoration(
              labelText: 'Confirm PIN',
              counterText: '',
              suffixIcon: IconButton(
                tooltip: _showConfirm ? 'Hide PIN' : 'Show PIN',
                onPressed: () => setState(() => _showConfirm = !_showConfirm),
                icon: Icon(
                  _showConfirm ? Icons.visibility_off : Icons.visibility,
                ),
              ),
            ),
            validator: (value) =>
                value == _pin.text ? null : 'PINs do not match',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_formKey.currentState!.validate()) {
            Navigator.pop(context, _pin.text);
          }
        },
        child: const Text('Enable lock'),
      ),
    ],
  );
}

class _PinConfirmDialog extends StatefulWidget {
  const _PinConfirmDialog();

  @override
  State<_PinConfirmDialog> createState() => _PinConfirmDialogState();
}

class _PinConfirmDialogState extends State<_PinConfirmDialog> {
  final _pin = TextEditingController();
  bool _showPin = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Confirm your PIN'),
    content: TextField(
      controller: _pin,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      obscureText: !_showPin,
      maxLength: 6,
      decoration: InputDecoration(
        labelText: 'PIN',
        counterText: '',
        suffixIcon: IconButton(
          tooltip: _showPin ? 'Hide PIN' : 'Show PIN',
          onPressed: () => setState(() => _showPin = !_showPin),
          icon: Icon(_showPin ? Icons.visibility_off : Icons.visibility),
        ),
      ),
      onSubmitted: (_) => Navigator.pop(context, _pin.text),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _pin.text),
        child: const Text('Continue'),
      ),
    ],
  );
}
