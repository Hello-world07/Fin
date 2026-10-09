import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:saf/saf.dart';
import 'package:share_plus/share_plus.dart';

import 'backup_codec.dart';
import 'database.dart';
import 'repositories.dart';
import '../domain/enums.dart';

class SavedBackup {
  const SavedBackup({
    required this.name,
    required this.location,
    required this.size,
    required this.counts,
    required this.bytes,
    required this.uri,
  });
  final String name;
  final String location;
  final int size;
  final Map<String, int> counts;
  final Uint8List bytes;
  final String uri;
}

class BackupRunResult {
  const BackupRunResult.saved(this.backup) : unchanged = false;
  const BackupRunResult.unchanged() : backup = null, unchanged = true;

  final SavedBackup? backup;
  final bool unchanged;
}

class BackupFolderUnavailableException implements Exception {
  const BackupFolderUnavailableException();

  @override
  String toString() => 'Backup folder not available';
}

abstract class BackupSecretStore {
  Future<String?> readPassword();
  Future<void> writePassword(String? password);
}

class SecureBackupSecretStore implements BackupSecretStore {
  SecureBackupSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'finkeep.backup.password';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readPassword() => _storage.read(key: _key);

  @override
  Future<void> writePassword(String? password) => password == null
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: password);
}

class BackupStatus {
  const BackupStatus({
    this.folderUri,
    this.folderName,
    this.interval = 'off',
    this.keep = 5,
    this.lastAt,
    this.lastName,
    this.lastLocation,
    this.lastError,
    this.passwordProtected = false,
    this.lastDataChecksum,
    this.lastAutoAttemptAt,
  });
  final String? folderUri;
  final String? folderName;
  final String interval;
  final int keep;
  final DateTime? lastAt;
  final String? lastName;
  final String? lastLocation;
  final String? lastError;
  final bool passwordProtected;
  final String? lastDataChecksum;
  final DateTime? lastAutoAttemptAt;

  bool get needsReminder =>
      lastAt == null || DateTime.now().difference(lastAt!).inDays >= 7;
}

class LocalBackupService {
  LocalBackupService(
    this.database, {
    Saf? saf,
    BackupSecretStore? secrets,
    DateTime Function()? now,
  }) : _saf = saf ?? Saf(),
       _secrets = secrets ?? SecureBackupSecretStore(),
       _now = now ?? DateTime.now;

  static const formatName = 'finkeep-local-backup';
  static const formatVersion = BackupCodec.version;
  static final _backupNamePattern = RegExp(
    r'^FinKeep-backup-\d{4}-\d{2}-\d{2}\.fin$',
  );
  static const _backupSettingsPrefix = 'backup.local.';
  static const _folderChannel = MethodChannel('finkeep/backup_folder');

  static const _insertOrder = [
    'payment_methods',
    'emis',
    'emi_payments',
    'money_records',
    'money_repayments',
    'subscriptions',
    'settings',
    'activity_logs',
  ];

  static const _deleteOrder = [
    'activity_logs',
    'emi_payments',
    'money_repayments',
    'emis',
    'money_records',
    'subscriptions',
    'payment_methods',
    'settings',
  ];

  final AppDatabase database;
  final Saf _saf;
  final BackupSecretStore _secrets;
  final DateTime Function() _now;
  bool canUndoRestore = false;

  Future<String> createBackupJson() async {
    return utf8.decode(await createBackupBytes());
  }

