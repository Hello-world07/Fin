import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance/src/data/backup_service.dart';
import 'package:personal_finance/src/data/database.dart';
import 'package:personal_finance/src/data/repositories.dart';
import 'package:personal_finance/src/domain/enums.dart';
import 'package:saf/saf.dart';

void main() {
  late AppDatabase database;
  late FakeSaf saf;
  late LocalBackupService service;
  var now = DateTime(2026, 10, 8, 10);

  setUp(() async {
    database = AppDatabase.test(NativeDatabase.memory());
    saf = FakeSaf();
    service = LocalBackupService(
      database,
      saf: saf,
      secrets: MemoryBackupSecretStore(),
      now: () => now,
    );
    expect(await service.chooseBackupFolder(), isTrue);
  });

  tearDown(() => database.close());

  test('rotation keeps five days and deletes only matching names', () async {
    for (var day = 1; day <= 7; day++) {
      saf.addFile(
        'FinKeep-backup-2026-10-${day.toString().padLeft(2, '0')}.fin',
      );
    }
    saf.addFile('holiday-photo.jpg');
    saf.addFile('FinKeep-backup-not-a-date.fin');

    await service.saveNow();

    final names = saf.fileNames;
    expect(
      names.where(
        (name) =>
            RegExp(r'^FinKeep-backup-\d{4}-\d{2}-\d{2}\.fin$').hasMatch(name),
      ),
      hasLength(5),
    );
    expect(names, contains('holiday-photo.jpg'));
    expect(names, contains('FinKeep-backup-not-a-date.fin'));
  });

  test('same-day backup verifies then replaces that day file', () async {
    final first = await service.saveNow();
    final firstBytes = first.backup!.bytes;
    await FinanceRepository(database).saveSubscription(
      SubscriptionsCompanion.insert(
        name: 'Wifi',
        amountPaise: 60000,
        frequency: PaymentFrequency.monthly,
        nextBillingDate: DateTime(2026, 11, 1),
        status: SubscriptionStatus.active,
      ),
    );

    final second = await service.saveNow();

    expect(second.unchanged, isFalse);
    expect(saf.fileNames, ['FinKeep-backup-2026-10-08.fin']);
    expect(second.backup!.bytes, isNot(equals(firstBytes)));
    expect(saf.readCount, greaterThanOrEqualTo(2));
  });

  test('unchanged data skips the write', () async {
    await service.saveNow();
    final writes = saf.writeCount;

    final result = await service.saveNow();

    expect(result.unchanged, isTrue);
    expect(saf.writeCount, writes);
  });

  test('lost folder permission requests folder selection again', () async {
    saf.permissionGranted = false;

    expect(await service.hasUsableFolder(), isFalse);
    expect((await service.status()).folderUri, isNull);
    await expectLater(
      service.saveNow(),
      throwsA(isA<BackupFolderUnavailableException>()),
    );
    expect((await service.status()).lastError, 'Folder not available');
  });

  test('failed write probe does not store a replacement folder', () async {
    saf.selectedUri = '${FakeSaf.folderUri}%2FFin';
    saf.failWrites = true;

    await expectLater(service.chooseBackupFolder(), throwsFormatException);

    expect((await service.status()).folderUri, FakeSaf.folderUri);
    expect(saf.fileNames, isEmpty);
  });
}

class MemoryBackupSecretStore implements BackupSecretStore {
  String? password;

  @override
  Future<String?> readPassword() async => password;

  @override
  Future<void> writePassword(String? value) async => password = value;
}

class FakeSaf extends Saf {
  static const folderUri =
      'content://test/tree/primary%3ADownload%2FFin%20tracker';

  final Map<String, SafDocumentFile> _files = {};
  final Map<String, Uint8List> _bytes = {};
  bool permissionGranted = true;
  bool failWrites = false;
  String selectedUri = folderUri;
  int writeCount = 0;
  int readCount = 0;
  int _nextId = 0;

  List<String> get fileNames =>
      _files.values.map((file) => file.name).toList()..sort();

  void addFile(String name, [List<int> bytes = const [1]]) {
    final uri = '$folderUri/file/${_nextId++}';
    _files[uri] = _file(uri, name, bytes.length);
    _bytes[uri] = Uint8List.fromList(bytes);
  }

  @override
  Future<SafDocumentFile?> pickDirectory({
    String? initialUri,
    bool writePermission = true,
    bool persistablePermission = true,
  }) async => SafDocumentFile(
    uri: selectedUri,
    name: 'Fin tracker',
    isDir: true,
    length: 0,
    lastModified: 0,
  );

  @override
  Future<List<SafPersistedPermission>> persistedPermissions() async =>
      permissionGranted
      ? [
          SafPersistedPermission(
            uri: selectedUri,
            read: true,
            write: true,
            persistedTime: 0,
          ),
        ]
      : const [];

  @override
  Future<SafDocumentFile?> stat(String uri) async {
    if (uri == folderUri && permissionGranted) {
      return const SafDocumentFile(
        uri: folderUri,
        name: 'Fin tracker',
        isDir: true,
        length: 0,
        lastModified: 0,
      );
    }
    return _files[uri];
  }

  @override
  Future<List<SafDocumentFile>> list(String dirUri) async =>
      _files.values.toList();

  @override
  Future<SafDocumentFile> writeFileBytes(
    String dirUri,
    String name,
    String mime,
    Uint8List data, {
    bool overwrite = false,
    bool append = false,
  }) async {
    if (failWrites) throw const FormatException('Provider rejected write');
    writeCount++;
    final uri = '$folderUri/file/${_nextId++}';
    final file = _file(uri, name, data.length);
    _files[uri] = file;
    _bytes[uri] = Uint8List.fromList(data);
    return file;
  }

  @override
  Future<Uint8List> readFileBytes(String uri, {int? start, int? count}) async {
    readCount++;
    return _bytes[uri]!;
  }

  @override
  Future<void> delete(String uri) async {
    _files.remove(uri);
    _bytes.remove(uri);
  }

  @override
  Future<SafDocumentFile> rename(String uri, String newName) async {
    final old = _files.remove(uri)!;
    final renamed = _file(uri, newName, old.length);
    _files[uri] = renamed;
    return renamed;
  }

  SafDocumentFile _file(String uri, String name, int length) => SafDocumentFile(
    uri: uri,
    name: name,
    isDir: false,
    length: length,
    lastModified: 0,
    mimeType: 'application/octet-stream',
  );
}
