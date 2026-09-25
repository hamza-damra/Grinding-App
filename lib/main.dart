import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'app/app.dart';
import 'core/config/app_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Load the IANA database before any UI renders a backend timestamp, so
  // FactoryTime can resolve Asia/Hebron (bundled asset, no I/O).
  tzdata.initializeTimeZones();
  if (kDebugMode) {
    // Startup diagnostic: never logs the device key or any token — only
    // which configuration problem (if any) blocks the app.
    debugPrint(
      '[Startup] env=${AppConfig.environment.name} '
      'configProblem=${AppConfig.problem?.name ?? 'none'}',
    );
  }
  runApp(const ProviderScope(child: GrindingApp()));
}
