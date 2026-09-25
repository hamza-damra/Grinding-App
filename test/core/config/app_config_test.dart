import 'package:flutter_grinding_app/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig.isSecureTransport', () {
    test('HTTPS is always allowed', () {
      expect(
        AppConfig.isSecureTransport(
          Uri.parse('https://taleeb.me/api'),
          releaseMode: true,
        ),
        isTrue,
      );
      expect(
        AppConfig.isSecureTransport(
          Uri.parse('https://hamzadamra.ddns.net:8443'),
          releaseMode: false,
        ),
        isTrue,
      );
    });

    test('cleartext HTTP to a remote host is refused in every build', () {
      for (final release in <bool>[true, false]) {
        expect(
          AppConfig.isSecureTransport(
            Uri.parse('http://hamzadamra.ddns.net:8080'),
            releaseMode: release,
          ),
          isFalse,
          reason: 'releaseMode=$release',
        );
        expect(
          AppConfig.isSecureTransport(
            Uri.parse('http://10.0.2.2:8080'),
            releaseMode: release,
          ),
          isFalse,
          reason: 'emulator host alias is a real network hop',
        );
      }
    });

    test('HTTP to the device loopback only in non-release builds', () {
      for (final url in <String>[
        'http://localhost:8080',
        'http://127.0.0.1:8080',
        'http://[::1]:8080',
      ]) {
        expect(
          AppConfig.isSecureTransport(Uri.parse(url), releaseMode: false),
          isTrue,
          reason: url,
        );
        expect(
          AppConfig.isSecureTransport(Uri.parse(url), releaseMode: true),
          isFalse,
          reason: url,
        );
      }
    });

    test('HTTP to the lab host only when the lab opt-in is on', () {
      for (final release in <bool>[true, false]) {
        expect(
          AppConfig.isSecureTransport(
            Uri.parse('http://hamzadamra.ddns.net:8080/api'),
            releaseMode: release,
            allowCleartextLab: true,
          ),
          isTrue,
          reason: 'releaseMode=$release',
        );
        expect(
          AppConfig.isSecureTransport(
            Uri.parse('http://hamzadamra.ddns.net:8080/api'),
            releaseMode: release,
            allowCleartextLab: false,
          ),
          isFalse,
          reason: 'releaseMode=$release',
        );
      }
    });

    test('the lab opt-in does not open any other cleartext host', () {
      for (final url in <String>[
        'http://taleeb.me',
        'http://evil.hamzadamra.ddns.net:8080',
        'http://hamzadamra.ddns.net.evil.com:8080',
        'http://10.0.2.2:8080',
        'http://127.0.0.1:8080',
        'ws://hamzadamra.ddns.net:8080',
      ]) {
        expect(
          AppConfig.isSecureTransport(
            Uri.parse(url),
            releaseMode: true,
            allowCleartextLab: true,
          ),
          isFalse,
          reason: url,
        );
      }
    });

    test('the lab opt-in is off unless compiled in', () {
      // The test run passes no ALLOW_CLEARTEXT_LAB define.
      expect(AppConfig.cleartextLabEnabled, isFalse);
    });

    test('other schemes are refused', () {
      expect(
        AppConfig.isSecureTransport(
          Uri.parse('ws://localhost:8080'),
          releaseMode: false,
        ),
        isFalse,
      );
    });
  });

  group('AppConfig.evaluate', () {
    test('a complete HTTPS configuration has no problem', () {
      expect(
        AppConfig.evaluate(
          baseUrl: 'https://taleeb.me',
          deviceKey: 'k',
          releaseMode: true,
        ),
        isNull,
      );
    });

    test('missing base URL / device key are reported', () {
      expect(
        AppConfig.evaluate(baseUrl: '  ', deviceKey: 'k'),
        ConfigProblem.missingBaseUrl,
      );
      expect(
        AppConfig.evaluate(baseUrl: 'https://taleeb.me', deviceKey: ' '),
        ConfigProblem.missingDeviceKey,
      );
    });

    test('an unparseable base URL is reported', () {
      expect(
        AppConfig.evaluate(baseUrl: 'taleeb.me', deviceKey: 'k'),
        ConfigProblem.invalidBaseUrl,
      );
    });

    test('a cleartext remote base URL is refused before the key check', () {
      expect(
        AppConfig.evaluate(
          baseUrl: 'http://hamzadamra.ddns.net:8080',
          deviceKey: '',
          releaseMode: false,
        ),
        ConfigProblem.insecureTransport,
      );
    });

    test('the lab base URL is accepted in release only with the opt-in', () {
      expect(
        AppConfig.evaluate(
          baseUrl: 'http://hamzadamra.ddns.net:8080',
          deviceKey: 'k',
          releaseMode: true,
          allowCleartextLab: true,
        ),
        isNull,
      );
      expect(
        AppConfig.evaluate(
          baseUrl: 'http://hamzadamra.ddns.net:8080',
          deviceKey: 'k',
          releaseMode: true,
          allowCleartextLab: false,
        ),
        ConfigProblem.insecureTransport,
      );
    });

    test('loopback HTTP (adb reverse) is accepted only outside release', () {
      expect(
        AppConfig.evaluate(
          baseUrl: 'http://127.0.0.1:8080',
          deviceKey: 'k',
          releaseMode: false,
        ),
        isNull,
      );
      expect(
        AppConfig.evaluate(
          baseUrl: 'http://127.0.0.1:8080',
          deviceKey: 'k',
          releaseMode: true,
        ),
        ConfigProblem.insecureTransport,
      );
    });
  });

  test('no device key is compiled into a build without DEVICE_KEY', () {
    // The test run passes no --dart-define: the key must be empty, never a
    // source default.
    expect(AppConfig.deviceKey, isEmpty);
  });

  test('command retry policy matches contract §9 (3 automatic retries)', () {
    expect(AppConfig.commandAutoRetryCount, 3);
    expect(AppConfig.commandRetryBackoff, hasLength(3));
  });
}
