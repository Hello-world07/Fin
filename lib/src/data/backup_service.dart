import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'database.dart';
import '../domain/enums.dart';

class LocalBackupService {
  LocalBackupService(this.database);

  static const formatName = 'finkeep-local-backup';
  static const formatVersion = 1;

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

  Future<String> createBackupJson() async {
    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in _insertOrder) {
      final rows = await database.customSelect('SELECT * FROM $table').get();
      tables[table] = rows
          .map((row) => Map<String, Object?>.from(row.data))
          .where(
            (row) =>
                table != 'settings' ||
                !(row['key'] as String).startsWith('privacy.appLock.'),
          )
          .toList();
    }
    return const JsonEncoder.withIndent('  ').convert({
      'format': formatName,
      'formatVersion': formatVersion,
      'schemaVersion': database.schemaVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'tables': tables,
    });
  }

  Future<void> restoreJson(String content) async {
    if (content.length > 50 * 1024 * 1024) {
      throw const FormatException('The selected backup is too large.');
    }
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != formatName ||
        decoded['formatVersion'] != formatVersion ||
        (decoded['schemaVersion'] != database.schemaVersion &&
            decoded['schemaVersion'] != 3) ||
        decoded['tables'] is! Map<String, dynamic>) {
      throw const FormatException('This is not a supported FinKeep backup.');
    }
    final tables = decoded['tables'] as Map<String, dynamic>;
    if (decoded['schemaVersion'] == 3) {
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
            (sourceRow['key'] as String).startsWith('privacy.appLock.')) {
          throw const FormatException(
            'Device security settings are not included in a data backup.',
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

    final deviceSecuritySettings = await (database.select(
      database.settings,
    )..where((setting) => setting.key.like('privacy.appLock.%'))).get();

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

  Future<void> shareBackup() async {
    final content = await createBackupJson();
    final directory = await getApplicationDocumentsDirectory();
    final file = File(
      p.join(
        directory.path,
        'finkeep-backup-${DateTime.now().millisecondsSinceEpoch}.json',
      ),
    );
    await file.writeAsString(content, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'FinKeep data backup',
        text: 'FinKeep local data backup',
      ),
    );
  }

  Future<bool> pickAndRestore() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      dialogTitle: 'Choose a FinKeep backup',
    );
    if (file == null) return false;
    if (file.path == null) {
      throw const FormatException('The selected file could not be read.');
    }
    final sourceFile = File(file.path!);
    if (await sourceFile.length() > 50 * 1024 * 1024) {
      throw const FormatException('The selected backup is too large.');
    }
    final content = await sourceFile.readAsString();
    await restoreJson(content);
    return true;
  }
}
