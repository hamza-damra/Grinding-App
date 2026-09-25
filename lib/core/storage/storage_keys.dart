class SecureStorageKeys {
  SecureStorageKeys._();

  /// `X-Session-Token` from `POST /auth/pin`. Secret — secure storage only.
  static const String sessionToken = 'grinding_worker_session_token';
}

class PrefsKeys {
  PrefsKeys._();

  // Non-secret cache of the logged-in worker, used to keep the worker on the
  // home screen when `/sessions/me` cannot be reached on launch (transient
  // network failure). Never used to decide that a session is valid.
  static const String lastWorkerId = 'grinding_last_worker_id';
  static const String lastWorkerName = 'grinding_last_worker_name';
  static const String lastWorkerExpiresAt = 'grinding_last_worker_expires_at';
}

class DurableStoreDirs {
  DurableStoreDirs._();

  /// Sub-directory (of the app-private support directory) holding one file
  /// per pending START / COMPLETE idempotency record.
  static const String pendingCommands = 'grinding_pending_commands';
}
