import 'dart:convert';
import 'dart:io';

import 'package:flutter_grinding_app/core/storage/durable_file_store.dart';
import 'package:flutter_grinding_app/features/grinding_orders/data/file_pending_command_store.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/entities/pending_command.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/grinding_command.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/grinding_source.dart';
import 'package:flutter_test/flutter_test.dart';

PendingCommand _record({
  int orderId = 1042,
  GrindingCommand command = GrindingCommand.start,
  String id = 'c1f0f1b8-9a57-4a0e-9a0e-5d2f7d7d9b10',
  GrindingSourceType? sourceType,
}) => PendingCommand(
  orderId: orderId,
  orderNumber: 'GR-${orderId.toString().padLeft(6, '0')}',
  identifier: '001000000255',
  sourceType: sourceType,
  command: command,
  clientRequestId: id,
  workerOperatorId: 57,
  workerName: 'محمد أحمد',
  createdAt: '2026-09-22T09:41:07.312Z',
);

void main() {
  late Directory root;
  late Directory dir;

  setUp(() {
    root = Directory.systemTemp.createTempSync('grinding_store_test');
    dir = Directory('${root.path}${Platform.pathSeparator}pending');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  DurableFileStore store() => DurableFileStore(() async => dir);

  group('DurableFileStore', () {
    test('write → readAll round trip; directory created on demand', () async {
      final files = store();
      await files.write('pending_1_start', '{"a":1}');
      expect(dir.existsSync(), isTrue);
      expect(await files.readAll(), <String, String>{
        'pending_1_start': '{"a":1}',
      });
    });

    test('a completed write is visible to a brand-new instance', () async {
      await store().write('pending_1_start', 'x');
      // A new instance = a new process reading the same directory.
      expect(await store().readAll(), <String, String>{'pending_1_start': 'x'});
    });

    test('no temp file remains after a completed write', () async {
      await store().write('pending_1_start', 'x');
      final names = dir.listSync().map((e) => e.uri.pathSegments.last);
      expect(names, <String>['pending_1_start.json']);
    });

    test('overwrite replaces the record atomically', () async {
      final files = store();
      await files.write('r', 'first');
      await files.write('r', 'second');
      expect(await files.readAll(), <String, String>{'r': 'second'});
    });

    test('an interrupted write (leftover .tmp) is discarded on read', () async {
      dir.createSync(recursive: true);
      File('${dir.path}/pending_9_start.json.tmp').writeAsStringSync('{');
      final records = await store().readAll();
      expect(records, isEmpty);
      expect(
        File('${dir.path}/pending_9_start.json.tmp').existsSync(),
        isFalse,
      );
    });

    test('foreign / invalid file names are ignored', () async {
      dir.createSync(recursive: true);
      File('${dir.path}/notes.txt').writeAsStringSync('x');
      File('${dir.path}/bad name.json').writeAsStringSync('x');
      expect(await store().readAll(), isEmpty);
    });

    test('delete removes; deleting a missing record is fine', () async {
      final files = store();
      await files.write('r', 'x');
      await files.delete('r');
      await files.delete('r');
      expect(await files.readAll(), isEmpty);
    });

    test('invalid names are rejected (no path traversal)', () async {
      expect(() => store().write('../evil', 'x'), throwsArgumentError);
      expect(() => store().delete('a/b'), throwsArgumentError);
    });

    test('operations are serialized: delete never overtakes a write', () async {
      final files = store();
      final write = files.write('r', 'x');
      final delete = files.delete('r');
      await Future.wait(<Future<void>>[write, delete]);
      expect(await files.readAll(), isEmpty);
    });

    test('a failing write throws (caller must not send)', () async {
      // The "directory" is a regular file → the directory cannot be created.
      final blocker = File('${root.path}${Platform.pathSeparator}blocker')
        ..writeAsStringSync('x');
      final files = DurableFileStore(() async => Directory(blocker.path));
      await expectLater(
        files.write('r', 'x'),
        throwsA(isA<FileSystemException>()),
      );
      // The chain survives the failure.
      final ok = DurableFileStore(() async => dir);
      await ok.write('r', 'y');
      expect(await ok.readAll(), <String, String>{'r': 'y'});
    });
  });

  group('FilePendingCommandStore', () {
    test('persists one file per orderId + command', () async {
      final pending = FilePendingCommandStore(store());
      await pending.save(_record());
      await pending.save(
        _record(orderId: 1043, command: GrindingCommand.complete, id: 'id-2'),
      );
      final names = dir.listSync().map((e) => e.uri.pathSegments.last).toSet();
      expect(names, <String>{
        'pending_1042_start.json',
        'pending_1043_complete.json',
      });
    });

    test('survives a "restart": new store instance, same id', () async {
      await FilePendingCommandStore(
        store(),
      ).save(_record(sourceType: GrindingSourceType.roll));
      final restored = await FilePendingCommandStore(store()).loadAll();
      expect(restored, hasLength(1));
      final record = restored.single;
      expect(record.clientRequestId, 'c1f0f1b8-9a57-4a0e-9a0e-5d2f7d7d9b10');
      expect(record.orderId, 1042);
      expect(record.command, GrindingCommand.start);
      expect(record.sourceType, GrindingSourceType.roll);
      expect(record.workerOperatorId, 57);
    });

    test('remove clears only that record', () async {
      final pending = FilePendingCommandStore(store());
      await pending.save(_record());
      await pending.save(_record(orderId: 7, id: 'other'));
      await pending.remove(1042, GrindingCommand.start);
      final left = await pending.loadAll();
      expect(left.map((r) => r.orderId), <int>[7]);
    });

    test(
      'corrupt / foreign-version records are skipped, not crashed on',
      () async {
        dir.createSync(recursive: true);
        File('${dir.path}/pending_1_start.json').writeAsStringSync('{not json');
        File(
          '${dir.path}/pending_2_start.json',
        ).writeAsStringSync(jsonEncode(<String, dynamic>{'v': 99}));
        // A record whose content does not match its file name.
        File(
          '${dir.path}/pending_3_start.json',
        ).writeAsStringSync(jsonEncode(_record(orderId: 4).toJson()));
        expect(await FilePendingCommandStore(store()).loadAll(), isEmpty);
      },
    );

    test('the file holds no secret: no token, no PIN, no device key', () async {
      await FilePendingCommandStore(store()).save(_record());
      final text = File(
        '${dir.path}/pending_1042_start.json',
      ).readAsStringSync();
      final json = jsonDecode(text) as Map<String, dynamic>;
      expect(json.keys.toSet(), <String>{
        'v',
        'orderId',
        'orderNumber',
        'identifier',
        'command',
        'clientRequestId',
        'workerOperatorId',
        'workerName',
        'createdAt',
      });
    });
  });
}
