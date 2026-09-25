import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_grinding_app/app/app.dart';
import 'package:flutter_grinding_app/core/api/api_client.dart';
import 'package:flutter_grinding_app/core/api/session_invalidation_signal.dart';
import 'package:flutter_grinding_app/core/auth/auth_session.dart';
import 'package:flutter_grinding_app/core/config/config_providers.dart';
import 'package:flutter_grinding_app/core/storage/durable_file_store.dart';
import 'package:flutter_grinding_app/core/storage/secure_token_store.dart';
import 'package:flutter_grinding_app/core/storage/storage_keys.dart';
import 'package:flutter_grinding_app/features/grinding_orders/data/file_pending_command_store.dart';
import 'package:flutter_grinding_app/features/grinding_orders/presentation/state/order_command_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test/support/fake_grinding_backend.dart';
import '../../test/support/test_harness.dart';

/// On-device wiring: the REAL flutter_secure_storage token store, the REAL
/// SharedPreferences and the REAL durable pending-command file store; only
/// the network is replaced (fake backend adapter behind the real Dio chain)
/// and the command backoff is shortened.
List<Override> deviceOverrides(
  FakeGrindingBackend backend, {
  String Function()? ids,
}) => <Override>[
  appConfigProblemProvider.overrideWithValue(null),
  dioProvider.overrideWith(
    (ref) => buildTestDio(
      session: ref.watch(authSessionProvider),
      signal: ref.watch(sessionInvalidationSignalProvider),
      adapter: backend,
    ),
  ),
  commandRetryBackoffProvider.overrideWithValue(const <Duration>[
    Duration(milliseconds: 20),
    Duration(milliseconds: 40),
    Duration(milliseconds: 80),
  ]),
  if (ids != null) clientRequestIdGeneratorProvider.overrideWithValue(ids),
];

/// The directory the production `pendingCommandStoreProvider` uses.
Future<Directory> pendingDirectory() async {
  final base = await getApplicationSupportDirectory();
  return Directory(
    '${base.path}${Platform.pathSeparator}${DurableStoreDirs.pendingCommands}',
  );
}

/// A fresh store instance over the real directory (= what a new process
/// reads).
Future<FilePendingCommandStore> realPendingStore() async {
  final dir = await pendingDirectory();
  return FilePendingCommandStore(DurableFileStore(() async => dir));
}

/// Wipes the session token, preferences and pending records.
Future<void> resetDeviceState() async {
  await FlutterSecureTokenStore().clearSessionToken();
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  final dir = await pendingDirectory();
  if (dir.existsSync()) dir.deleteSync(recursive: true);
}

Future<void> pumpDeviceApp(
  WidgetTester tester,
  FakeGrindingBackend backend, {
  String Function()? ids,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: deviceOverrides(backend, ids: ids),
      child: const GrindingApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// "Restart" inside the same process: the whole provider graph is disposed
/// and rebuilt; everything durable is re-read from the device storage.
Future<void> restartInProcess(
  WidgetTester tester,
  FakeGrindingBackend backend, {
  String Function()? ids,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await pumpDeviceApp(tester, backend, ids: ids);
}

/// Pumps until [finder] matches (real time on a device).
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder');
}
