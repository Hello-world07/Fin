import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/app_lock.dart';
import '../../core/providers.dart';
import '../../data/backup_codec.dart';
import '../../data/backup_service.dart';
import '../../shared/finance_bottom_sheet.dart';
import 'settings_widgets.dart';

const _countLabels = {
  'emis': 'EMIs',
  'emi_payments': 'Installments',
  'money_records': 'Money records',
  'money_repayments': 'Repayments',
  'subscriptions': 'Subscriptions',
  'activity_logs': 'Activity',
  'payment_methods': 'Payment methods',
  'settings': 'Settings',
  'recycle_bin': 'Recycle bin',
};

class BackupReminderBanner extends ConsumerWidget {
  const BackupReminderBanner({super.key, required this.onBackUp});
  final VoidCallback onBackUp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(backupStatusProvider).valueOrNull;
    if (status == null || !status.needsReminder) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Material(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
        child: ListTile(
          leading: const Icon(Icons.backup_outlined),
          title: Text(
            status.lastAt == null
                ? 'Your data has not been backed up'
                : 'Your last backup is over 7 days old',
          ),
          trailing: TextButton(
            onPressed: onBackUp,
            child: const Text('Back up'),
          ),
        ),
      ),
    );
  }
}

class BackupSettingsSection extends ConsumerStatefulWidget {
  const BackupSettingsSection({super.key});

  @override
  ConsumerState<BackupSettingsSection> createState() =>
      _BackupSettingsSectionState();
}

class _BackupSettingsSectionState extends ConsumerState<BackupSettingsSection> {
  bool busy = false;

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      if (mounted) ref.invalidate(backupStatusProvider);
    } on FormatException catch (error) {
      if (mounted) _message(context, error.message.toString());
    } catch (error) {
      if (mounted) _message(context, 'Backup action failed: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status =
        ref.watch(backupStatusProvider).valueOrNull ?? const BackupStatus();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsRow(
          icon: Icons.restore_outlined,
          title: 'Restore from backup',
          subtitle: 'Preview before replacing data',
          onTap: busy
              ? null
              : () => run(() => showRestoreBackupFlow(context, ref)),
        ),
        if (ref.read(localBackupProvider).canUndoRestore)
          SettingsRow(
            icon: Icons.undo,
            title: 'Undo restore',
            subtitle: 'Use the safety copy from this session',
            onTap: busy
                ? null
                : () => run(() async {
                    await ref.read(localBackupProvider).undoRestore();
                    if (!mounted) return;
                    _refreshAfterRestore(ref);
                    _message(this.context, 'Restore undone.');
                  }),
          ),
        SettingsRow(
          icon: Icons.folder_open_outlined,
          title: 'Backup folder',
          subtitle: status.folderName ?? 'Not chosen',
          trailing: const Text('Change'),
          onTap: busy
              ? null
              : () => run(() async {
                  final service = ref.read(localBackupProvider);
                  final picked = await service.chooseBackupFolder();
                  if (picked && mounted) {
                    final result = await service.saveNow();
                    if (mounted) _showBackupResult(this.context, result);
                  }
                }),
        ),
        SettingsRow(
          icon: Icons.autorenew,
          title: 'Automatic backup',
          subtitle: 'Once a day when data changes',
          trailing: Switch.adaptive(
            value: status.interval != 'off',
            onChanged: busy
                ? null
                : (enabled) => run(() async {
                    if (enabled && status.folderUri == null) {
                      await showCreateBackupFlow(context, ref);
                      return;
                    }
                    await ref
                        .read(localBackupProvider)
                        .setAutoBackup(
                          interval: enabled ? 'daily' : 'off',
                          keep: status.keep,
                        );
                  }),
          ),
        ),
        SettingsRow(
          icon: Icons.layers_outlined,
          title: 'Keep recent backup days',
          trailing: PopupMenuButton<int>(
            tooltip: 'Number of backup days to keep',
            initialValue: status.keep,
            onSelected: busy
                ? null
                : (count) => run(
                    () => ref
                        .read(localBackupProvider)
                        .setAutoBackup(
                          interval: status.interval == 'off' ? 'off' : 'daily',
                          keep: count,
                        ),
                  ),
            itemBuilder: (_) => const [1, 3, 5, 10]
                .map(
                  (count) => PopupMenuItem(value: count, child: Text('$count')),
                )
                .toList(),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${status.keep}'),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ),
        SettingsRow(
          icon: Icons.password_outlined,
          title: 'Protect backups with a password',
          subtitle: status.passwordProtected
              ? 'Password set'
              : 'Password not set',
          trailing: Switch.adaptive(
            value: status.passwordProtected,
            onChanged: busy
                ? null
                : (enabled) =>
                      run(() => _setBackupProtection(context, ref, enabled)),
          ),
        ),
        if (status.lastError != null)
          SettingsRow(
            icon: Icons.error_outline,
            title: 'Last backup failed',
            subtitle: status.lastError,
          ),
      ],
    );
  }
}