  Future<Uint8List> createBackupBytes({String? password}) async {
    final tables = await database.transaction(() async {
      final snapshot = <String, List<Map<String, Object?>>>{};
      for (final table in _insertOrder) {
        final rows = await database.customSelect('SELECT * FROM $table').get();
        snapshot[table] = rows
            .map((row) => Map<String, Object?>.from(row.data))
            .where(
              (row) =>
                  table != 'settings' ||
                  (!(row['key'] as String).startsWith('privacy.appLock.') &&
                      !(row['key'] as String).startsWith(
                        _backupSettingsPrefix,
                      )),
            )
            .toList();
      }
      return snapshot;
    });
    String version;
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      version = '1.0.0';
    }
    return BackupCodec.encode(
      tables: tables,
      schemaVersion: database.schemaVersion,
      appVersion: version,
      createdAt: DateTime.now(),
      password: password,
    );
  }

  Future<BackupDocument> inspectBytes(Uint8List bytes, {String? password}) =>
      BackupCodec.decode(bytes, password: password);

  Future<void> restoreJson(String content) async {
    final document = await inspectBytes(
      Uint8List.fromList(utf8.encode(content)),
    );
    await restoreDocument(document);
  }

  Future<void> restoreDocument(BackupDocument document) async {
    final columns = await validateDocument(document);
    final tables = document.tables;
    final deviceSecuritySettings =
        await (database.select(database.settings)..where(
              (setting) =>
                  setting.key.like('privacy.appLock.%') |
                  setting.key.like('$_backupSettingsPrefix%'),
            ))
            .get();

    await database.transaction(() async {
      for (final table in _deleteOrder) {
        await database.customStatement('DELETE FROM $table');
      }
      for (final table in _insertOrder) {
        final tableColumns = columns[table]!.toList();
        final columnSql = tableColumns.map((column) => '"$column"').join(', ');
        final placeholders = List.filled(tableColumns.length, '?').join(', ');
        final rows = <dynamic>[
          ...(tables[table] as List<dynamic>),
          if (table == 'settings')
            ...deviceSecuritySettings.map(
              (setting) => {'key': setting.key, 'value': setting.value},
            ),
        ];
        for (final source in rows) {
          final row = source as Map<String, dynamic>;
          await database.customStatement(
            'INSERT INTO $table ($columnSql) VALUES ($placeholders)',
            tableColumns.map((column) => row[column]).toList(),
          );
        }
      }
    });
    database.markTablesUpdated(database.allTables);
    try {
      await FinanceRepository(database).refreshLocalReminders();
    } catch (_) {
      // Restored data remains valid even when notification access is unavailable.
    }
  }

  Future<Map<String, Set<String>>> validateDocument(
    BackupDocument document,
  ) async {
    if (document.schemaVersion != database.schemaVersion &&
        document.schemaVersion != 3) {
      throw const FormatException(
        'This backup uses an unsupported database version.',
      );
    }
    final tables = document.tables;
    if (document.schemaVersion == 3) {
      final oldEmis = tables['emis'];
      if (oldEmis is List) {
        for (final row in oldEmis.whereType<Map<String, dynamic>>()) {
          row.putIfAbsent('type', () => 'Loan');
          row.putIfAbsent('initial_paid_installments', () => 0);
        }
      }
    }
    if (tables.keys.toSet().difference(_insertOrder.toSet()).isNotEmpty ||
        tables.length != _insertOrder.length) {
      throw const FormatException('The backup is missing or has unknown data.');
    }

    final columns = <String, Set<String>>{};
    for (final table in _insertOrder) {
      final info = await database
          .customSelect('PRAGMA table_info($table)')
          .get();
      columns[table] = info.map((row) => row.data['name'] as String).toSet();
      final sourceRows = tables[table];
      if (sourceRows is! List) {
        throw FormatException('Invalid data in $table.');
      }
      for (final sourceRow in sourceRows) {
        if (sourceRow is! Map<String, dynamic> ||
            sourceRow.keys.toSet().difference(columns[table]!).isNotEmpty ||
            columns[table]!.difference(sourceRow.keys.toSet()).isNotEmpty) {
          throw FormatException('Invalid row in $table.');
        }
        if (table == 'settings' &&
            ((sourceRow['key'] as String).startsWith('privacy.appLock.') ||
                (sourceRow['key'] as String).startsWith(
                  _backupSettingsPrefix,
                ))) {
          throw const FormatException(
            'Device-specific security and backup settings cannot be restored.',
          );
        }
        if (sourceRow.values.any(
          (value) =>
              value != null &&
              value is! String &&
              value is! num &&
              value is! bool,
        )) {
          throw FormatException('Unsupported value in $table.');
        }
      }
    }
    _validateFinanceRows(tables);

    return columns;
  }

  void _validateFinanceRows(Map<String, dynamic> tables) {
    List<Map<String, dynamic>> rows(String table) =>
        (tables[table] as List).cast<Map<String, dynamic>>();
    int number(Map<String, dynamic> row, String column) {
      final value = row[column];
      if (value is! num || !value.isFinite || value % 1 != 0) {
        throw FormatException('Invalid $column in backup.');
      }
      return value.toInt();
    }

    void dateValue(
      Map<String, dynamic> row,
      String column, {
      bool nullable = false,
    }) {
      final value = row[column];
      if (nullable && value == null) return;
      if (value is! num || !value.isFinite || value % 1 != 0) {
        throw FormatException('Invalid $column in backup.');
      }
    }

    void uniqueIds(List<Map<String, dynamic>> items, String table) {
      final ids = items.map((item) => number(item, 'id')).toList();
      if (ids.any((id) => id <= 0) || ids.toSet().length != ids.length) {
        throw FormatException('Invalid or duplicate IDs in $table.');
      }
    }

    bool validEnum(Object? value, Iterable<Enum> values) =>
        value is String && values.any((item) => item.name == value);

    final methods = rows('payment_methods');
    uniqueIds(methods, 'payment_methods');
    for (final row in methods) {
      dateValue(row, 'created_at');
    }
    final methodIds = methods.map((row) => number(row, 'id')).toSet();
    final emis = rows('emis');
    uniqueIds(emis, 'emis');
    final emiById = {for (final row in emis) number(row, 'id'): row};
    for (final row in emis) {
      if (number(row, 'principal_paise') <= 0 ||
          number(row, 'emi_amount_paise') <= 0 ||
          number(row, 'tenure_months') <= 0 ||
          number(row, 'initial_paid_installments') < 0 ||
          number(row, 'initial_paid_installments') >
              number(row, 'tenure_months') ||
          !const {
            'Loan',
            'Phone/Product',
            'Credit Card',
          }.contains(row['type']) ||
          !validEnum(row['frequency'], PaymentFrequency.values) ||
          !validEnum(row['status'], EmiStatus.values) ||
          (row['payment_method_id'] != null &&
              !methodIds.contains(number(row, 'payment_method_id')))) {
        throw const FormatException('Invalid EMI data in backup.');
      }
      dateValue(row, 'start_date');
      dateValue(row, 'next_due_date');
      dateValue(row, 'created_at');
      dateValue(row, 'updated_at');
      final rate = row['interest_rate'];
      if (rate != null && (rate is! num || !rate.isFinite || rate < 0)) {
        throw const FormatException('Invalid EMI interest rate in backup.');
      }
    }
    final emiPayments = rows('emi_payments');
    uniqueIds(emiPayments, 'emi_payments');
    final paidInstallments = <String>{};
    for (final row in emiPayments) {
      final emi = emiById[number(row, 'emi_id')];
      final installment = number(row, 'installment_number');
      if (emi == null ||
          number(row, 'amount_paise') <= 0 ||
          installment < 1 ||
          installment > number(emi, 'tenure_months') ||
          !paidInstallments.add('${row['emi_id']}:$installment')) {
        throw const FormatException('Invalid EMI payment history in backup.');
      }
      dateValue(row, 'paid_on');
    }

    final money = rows('money_records');
    uniqueIds(money, 'money_records');
    final moneyById = {for (final row in money) number(row, 'id'): row};
    for (final row in money) {
      if (number(row, 'amount_paise') <= 0 ||
          !validEnum(row['direction'], MoneyDirection.values) ||
          !validEnum(row['status'], MoneyStatus.values) ||
          (row['payment_method_id'] != null &&
              !methodIds.contains(number(row, 'payment_method_id')))) {
        throw const FormatException('Invalid Money record in backup.');
      }
      dateValue(row, 'record_date');
      dateValue(row, 'due_date', nullable: true);
      dateValue(row, 'created_at');
      dateValue(row, 'updated_at');
    }
    final repayments = rows('money_repayments');
    uniqueIds(repayments, 'money_repayments');
    final repaidByRecord = <int, int>{};
    for (final row in repayments) {
      final recordId = number(row, 'money_record_id');
      if (!moneyById.containsKey(recordId) ||
          number(row, 'amount_paise') <= 0) {
        throw const FormatException('Invalid repayment history in backup.');
      }
      repaidByRecord.update(
        recordId,
        (amount) => amount + number(row, 'amount_paise'),
        ifAbsent: () => number(row, 'amount_paise'),
      );
      dateValue(row, 'paid_on');
    }
    for (final entry in repaidByRecord.entries) {
      if (entry.value > number(moneyById[entry.key]!, 'amount_paise')) {
        throw const FormatException(
          'Repayments exceed the original amount in backup.',
        );
      }
    }

    final subscriptions = rows('subscriptions');
    uniqueIds(subscriptions, 'subscriptions');
    for (final row in subscriptions) {
      if (number(row, 'amount_paise') <= 0 ||
          !validEnum(row['frequency'], PaymentFrequency.values) ||
          !validEnum(row['status'], SubscriptionStatus.values) ||
          (row['payment_method_id'] != null &&
              !methodIds.contains(number(row, 'payment_method_id')))) {
        throw const FormatException('Invalid subscription data in backup.');
      }
      dateValue(row, 'next_billing_date');
      dateValue(row, 'created_at');
      dateValue(row, 'updated_at');
    }
    final logs = rows('activity_logs');
    uniqueIds(logs, 'activity_logs');
    for (final row in logs) {
      if (!validEnum(row['type'], ActivityType.values)) {
        throw const FormatException('Invalid activity history in backup.');
      }
      dateValue(row, 'occurred_at');
    }
  }

  Future<BackupRunResult> saveNow() async {
    final config = await status();
    if (!await hasUsableFolder(config)) {
      await _setSetting('lastError', 'Folder not available');
      throw const BackupFolderUnavailableException();
    }
    try {
      final password = await _secrets.readPassword();
      final bytes = await createBackupBytes(password: password);
      final document = await inspectBytes(bytes, password: password);
      final files = await _saf.list(config.folderUri!);
      final priorName = config.lastName;
      final priorStillExists =
          priorName != null &&
          files.any((file) => !file.isDir && file.name == priorName);
      if (priorStillExists &&
          config.lastDataChecksum == document.dataChecksum) {
        await _setSetting('lastError', '');
        return const BackupRunResult.unchanged();
      }

      final now = _now();
      final name = 'FinKeep-backup-${DateFormat('yyyy-MM-dd').format(now)}.fin';
      final temporaryName = '$name.${now.microsecondsSinceEpoch}.pending';
      SafDocumentFile? pending;
      try {
        pending = await _saf.writeFileBytes(
          config.folderUri!,
          temporaryName,
          'application/octet-stream',
          bytes,
        );
        final verifiedBytes = await _saf.readFileBytes(pending.uri);
        final verified = await inspectBytes(verifiedBytes, password: password);
        if (verified.dataChecksum != document.dataChecksum) {
          throw const FormatException('Backup verification failed.');
        }
        for (final old in files.where(
          (file) => !file.isDir && file.name == name,
        )) {
          await _saf.delete(old.uri);
        }
        final savedFile = await _saf.rename(pending.uri, name);
        pending = null;
        await _rotateBackups(config.folderUri!, config.keep);
        await _setSetting('lastAt', now.toUtc().toIso8601String());
        await _setSetting('lastName', name);
        await _setSetting(
          'lastLocation',
          config.folderName ?? 'Selected folder',
        );
        await _setSetting('lastDataChecksum', document.dataChecksum);
        await _setSetting('lastError', '');
        return BackupRunResult.saved(
          SavedBackup(
            name: name,
            location: config.folderName ?? 'Selected folder',
            size: verifiedBytes.length,
            counts: verified.counts,
            bytes: verifiedBytes,
            uri: savedFile.uri,
          ),
        );
      } finally {
        if (pending != null) {
          try {
            await _saf.delete(pending.uri);
          } catch (_) {
            // A failed cleanup must not hide the original backup error.
          }
        }
      }
    } catch (error) {
      await _setSetting(
        'lastError',
        error is BackupFolderUnavailableException
            ? 'Folder not available'
            : 'Could not write backup',
      );
      rethrow;
    }
  }

  Future<void> _rotateBackups(String folderUri, int keep) async {
    final files =
        (await _saf.list(folderUri))
            .where(
              (file) => !file.isDir && _backupNamePattern.hasMatch(file.name),
            )
            .toList()
          ..sort((a, b) => b.name.compareTo(a.name));
    for (final old in files.skip(keep)) {
      await _saf.delete(old.uri);
    }
  }

  Future<void> shareSavedBackup(SavedBackup saved) async {
    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path, saved.name));
    await file.writeAsBytes(saved.bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/octet-stream')],
        subject: 'FinKeep backup file',
      ),
    );
  }

  Future<void> openLocation(SavedBackup saved) async {
    await _saf.pickFile(initialUri: saved.uri);
  }

  Future<Uint8List?> pickBackupBytes() async {
    final file = await FilePicker.pickFile(
      type: FileType.any,
      dialogTitle: 'Choose a FinKeep backup',
    );
    if (file == null) return null;
    if ((await file.length() ?? BackupCodec.maxBytes + 1) >
            BackupCodec.maxBytes ||
        file.path == null) {
      throw const FormatException(
        'The selected backup is too large or unreadable.',
      );
    }
    return File(file.path!).readAsBytes();
  }

  Future<void> restoreWithSafety(BackupDocument document) async {
    await validateDocument(document);
    final safety = await _safetyFile();
    final temp = File('${safety.path}.tmp');
    final bytes = await createBackupBytes();
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(safety.path);
    await restoreDocument(document);
    canUndoRestore = true;
  }

  Future<void> undoRestore() async {
    if (!canUndoRestore) return;
    final safety = await _safetyFile();
    final document = await inspectBytes(await safety.readAsBytes());
    await restoreDocument(document);
    canUndoRestore = false;
  }

  Future<File> _safetyFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(p.join(directory.path, 'FinKeep-pre-restore.finkeep'));
  }

  Future<BackupStatus> status() async {
    final rows = await (database.select(
      database.settings,
    )..where((row) => row.key.like('$_backupSettingsPrefix%'))).get();
    final values = {
      for (final row in rows)
        row.key.substring(_backupSettingsPrefix.length): row.value,
    };
    final storedKeep = int.tryParse(values['keep'] ?? '');
    final keep = const {1, 3, 5, 10}.contains(storedKeep) ? storedKeep! : 5;
    return BackupStatus(
      folderUri: values['folderUri'],
      folderName: values['folderName'],
      interval: values['interval'] == null || values['interval'] == 'off'
          ? 'off'
          : 'daily',
      keep: keep,
      lastAt: DateTime.tryParse(values['lastAt'] ?? ''),
      lastName: values['lastName'],
      lastLocation: values['lastLocation'],
      lastError: (values['lastError'] ?? '').isEmpty
          ? null
          : values['lastError'],
      passwordProtected: await _secrets.readPassword() != null,
      lastDataChecksum: values['lastDataChecksum'],
      lastAutoAttemptAt: DateTime.tryParse(values['lastAutoAttemptAt'] ?? ''),
    );
  }

  Future<bool> chooseBackupFolder() async {
    final treeUri = Platform.isAndroid
        ? await _folderChannel.invokeMethod<String>('pickTree')
        : (await _saf.pickDirectory())?.uri;
    if (treeUri == null) return false;
    SafDocumentFile? probe;
    try {
      final grants = await _saf.persistedPermissions();
      if (!grants.any(
        (grant) => grant.uri == treeUri && grant.read && grant.write,
      )) {
        throw const FormatException(
          'Folder access was not granted. Choose the folder and tap Allow.',
        );
      }
      final probeBytes = Uint8List.fromList(const [
        70,
        105,
        110,
        75,
        101,
        101,
        112,
      ]);
      probe = await _saf.writeFileBytes(
        treeUri,
        '.FinKeep-write-test-${_now().microsecondsSinceEpoch}.tmp',
        'application/octet-stream',
        probeBytes,
      );
      final readBack = await _saf.readFileBytes(probe.uri);
      if (!_sameBytes(probeBytes, readBack)) {
        throw const FormatException('The selected folder is not writable.');
      }
      await _saf.delete(probe.uri);
      probe = null;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'Could not write to this folder. Choose another folder and tap Allow.',
      );
    } finally {
      if (probe != null) {
        try {
          await _saf.delete(probe.uri);
        } catch (_) {
          // Keep the folder unselected when the write probe cannot be cleaned up.
        }
      }
    }
    await _setSetting('folderUri', treeUri);
    await _setSetting('folderName', _locationFromUri(treeUri));
    await _setSetting('interval', 'daily');
    await _setSetting('lastDataChecksum', '');
    await _setSetting('lastError', '');
    return true;
  }

  Future<bool> hasUsableFolder([BackupStatus? current]) async {
    final config = current ?? await status();
    if (config.folderUri == null) return false;
    try {
      final grants = await _saf.persistedPermissions();
      if (!grants.any(
        (grant) => grant.uri == config.folderUri && grant.read && grant.write,
      )) {
        await _clearSavedFolder();
        return false;
      }
      final available = await _saf.stat(config.folderUri!) != null;
      if (!available) await _clearSavedFolder();
      return available;
    } catch (_) {
      await _clearSavedFolder();
      return false;
    }
  }

  Future<void> _clearSavedFolder() async {
    await (database.delete(database.settings)..where(
          (row) => row.key.isIn([
            '${_backupSettingsPrefix}folderUri',
            '${_backupSettingsPrefix}folderName',
          ]),
        ))
        .go();
    await _setSetting('lastError', 'Folder not available');
  }

  bool _sameBytes(Uint8List first, Uint8List second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  Future<void> setBackupPassword(String? password) async {
    if (password != null && password.length < 8) {
      throw const FormatException('Use a password of at least 8 characters.');
    }
    await _secrets.writePassword(password);
    await _setSetting('lastDataChecksum', '');
  }

  Future<void> setAutoBackup({required String interval, int keep = 5}) async {
    if (!const {'off', 'daily'}.contains(interval) ||
        !const {1, 3, 5, 10}.contains(keep)) {
      throw const FormatException('Invalid auto-backup settings.');
    }
    await _setSetting('interval', interval);
    await _setSetting('keep', keep.toString());
  }

  Future<SavedBackup?> runAutoBackupIfDue() async {
    final config = await status();
    if (config.interval == 'off' || config.folderUri == null) return null;
    final now = _now();
    final lastAttempt = config.lastAutoAttemptAt;
    if (lastAttempt != null &&
        lastAttempt.year == now.year &&
        lastAttempt.month == now.month &&
        lastAttempt.day == now.day) {
      return null;
    }
    await _setSetting('lastAutoAttemptAt', now.toUtc().toIso8601String());
    try {
      final result = await saveNow();
      return result.backup;
    } catch (_) {
      return null;
    }
  }

  Future<void> _setSetting(String key, String value) async {
    await database
        .into(database.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: '$_backupSettingsPrefix$key',
            value: value,
          ),
        );
  }

  String _locationFromUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return 'Selected location';
    final decoded = Uri.decodeComponent(uri.pathSegments.lastOrNull ?? '');
    if (decoded.contains(':')) {
      final path = decoded.substring(decoded.indexOf(':') + 1);
      if (path.isNotEmpty && !RegExp(r'^\d+$').hasMatch(path)) {
        return path
            .split('/')
            .map((part) => part == 'Download' ? 'Downloads' : part)
            .join(' > ');
      }
    }
    final authority = uri.host.toLowerCase();
    if (authority.contains('downloads')) return 'Downloads';
    if (authority.contains('google') || authority.contains('drive')) {
      return 'Google Drive';
    }
    return 'Selected location';
  }
}
