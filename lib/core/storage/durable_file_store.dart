import 'dart:async';
import 'dart:io';

/// Crash-safe `name → text` store: one file per record, written atomically.
/// Holds the pending START / COMPLETE idempotency records.
///
/// ## Why not flutter_secure_storage / shared_preferences
///
/// The contract requires the `clientRequestId` to be persisted BEFORE the
/// first request, so a process kill right after sending can never make the
/// next launch mint a second id for the same physical action. Both
/// flutter_secure_storage 9.2.x and 10.x write through
/// `SharedPreferences.Editor.apply()` on Android — an asynchronous disk write:
/// their `write()` future completes while the data may still be only in
/// memory, and a kill at that moment loses it. The legacy shared_preferences
/// plugin happens to use `commit()` today, but that is an implementation
/// detail this safety property must not depend on.
///
/// ## Write protocol ([write])
///
/// 1. write `<name>.json.tmp` with `flush: true` — `RandomAccessFile.flush`
///    is `fsync(2)` on Android/Linux, so the bytes are on the storage device;
/// 2. rename it to `<name>.json` — atomic on POSIX file systems: a reader sees
///    either no record or the complete record, never a torn one;
/// 3. only then does the returned future complete.
///
/// Once the future has completed the record lives in the file system, not in
/// this process, so a process kill cannot lose it. A kill before step 2
/// leaves at most a `.tmp` file; [readAll] deletes those, because the caller
/// was never told the write succeeded and therefore sent nothing under it.
///
/// Residual risk (documented, not a process-kill concern): Dart cannot fsync
/// the directory, so on a sudden POWER loss within the file system's journal
/// commit interval the rename itself may be rolled back.
///
/// All operations are serialized, so a [delete] can never overtake a
/// [write] of the same record.
class DurableFileStore {
  DurableFileStore(this._directory);

  /// Resolves the (app-private) directory. Created on first use.
  final Future<Directory> Function() _directory;

  Directory? _resolved;
  Future<void> _tail = Future<void>.value();

  static const String _suffix = '.json';
  static const String _tmpSuffix = '.json.tmp';
  static final RegExp _validName = RegExp(r'^[A-Za-z0-9_-]+$');

  /// Durably writes [contents] under [name] (see class doc). Throws on any
  /// file-system failure — the caller must then treat the record as NOT
  /// persisted.
  Future<void> write(String name, String contents) => _serialized(() async {
    _checkName(name);
    final dir = await _dir();
    final tmp = File(_path(dir, '$name$_tmpSuffix'));
    final dest = File(_path(dir, '$name$_suffix'));
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename(dest.path);
  });

  /// Every complete record, keyed by name. Leftover `.tmp` files (a write
  /// interrupted before its rename) are deleted. Unreadable files are skipped.
  Future<Map<String, String>> readAll() => _serialized(() async {
    final dir = await _dir();
    final records = <String, String>{};
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final base = entity.uri.pathSegments.last;
      if (base.endsWith(_tmpSuffix)) {
        try {
          await entity.delete();
        } on FileSystemException {
          // Best effort; it is ignored on every read anyway.
        }
        continue;
      }
      if (!base.endsWith(_suffix)) continue;
      final name = base.substring(0, base.length - _suffix.length);
      if (!_validName.hasMatch(name)) continue;
      try {
        records[name] = await entity.readAsString();
      } on FileSystemException {
        continue;
      }
    }
    return records;
  });

  /// Removes the record [name]. A missing record is not an error.
  Future<void> delete(String name) => _serialized(() async {
    _checkName(name);
    final dir = await _dir();
    final file = File(_path(dir, '$name$_suffix'));
    if (await file.exists()) {
      await file.delete();
    }
  });

  Future<T> _serialized<T>(Future<T> Function() op) {
    final result = _tail.then((_) => op());
    // Keep the chain alive regardless of this operation's outcome.
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<Directory> _dir() async {
    final resolved = _resolved;
    if (resolved != null) return resolved;
    final dir = await _directory();
    await dir.create(recursive: true);
    return _resolved = dir;
  }

  static String _path(Directory dir, String file) =>
      '${dir.path}${Platform.pathSeparator}$file';

  static void _checkName(String name) {
    if (!_validName.hasMatch(name)) {
      throw ArgumentError.value(name, 'name', 'invalid record name');
    }
  }
}
