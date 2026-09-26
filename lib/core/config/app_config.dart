import 'package:flutter/foundation.dart';

/// Application environment. Selected at compile time via
/// `--dart-define=APP_ENV=production|staging|dev`. Unrecognised values fall
/// back to [AppEnvironment.debug] in debug builds and
/// [AppEnvironment.production] in release builds.
enum AppEnvironment { production, staging, debug }

/// Why the build cannot talk to a backend. Surfaced only as the generic
/// Arabic config-missing screen; the enum name is a debug diagnostic and never
/// carries the configured values themselves.
enum ConfigProblem {
  missingBaseUrl,
  invalidBaseUrl,
  missingDeviceKey,

  /// The base URL is not HTTPS. The PIN, the device key and the session token
  /// must never travel over cleartext HTTP, so such a build refuses to send
  /// anything. Debug/profile builds may use plain HTTP to the device loopback
  /// only (`adb reverse`), which never leaves the device. The single
  /// exception is the opt-in lab host (see [AppConfig.cleartextLabHost]).
  insecureTransport,
}

class AppConfig {
  AppConfig._();

  /// Production base URL, used only by production builds that do not pass
  /// `API_BASE_URL`. Non-production builds have NO default: a developer build
  /// must name its backend explicitly, so it can never silently reach
  /// production or a cleartext host.
  static const String _defaultProductionBaseUrl = 'https://taleeb.me';

  static const String _rawAppEnv = String.fromEnvironment('APP_ENV');

  static AppEnvironment get environment {
    switch (_rawAppEnv.toLowerCase()) {
      case 'production':
      case 'prod':
        return AppEnvironment.production;
      case 'staging':
      case 'stage':
        return AppEnvironment.staging;
      case 'debug':
      case 'dev':
        return AppEnvironment.debug;
      default:
        return kReleaseMode ? AppEnvironment.production : AppEnvironment.debug;
    }
  }

  static bool get isProduction => environment == AppEnvironment.production;

  static const String _rawBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    final explicit = _rawBaseUrl.trim();
    if (explicit.isNotEmpty) return explicit;
    return isProduction ? _defaultProductionBaseUrl : '';
  }

  /// The shared factory device key. Supplied per installation with
  /// `--dart-define=DEVICE_KEY=...` (or `--dart-define-from-file`). There is
  /// deliberately NO default in source: a build without a key shows the
  /// config-missing screen and sends nothing.
  static const String deviceKey = String.fromEnvironment('DEVICE_KEY');

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 30);

  /// Best-effort `POST /auth/logout` must never hold the worker on the home
  /// screen: the local session is cleared whatever the server answers.
  static const Duration logoutTimeout = Duration(seconds: 5);

  /// Automatic retries for read-only requests (`GET`s and the read-only
  /// `POST /check`) that fail with a transient transport error.
  static const int idempotentRetryCount = 1;
  static const List<Duration> idempotentRetryBackoff = <Duration>[
    Duration(milliseconds: 350),
    Duration(milliseconds: 900),
  ];

  /// Contract §9: a START / COMPLETE that fails at the transport level is
  /// retried automatically up to 3 times with the SAME `clientRequestId`.
  static const int commandAutoRetryCount = 3;
  static const List<Duration> commandRetryBackoff = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  /// Biometric handoff §4.3: the server holds an attempt-status long-poll
  /// for up to 25 s, so its receive timeout must be at least 35 s.
  static const Duration biometricStatusReceiveTimeout = Duration(seconds: 40);

  /// Biometric handoff §8: pause between failed attempt-status polls (1 s,
  /// 2 s, 4 s, then at most 10 s). Polling goes on until the server's 410.
  static const List<Duration> biometricPollBackoff = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 10),
  ];

  /// Grace period `AsyncStatusView` waits — performing one silent auto-retry —
  /// before escalating a settled technical failure to the blocking dialog.
  static const Duration connectionErrorGrace = Duration(milliseconds: 600);

  static const String apiPrefix = '/api/v1/grinding-app';

  static const String appNameAr = 'الجاروشة';

  static const String missingConfigMessageAr =
      'إعدادات التطبيق غير مكتملة، يرجى التواصل مع المسؤول';

  static bool isLoopbackHost(String host) {
    final h = host.toLowerCase();
    return h == 'localhost' || h == '127.0.0.1' || h == '::1' || h == '[::1]';
  }

  /// Whether a request to [uri] may carry credentials. HTTPS always; plain
  /// HTTP only to the device loopback and never in a release build.
  ///
  /// The one exception is [cleartextLabHost] when [cleartextLabEnabled] (or
  /// [allowCleartextLab] in tests): plain HTTP to that exact host, in any
  /// build mode.
  static bool isSecureTransport(
    Uri uri, {
    bool releaseMode = kReleaseMode,
    bool? allowCleartextLab,
  }) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https') return true;
    if (scheme == 'http' && !releaseMode && isLoopbackHost(uri.host)) {
      return true;
    }
    if (scheme == 'http' &&
        (allowCleartextLab ?? cleartextLabEnabled) &&
        uri.host.toLowerCase() == cleartextLabHost) {
      return true;
    }
    return false;
  }

  /// The owner's plain-HTTP lab backend (`http://hamzadamra.ddns.net:8080`).
  /// Cleartext to it was approved by the owner on 2026-09-22 for lab builds
  /// only: such a build must use disposable test credentials and a test
  /// device key, never a real worker PIN or the factory device key. Android's
  /// `network_security_config_lab.xml` names the same host.
  static const String cleartextLabHost = 'hamzadamra.ddns.net';

  static const bool _allowCleartextLab = bool.fromEnvironment(
    'ALLOW_CLEARTEXT_LAB',
  );

  /// Whether this build may use plain HTTP to [cleartextLabHost]: requires
  /// `--dart-define=ALLOW_CLEARTEXT_LAB=true` AND a non-production `APP_ENV`,
  /// so a production build can never talk cleartext.
  static bool get cleartextLabEnabled => _allowCleartextLab && !isProduction;

  /// Pure validation of a configuration, exposed for tests.
  static ConfigProblem? evaluate({
    required String baseUrl,
    required String deviceKey,
    bool releaseMode = kReleaseMode,
    bool? allowCleartextLab,
  }) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) return ConfigProblem.missingBaseUrl;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return ConfigProblem.invalidBaseUrl;
    }
    if (!isSecureTransport(
      uri,
      releaseMode: releaseMode,
      allowCleartextLab: allowCleartextLab,
    )) {
      return ConfigProblem.insecureTransport;
    }
    if (deviceKey.trim().isEmpty) return ConfigProblem.missingDeviceKey;
    return null;
  }

  static ConfigProblem? get problem =>
      evaluate(baseUrl: baseUrl, deviceKey: deviceKey);

  static bool get isConfigured => problem == null;
}
