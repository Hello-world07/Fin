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
          title: status.folderName ?? 'Choose backup folder',
          subtitle: 'For automatic backup',
          onTap: busy
              ? null
              : () => run(() async {
                  final picked = await ref
                      .read(localBackupProvider)
                      .chooseAutoFolder();
                  if (picked && mounted) {
                    _message(this.context, 'Backup folder selected.');
                  }
                }),
        ),
        SettingsRow(
          icon: Icons.autorenew,
          title: 'Automatic backup',
          subtitle: 'When FinKeep opens',
          trailing: PopupMenuButton<String>(
            tooltip: 'Automatic backup frequency',
            initialValue: status.interval,
            onSelected: busy
                ? null
                : (value) => run(() async {
                    if (value != 'off' && status.folderUri == null) {
                      _message(context, 'Choose a backup folder first.');
                      return;
                    }
                    await ref
                        .read(localBackupProvider)
                        .setAutoBackup(interval: value, keep: status.keep);
                  }),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'off', child: Text('Off')),
              PopupMenuItem(value: 'daily', child: Text('Daily')),
              PopupMenuItem(value: 'weekly', child: Text('Weekly')),
            ],
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    status.interval == 'off'
                        ? 'Off'
                        : status.interval == 'daily'
                        ? 'Daily'
                        : 'Weekly',
                  ),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ),
        if (status.interval != 'off') ...[
          SettingsRow(
            icon: Icons.layers_outlined,
            title: 'Keep recent backups',
            trailing: PopupMenuButton<int>(
              tooltip: 'Number of auto-backups to keep',
              initialValue: status.keep,
              onSelected: busy
                  ? null
                  : (count) => run(
                      () => ref
                          .read(localBackupProvider)
                          .setAutoBackup(
                            interval: status.interval,
                            keep: count,
                          ),
                    ),
              itemBuilder: (_) => const [3, 5, 10, 20]
                  .map(
                    (count) =>
                        PopupMenuItem(value: count, child: Text('$count')),
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
          const Text(
            'Automatic backups are not password protected. Choose a private folder.',
          ),
        ],
      ],
    );
  }
}

Future<void> showCreateBackupFlow(BuildContext context, WidgetRef ref) async {
  final password = await _createPasswordChoice(context);
  if (password == null || !context.mounted) return;
  final service = ref.read(localBackupProvider);
  final saved = await AppLockSession.instance.keepUnlocked(
    () => service.saveNow(password: password.$2),
  );
  if (saved == null || !context.mounted) return;
  ref.invalidate(backupStatusProvider);
  await showFinanceBottomSheet<void>(
    context,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Backup saved',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(saved.name, maxLines: 2, overflow: TextOverflow.ellipsis),
              Text(
                '${(saved.size / 1024).toStringAsFixed(1)} KB · ${saved.location}',
              ),
              const SizedBox(height: 12),
              _Counts(saved.counts),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await service.openLocation(saved);
                  } catch (error) {
                    if (sheetContext.mounted) {
                      _message(sheetContext, 'Could not open location: $error');
                    }
                  }
                },
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Open location'),
              ),
              TextButton.icon(
                onPressed: () => service.shareSavedBackup(saved),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share backup file'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<(bool, String?)?> _createPasswordChoice(BuildContext context) async {
  final password = TextEditingController();
  final confirm = TextEditingController();
  var protect = false;
  String? error;
  final result = await showDialog<(bool, String?)>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Create backup'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Protect with a password'),
                value: protect,
                onChanged: (value) => setDialogState(() {
                  protect = value;
                  error = null;
                }),
              ),
              if (protect) ...[
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                TextField(
                  controller: confirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                  ),
                ),
                const SizedBox(height: 8),
                const Text('A lost backup password cannot be recovered.'),
              ],
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (protect &&
                  (password.text.length < 8 || password.text != confirm.text)) {
                setDialogState(
                  () => error =
                      'Enter matching passwords of at least 8 characters.',
                );
                return;
              }
              Navigator.pop(dialogContext, (
                true,
                protect ? password.text : null,
              ));
            },
            child: const Text('Continue'),
          ),
        ],
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
