import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';

class BackupDocument {
  const BackupDocument({
    required this.tables,
    required this.counts,
    required this.createdAt,
    required this.appVersion,
    required this.schemaVersion,
    required this.encrypted,
    required this.legacy,
  });

  final Map<String, dynamic> tables;
  final Map<String, int> counts;
  final DateTime createdAt;
  final String appVersion;
  final int schemaVersion;
  final bool encrypted;
  final bool legacy;
}

class BackupCodec {
  static const format = 'finkeep-local-backup';
  static const version = 2;
  static const maxBytes = 50 * 1024 * 1024;
  static const _iterations = 210000;

  static Future<Uint8List> encode({
    required Map<String, dynamic> tables,
    required int schemaVersion,
    required String appVersion,
    required DateTime createdAt,
    String? password,
  }) async {
    final counts = {
      for (final entry in tables.entries)
        entry.key: (entry.value as List).length,
      'recycle_bin': 0,
    };
    final payload = <String, dynamic>{
      'format': format,
      'formatVersion': version,
      'schemaVersion': schemaVersion,
      'appVersion': appVersion,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'counts': counts,
      'recycleBin': const [],
      'tables': tables,
    };
    final checksum = hash.sha256
        .convert(utf8.encode(jsonEncode(payload)))
        .toString();
    final plain = Uint8List.fromList(
      utf8.encode(jsonEncode({...payload, 'checksum': checksum})),
    );
    if (plain.length > maxBytes) {
      throw const FormatException('The backup is too large.');
    }
    if (password == null) return plain;
    if (password.length < 8) {
      throw const FormatException('Use a password of at least 8 characters.');
    }
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List.generate(16, (_) => random.nextInt(256)),
    );
    final nonce = Uint8List.fromList(
      List.generate(12, (_) => random.nextInt(256)),
    );
    final key = await Pbkdf2.hmacSha256(
      iterations: _iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: password, nonce: salt);
    final box = await AesGcm.with256bits().encrypt(
      plain,
      secretKey: key,
      nonce: nonce,
    );
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': format,
          'formatVersion': version,
          'encrypted': true,
          'kdf': 'PBKDF2-HMAC-SHA256',
          'iterations': _iterations,
          'salt': base64Encode(salt),
          'cipher': 'AES-256-GCM',
          'nonce': base64Encode(box.nonce),
          'mac': base64Encode(box.mac.bytes),
          'ciphertext': base64Encode(box.cipherText),
        }),
      ),
    );
  }

  static bool needsPassword(Uint8List bytes) {
    final envelope = _jsonMap(bytes);
    return envelope['encrypted'] == true;
  }

  static Future<BackupDocument> decode(
    Uint8List bytes, {
    String? password,
  }) async {
    var envelope = _jsonMap(bytes);
    if (envelope['format'] != format) {
      throw const FormatException('This is not a FinKeep backup.');
    }
    final fileVersion = envelope['formatVersion'];
    if (fileVersion is! int || fileVersion > version) {
      throw const FormatException(
        'This backup was made by a newer FinKeep version.',
      );
    }
    if (fileVersion < 1) {
      throw const FormatException('Unsupported backup version.');
    }
    final encrypted = envelope['encrypted'] == true;
    if (encrypted) {
      if (password == null || password.isEmpty) {
        throw const FormatException('Enter the backup password.');
      }
      try {
        if (envelope['kdf'] != 'PBKDF2-HMAC-SHA256' ||
            envelope['cipher'] != 'AES-256-GCM' ||
            envelope['iterations'] != _iterations) {
          throw const FormatException('Unsupported backup encryption.');
        }
        final salt = base64Decode(envelope['salt'] as String);
        final nonce = base64Decode(envelope['nonce'] as String);
        final mac = base64Decode(envelope['mac'] as String);
        final ciphertext = base64Decode(envelope['ciphertext'] as String);
        if (salt.length != 16 || nonce.length != 12 || mac.length != 16) {
          throw const FormatException('The encrypted backup is corrupt.');
        }
        final key = await Pbkdf2.hmacSha256(
          iterations: _iterations,
          bits: 256,
        ).deriveKeyFromPassword(password: password, nonce: salt);
        final clear = await AesGcm.with256bits().decrypt(
          SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
          secretKey: key,
        );
        envelope = _jsonMap(Uint8List.fromList(clear));
      } on SecretBoxAuthenticationError {
        throw const FormatException(
          'Wrong password or corrupt encrypted file.',
        );
      } on FormatException {
        rethrow;
      } catch (_) {
        throw const FormatException('The encrypted backup is corrupt.');
      }
    }
    if (envelope['format'] != format ||
        envelope['formatVersion'] != fileVersion) {
      throw const FormatException('The backup content is corrupt.');
    }
    final tables = envelope['tables'];
    if (tables is! Map<String, dynamic>) {
      throw const FormatException('The backup is missing records.');
    }
    if (fileVersion == version) {
      final checksum = envelope.remove('checksum');
      if (checksum is! String ||
          hash.sha256.convert(utf8.encode(jsonEncode(envelope))).toString() !=
              checksum) {
        throw const FormatException('The backup checksum does not match.');
      }
      final counts = envelope['counts'];
      if (counts is! Map<String, dynamic> ||
          counts.keys.toSet().difference({
            ...tables.keys,
            'recycle_bin',
          }).isNotEmpty ||
          {
            ...tables.keys,
            'recycle_bin',
          }.difference(counts.keys.toSet()).isNotEmpty ||
          envelope['recycleBin'] is! List ||
          (envelope['recycleBin'] as List).isNotEmpty ||
          counts.entries.any(
            (e) =>
                e.value is! int ||
                e.value !=
                    (e.key == 'recycle_bin'
                        ? 0
                        : (tables[e.key] is List
                              ? (tables[e.key] as List).length
                              : -1)),
          )) {
        throw const FormatException('The backup record counts are corrupt.');
      }
    }
    final date = DateTime.tryParse(
      (envelope['createdAt'] ?? envelope['exportedAt'] ?? '').toString(),
    );
    final schema = envelope['schemaVersion'];
    if (date == null || schema is! int) {
      throw const FormatException('The backup metadata is corrupt.');
    }
    return BackupDocument(
      tables: tables,
      counts: {
        for (final entry in tables.entries)
          entry.key: entry.value is List ? (entry.value as List).length : 0,
        'recycle_bin': 0,
      },
      createdAt: date,
      appVersion: (envelope['appVersion'] ?? 'Unknown').toString(),
      schemaVersion: schema,
      encrypted: encrypted,
      legacy: fileVersion == 1,
    );
  }

  static Map<String, dynamic> _jsonMap(Uint8List bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('The selected backup is too large.');
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      throw const FormatException('The backup file is corrupt or unreadable.');
    }
    throw const FormatException('The backup file is corrupt or unreadable.');
  }
}
