import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_grinding_app/core/errors/arabic_messages.dart';
import 'package:flutter_grinding_app/features/scanner/data/camera_permissions.dart';
import 'package:flutter_grinding_app/features/scanner/presentation/scanner_result.dart';
import 'package:flutter_grinding_app/features/scanner/presentation/scanner_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../support/fake_scanner_platform.dart';
import '../../support/finders.dart';

/// Hosts the REAL [ScannerScreen] behind a go_router push (as in the app)
/// and records what it pops with.
class _ScannerHost {
  _ScannerHost(this.permissions);

  final FakeCameraPermissions permissions;
  final List<ScannerResult?> results = <ScannerResult?>[];

  late final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const ValueKey('open-scanner'),
              onPressed: () async =>
                  results.add(await context.push<ScannerResult>('/scan')),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/scan',
        builder: (context, state) => const ScannerScreen(),
      ),
    ],
  );

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          cameraPermissionsProvider.overrideWithValue(permissions),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  Future<void> openScanner(WidgetTester tester) async {
    await tester.tap(byKey('open-scanner'));
    await _frames(tester);
  }
}

/// The camera-starting spinner never settles: pump a bounded number of frames.
Future<void> _frames(WidgetTester tester, [int count = 10]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _lifecycle(WidgetTester tester, AppLifecycleState state) async {
  tester.binding.handleAppLifecycleStateChanged(state);
  await _frames(tester, 4);
}

void main() {
  late MobileScannerPlatform original;
  late FakeScannerPlatform platform;

  setUp(() {
    original = MobileScannerPlatform.instance;
    platform = FakeScannerPlatform();
    MobileScannerPlatform.instance = platform;
  });

  tearDown(() async {
    MobileScannerPlatform.instance = original;
    await platform.close();
  });

  Future<_ScannerHost> open(
    WidgetTester tester, {
    CameraPermissionState permission = CameraPermissionState.granted,
    CameraPermissionState? answer,
  }) async {
    final host = _ScannerHost(
      FakeCameraPermissions(permission, answer: answer),
    );
    await host.pump(tester);
    await host.openScanner(tester);
    return host;
  }

  group('camera permission', () {
    testWidgets('granted → the camera starts: preview, frame, hint', (
      tester,
    ) async {
      final host = await open(tester);
      expect(host.permissions.requests, 0);
      expect(platform.startCalls, 1);
      expect(platform.cameraHeld, isTrue);
      expect(byKey('fake-camera-preview'), findsOneWidget);
      expect(byKey('scanner-reticle'), findsOneWidget);
      expect(find.text(ArabicMessages.scanHint), findsOneWidget);
      expect(byKey('camera-failed'), findsNothing);
      expect(byKey('scanner-manual-entry'), findsOneWidget);
    });

    testWidgets('not yet asked → asked once, granted → the camera starts', (
      tester,
    ) async {
      final host = await open(
        tester,
        permission: CameraPermissionState.denied,
        answer: CameraPermissionState.granted,
      );
      expect(host.permissions.requests, 1);
      expect(platform.cameraHeld, isTrue);
      expect(byKey('scanner-reticle'), findsOneWidget);
    });

    testWidgets(
      'denied → concise panel with «السماح بالكاميرا»; manual entry stays; '
      'asking again and granting starts the camera',
      (tester) async {
        final host = await open(
          tester,
          permission: CameraPermissionState.denied,
        );
        expect(byKey('camera-permission-denied'), findsOneWidget);
        expect(
          find.text(ArabicMessages.cameraPermissionRequired),
          findsOneWidget,
        );
        expect(byKey('scanner-manual-entry'), findsOneWidget);
        expect(platform.startCalls, 0);
        expect(byKey('scanner-reticle'), findsNothing);

        host.permissions.answer = CameraPermissionState.granted;
        await tester.tap(byKey('camera-allow'));
        await _frames(tester);
        expect(host.permissions.requests, 2);
        expect(byKey('camera-permission-denied'), findsNothing);
        expect(platform.cameraHeld, isTrue);
      },
    );

    testWidgets(
      'permanently denied → «فتح الإعدادات»; back from the settings with the '
      'permission granted, the camera starts by itself',
      (tester) async {
        final host = await open(
          tester,
          permission: CameraPermissionState.permanentlyDenied,
        );
        expect(byKey('camera-permission-blocked'), findsOneWidget);
        expect(
          find.text(ArabicMessages.cameraPermissionBlocked),
          findsOneWidget,
        );
        await tester.tap(byKey('camera-open-settings'));
        await _frames(tester, 2);
        expect(host.permissions.settingsOpened, 1);

        await _lifecycle(tester, AppLifecycleState.inactive);
        host.permissions.current = CameraPermissionState.granted;
        await _lifecycle(tester, AppLifecycleState.resumed);
        expect(byKey('camera-permission-blocked'), findsNothing);
        expect(platform.cameraHeld, isTrue);
        // Never asked again through a dialog the system would not show.
        expect(host.permissions.requests, 0);
      },
    );
  });

  group('camera start', () {
    testWidgets(
      'a failed start → «تعذر تشغيل الكاميرا.» with one retry — never '
      'restarted in a loop',
      (tester) async {
        platform.startFailures.add(
          const MobileScannerException(
            errorCode: MobileScannerErrorCode.genericError,
          ),
        );
        await open(tester);
        expect(byKey('camera-failed'), findsOneWidget);
        expect(find.text(ArabicMessages.cameraUnavailable), findsOneWidget);
        expect(byKey('scanner-manual-entry'), findsOneWidget);
        expect(byKey('scanner-reticle'), findsNothing);
        expect(platform.startCalls, 1);

        // Lifecycle changes do not retry a camera that never ran.
        await _lifecycle(tester, AppLifecycleState.inactive);
        await _lifecycle(tester, AppLifecycleState.resumed);
        expect(platform.startCalls, 1);

        await tester.tap(byKey('camera-retry'));
        await _frames(tester);
        expect(platform.startCalls, 2);
        expect(byKey('camera-failed'), findsNothing);
        expect(byKey('scanner-reticle'), findsOneWidget);
      },
    );

    testWidgets('no camera on the device → message, no retry', (tester) async {
      platform.startFailures.add(
        const MobileScannerException(
          errorCode: MobileScannerErrorCode.unsupported,
        ),
      );
      await open(tester);
      expect(find.text(ArabicMessages.noCameraOnDevice), findsOneWidget);
      expect(byKey('camera-retry'), findsNothing);
      expect(byKey('scanner-manual-entry'), findsOneWidget);
    });

    testWidgets('a camera an earlier screen left bound is released first', (
      tester,
    ) async {
      platform.textureId = 99; // leaked by a previous scanner
      await open(tester);
      expect(platform.releases, 1);
      expect(platform.startCalls, 1);
      expect(byKey('camera-failed'), findsNothing);
      expect(platform.cameraHeld, isTrue);
    });

    testWidgets(
      'leaving while the camera is still starting never leaves it bound; '
      'the next scanner starts normally',
      (tester) async {
        platform.startGate = Completer<void>();
        final host = await open(tester);
        expect(byKey('camera-starting'), findsOneWidget);

        await tester.tap(byKey('scanner-manual-entry'));
        await _frames(tester);
        expect(host.results, <Matcher>[isA<ManualEntryRequested>()]);

        platform.startGate!.complete();
        platform.startGate = null;
        await tester.pumpAndSettle();
        expect(platform.cameraHeld, isFalse);

        await host.openScanner(tester);
        expect(byKey('camera-failed'), findsNothing);
        expect(platform.cameraHeld, isTrue);
        expect(byKey('scanner-reticle'), findsOneWidget);
      },
    );

    testWidgets('app inactive → camera stopped; resumed → restarted', (
      tester,
    ) async {
      await open(tester);
      await _lifecycle(tester, AppLifecycleState.inactive);
      expect(platform.cameraHeld, isFalse);
      await _lifecycle(tester, AppLifecycleState.hidden);
      await _lifecycle(tester, AppLifecycleState.paused);
      await _lifecycle(tester, AppLifecycleState.hidden);
      await _lifecycle(tester, AppLifecycleState.inactive);
      await _lifecycle(tester, AppLifecycleState.resumed);
      expect(platform.cameraHeld, isTrue);
      expect(platform.startCalls, 2);
      expect(byKey('scanner-reticle'), findsOneWidget);
    });
  });

  group('scanning', () {
    testWidgets(
      'the first valid code stops the camera and pops once; a second code is '
      'ignored',
      (tester) async {
        final host = await open(tester);
        platform.emit(<String>['001000000255']);
        platform.emit(<String>['120000004428']);
        await _frames(tester);
        expect(host.results, hasLength(1));
        expect(
          host.results.single,
          isA<ScannedIdentifier>().having(
            (r) => r.identifier,
            'identifier',
            '001000000255',
          ),
        );
        expect(platform.cameraHeld, isFalse);
      },
    );

    testWidgets('an invalid code shows the 12-digit message and keeps going', (
      tester,
    ) async {
      final host = await open(tester);
      platform.emit(<String>['ABC-123']);
      await _frames(tester, 2);
      expect(byKey('scanner-invalid'), findsOneWidget);
      expect(find.text(ArabicMessages.identifierInvalid), findsOneWidget);
      expect(host.results, isEmpty);
      expect(platform.cameraHeld, isTrue);

      platform.emit(<String>[' 001000000255 ']);
      await _frames(tester);
      expect(
        host.results.single,
        isA<ScannedIdentifier>().having(
          (r) => r.identifier,
          'identifier',
          '001000000255',
        ),
      );
      await tester.pump(const Duration(seconds: 4)); // message timer
    });

    testWidgets('«إدخال الرقم يدويًا» pops ManualEntryRequested', (
      tester,
    ) async {
      final host = await open(tester);
      await tester.tap(byKey('scanner-manual-entry'));
      await tester.pumpAndSettle(); // the route transition, then dispose
      expect(host.results, <Matcher>[isA<ManualEntryRequested>()]);
      expect(platform.cameraHeld, isFalse);
    });
  });
}
