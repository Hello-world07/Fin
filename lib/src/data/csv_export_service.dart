import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'database.dart';

class CsvExportService {
  CsvExportService(this.database);
  final AppDatabase database;

  static const _tables = {
    'EMIs': 'emis',
    'Money': 'money_records',
    'Subscriptions': 'subscriptions',
  };

  Future<void> shareExport() async {
    final directory = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final files = <XFile>[];
    for (final entry in _tables.entries) {
      final columns = await database
          .customSelect('PRAGMA table_info(${entry.value})')
          .get();
      final names = columns.map((row) => row.data['name'] as String).toList();
      final rows = await database
          .customSelect('SELECT * FROM ${entry.value}')
          .get();
      final csv = StringBuffer()..writeln(names.map(_escape).join(','));
      for (final row in rows) {
        csv.writeln(names.map((name) => _escape(row.data[name])).join(','));
      }
      final file = File(
        p.join(directory.path, 'FinKeep-${entry.key}-$stamp.csv'),
      );
      await file.writeAsString(csv.toString(), encoding: utf8, flush: true);
      files.add(XFile(file.path, mimeType: 'text/csv'));
    }
    await SharePlus.instance.share(
      ShareParams(files: files, subject: 'FinKeep CSV export'),
    );
  }

  String _escape(Object? value) {
    final text = value?.toString() ?? '';
    if (!text.contains(RegExp(r'[,"\r\n]'))) return text;
    return '"${text.replaceAll('"', '""')}"';
  }
}
