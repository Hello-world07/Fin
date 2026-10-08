import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/data/backup_codec.dart';

void main() {
  final date = DateTime.utc(2026, 10, 8, 22, 40);
  final tables = <String, dynamic>{
    'emis': [
      {'id': 1, 'name': 'Phone'},
    ],
    'money_records': <dynamic>[],
    'settings': <dynamic>[],
  };

  test('serializes metadata, counts and checksum', () async {
    final bytes = await BackupCodec.encode(
      tables: tables,
      schemaVersion: 4,
      appVersion: '1.0.0',
      createdAt: date,
    );
    final document = await BackupCodec.decode(bytes);
    expect(document.createdAt, date);
    expect(document.appVersion, '1.0.0');
    expect(document.counts['emis'], 1);
    expect(document.counts['recycle_bin'], 0);
    expect(document.encrypted, isFalse);

    final tampered = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    ((tampered['tables'] as Map<String, dynamic>)['emis'] as List)
            .first['name'] =
        'Changed';
    await expectLater(
      BackupCodec.decode(Uint8List.fromList(utf8.encode(jsonEncode(tampered)))),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('checksum'),
        ),
      ),
    );
  });

  test(
    'AES-GCM password backup round trips and rejects a wrong password',
    () async {
      final bytes = await BackupCodec.encode(
        tables: tables,
        schemaVersion: 4,
        appVersion: '1.0.0',
        createdAt: date,
        password: 'correct horse battery',
      );
      expect(BackupCodec.needsPassword(bytes), isTrue);
      final document = await BackupCodec.decode(
        bytes,
        password: 'correct horse battery',
      );
      expect(document.encrypted, isTrue);
      expect(document.counts['emis'], 1);
      await expectLater(
        BackupCodec.decode(bytes, password: 'wrong password'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Wrong password'),
          ),
        ),
      );
    },
  );

  test('newer backup version is rejected before records are read', () async {
    final bytes = await BackupCodec.encode(
      tables: tables,
      schemaVersion: 4,
      appVersion: '1.0.0',
      createdAt: date,
    );
    final changed = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    changed['formatVersion'] = BackupCodec.version + 1;
    await expectLater(
      BackupCodec.decode(Uint8List.fromList(utf8.encode(jsonEncode(changed)))),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('newer'),
        ),
      ),
    );
  });

  test('missing count metadata is rejected', () async {
    final bytes = await BackupCodec.encode(
      tables: tables,
      schemaVersion: 4,
      appVersion: '1.0.0',
      createdAt: date,
    );
    final changed = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    (changed['counts'] as Map<String, dynamic>).remove('emis');
    final payload = Map<String, dynamic>.from(changed)..remove('checksum');
    changed['checksum'] = hash.sha256
        .convert(utf8.encode(jsonEncode(payload)))
        .toString();
    await expectLater(
      BackupCodec.decode(Uint8List.fromList(utf8.encode(jsonEncode(changed)))),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('counts'),
        ),
      ),
    );
  });
}
