/// Aggregates the cross-feature Riverpod providers (Operator App parity).
/// Individual feature modules expose their own providers locally; this file
/// is for shared infrastructure (Dio, storage, prefs, session).
library;

export '../core/api/api_client.dart' show dioProvider;
export '../core/auth/auth_session.dart' show authSessionProvider;
export '../core/storage/prefs_store.dart'
    show prefsStoreProvider, sharedPreferencesProvider;
export '../core/storage/secure_token_store.dart' show secureTokenStoreProvider;
