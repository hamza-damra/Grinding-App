import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'storage_keys.dart';

/// Non-secret identity of the last logged-in worker (Operator App's
/// `LastOperator`). Never contains the token or the PIN.
class LastWorker {
  const LastWorker({
    required this.operatorId,
    required this.name,
    this.expiresAt,
  });

  final int operatorId;
  final String name;

  /// Raw ISO-8601 instant as sent by the backend; display only. The app never
  /// decides session validity from the local clock — the server does.
  final String? expiresAt;
}

/// Non-critical preferences. Safety-critical state (pending START / COMPLETE
/// idempotency records) is NOT stored here — see `DurableFileStore`.
abstract class PrefsStore {
  Future<void> writeLastWorker(LastWorker worker);
  Future<LastWorker?> readLastWorker();
  Future<void> clearLastWorker();
}

class SharedPreferencesPrefsStore implements PrefsStore {
  SharedPreferencesPrefsStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<void> writeLastWorker(LastWorker worker) async {
    await _prefs.setInt(PrefsKeys.lastWorkerId, worker.operatorId);
    await _prefs.setString(PrefsKeys.lastWorkerName, worker.name);
    final expiresAt = worker.expiresAt;
    if (expiresAt == null) {
      await _prefs.remove(PrefsKeys.lastWorkerExpiresAt);
    } else {
      await _prefs.setString(PrefsKeys.lastWorkerExpiresAt, expiresAt);
    }
  }

  @override
  Future<LastWorker?> readLastWorker() async {
    final id = _prefs.getInt(PrefsKeys.lastWorkerId);
    final name = _prefs.getString(PrefsKeys.lastWorkerName);
    if (id == null || name == null) return null;
    return LastWorker(
      operatorId: id,
      name: name,
      expiresAt: _prefs.getString(PrefsKeys.lastWorkerExpiresAt),
    );
  }

  @override
  Future<void> clearLastWorker() async {
    await _prefs.remove(PrefsKeys.lastWorkerId);
    await _prefs.remove(PrefsKeys.lastWorkerName);
    await _prefs.remove(PrefsKeys.lastWorkerExpiresAt);
  }
}

/// In-memory prefs used in tests.
class InMemoryPrefsStore implements PrefsStore {
  InMemoryPrefsStore({this._lastWorker});

  LastWorker? _lastWorker;

  @override
  Future<void> writeLastWorker(LastWorker worker) async {
    _lastWorker = worker;
  }

  @override
  Future<LastWorker?> readLastWorker() async => _lastWorker;

  @override
  Future<void> clearLastWorker() async {
    _lastWorker = null;
  }
}

final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) {
  return SharedPreferences.getInstance();
});

final prefsStoreProvider = FutureProvider<PrefsStore>((ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return SharedPreferencesPrefsStore(prefs);
});
