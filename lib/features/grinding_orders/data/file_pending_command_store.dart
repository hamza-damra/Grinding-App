import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/storage/durable_file_store.dart';
import '../../../core/storage/storage_keys.dart';
import '../domain/entities/pending_command.dart';
import '../domain/repositories/pending_command_store.dart';
import '../domain/value_objects/grinding_command.dart';

/// [PendingCommandStore] on top of [DurableFileStore]: one atomically written,
/// fsync'd file per `orderId + command` in the app-private support directory
/// (excluded from backups by the manifest rules). See [DurableFileStore] for
/// why this is not shared_preferences / flutter_secure_storage.
class FilePendingCommandStore implements PendingCommandStore {
  FilePendingCommandStore(this._files);

  final DurableFileStore _files;

  @override
  Future<List<PendingCommand>> loadAll() async {
    final raw = await _files.readAll();
    final commands = <PendingCommand>[];
    for (final entry in raw.entries) {
      PendingCommand? parsed;
      try {
        parsed = PendingCommand.tryFromJson(jsonDecode(entry.value));
      } on FormatException {
        parsed = null;
      }
      if (parsed == null || parsed.key != entry.key) {
        if (kDebugMode) {
          debugPrint('[PendingCommandStore] unreadable record ${entry.key}');
        }
        continue;
      }
      commands.add(parsed);
    }
    commands.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return commands;
  }

  @override
  Future<void> save(PendingCommand command) =>
      _files.write(command.key, jsonEncode(command.toJson()));

  @override
  Future<void> remove(int orderId, GrindingCommand command) =>
      _files.delete(PendingCommand.keyFor(orderId, command));
}

final pendingCommandStoreProvider = Provider<PendingCommandStore>((ref) {
  return FilePendingCommandStore(
    DurableFileStore(() async {
      final base = await getApplicationSupportDirectory();
      return Directory(
        '${base.path}${Platform.pathSeparator}'
        '${DurableStoreDirs.pendingCommands}',
      );
    }),
  );
});