Future<void> showCreateBackupFlow(BuildContext context, WidgetRef ref) async {
  final service = ref.read(localBackupProvider);
  if (!await service.hasUsableFolder()) {
    if (!context.mounted) return;
    final choose = await _showChooseFolderSheet(context);
    if (choose != true || !context.mounted) return;
    final selected = await AppLockSession.instance.keepUnlocked(
      service.chooseBackupFolder,
    );
    if (!selected || !context.mounted) return;
  }
  try {
    final result = await AppLockSession.instance.keepUnlocked(service.saveNow);
    if (!context.mounted) return;
    ref.invalidate(backupStatusProvider);
    _showBackupResult(context, result);
  } on BackupFolderUnavailableException {
    if (!context.mounted) return;
    final choose = await _showChooseFolderSheet(context);
    if (choose != true || !context.mounted) return;
    if (await service.chooseBackupFolder() && context.mounted) {
      final result = await service.saveNow();
      if (!context.mounted) return;
      ref.invalidate(backupStatusProvider);
      _showBackupResult(context, result);
    }
  }
}

Future<bool?> _showChooseFolderSheet(BuildContext context) {
  return showFinanceBottomSheet<bool>(
    context,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Choose where to keep your backups',
            style: Theme.of(sheetContext).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'FinKeep will save future backups there without opening a file picker.',
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => Navigator.pop(sheetContext, true),
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Choose folder'),
          ),
        ],
      ),
    ),
  );
}

void _showBackupResult(BuildContext context, BackupRunResult result) {
  if (result.unchanged) {
    _message(context, 'Already up to date');
    return;
  }
  final saved = result.backup!;
  _message(
    context,
    'Backed up - ${(saved.size / 1024).ceil()} KB - ${saved.location}',
  );
}

Future<void> _setBackupProtection(
  BuildContext context,
  WidgetRef ref,
  bool enabled,
) async {
  final service = ref.read(localBackupProvider);
  if (!enabled) {
    await service.setBackupPassword(null);
    return;
  }
  final password = await _askNewBackupPassword(context);
  if (password != null) await service.setBackupPassword(password);
}

Future<String?> _askNewBackupPassword(BuildContext context) async {
  final password = TextEditingController();
  final confirm = TextEditingController();
  String? error;
  final result = await showFinanceBottomSheet<String>(
    context,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Protect backups',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('A lost backup password cannot be recovered.'),
              const SizedBox(height: 16),
              TextField(
                controller: password,
                obscureText: true,
                keyboardType: TextInputType.visiblePassword,
                decoration: const InputDecoration(labelText: 'Backup password'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirm,
                obscureText: true,
                keyboardType: TextInputType.visiblePassword,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  if (password.text.length < 8 ||
                      password.text != confirm.text) {
                    setSheetState(
                      () => error =
                          'Enter matching passwords of at least 8 characters.',
                    );
                    return;
                  }
                  Navigator.pop(sheetContext, password.text);
                },
                icon: const Icon(Icons.lock_outline),
                label: const Text('Set password'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  password.dispose();
  confirm.dispose();
  return result;
}

Future<void> showRestoreBackupFlow(BuildContext context, WidgetRef ref) async {
  final service = ref.read(localBackupProvider);
  final bytes = await AppLockSession.instance.keepUnlocked(
    service.pickBackupBytes,
  );
  if (bytes == null || !context.mounted) return;
  String? password;
  if (BackupCodec.needsPassword(bytes)) {
    password = await _askPassword(context);
    if (password == null || !context.mounted) return;
  }
  final document = await service.inspectBytes(bytes, password: password);
  await service.validateDocument(document);
  if (!context.mounted) return;
  final approved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Restore this backup?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Created ${DateFormat('d MMM y, h:mm a').format(document.createdAt.toLocal())}',
            ),
            Text(
              'FinKeep ${document.appVersion}${document.legacy ? ' · legacy format (no checksum)' : ''}',
            ),
            const SizedBox(height: 12),
            _Counts(document.counts),
            const SizedBox(height: 12),
            const Text(
              'This replaces EMIs, money, subscriptions, activity and portable settings on this device. Your PIN and backup-folder choice stay unchanged. A private safety copy is made first.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Restore'),
        ),
      ],
    ),
  );
  if (approved != true || !context.mounted) return;
  await AppLockSession.instance.keepUnlocked(
    () => service.restoreWithSafety(document),
  );
  _refreshAfterRestore(ref);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Backup restored.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await service.undoRestore();
            _refreshAfterRestore(ref);
          },
        ),
        duration: const Duration(seconds: 8),
      ),
    );
  }
}

Future<String?> _askPassword(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Backup password'),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Password'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: const Text('Preview'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

void _refreshAfterRestore(WidgetRef ref) {
  ref.invalidate(dashboardProvider);
  ref.invalidate(emisProvider);
  ref.invalidate(emiDetailsProvider);
  ref.invalidate(moneyRecordsProvider);
  ref.invalidate(subscriptionsProvider);
  ref.invalidate(paymentMethodsProvider);
  ref.invalidate(remindersProvider);
  ref.invalidate(financialActionsProvider);
  ref.invalidate(activityProvider);
  ref.invalidate(appThemeModeProvider);
  ref.invalidate(backupStatusProvider);
}

void _message(BuildContext context, String message) {
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _Counts extends StatelessWidget {
  const _Counts(this.counts);
  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 6,
    children: [
      for (final entry in counts.entries)
        if (_countLabels.containsKey(entry.key))
          Chip(label: Text('${_countLabels[entry.key]}: ${entry.value}')),
    ],
  );
}
