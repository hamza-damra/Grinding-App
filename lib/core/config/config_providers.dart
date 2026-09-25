import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_config.dart';

/// The build's configuration problem, or `null` when the app may talk to its
/// backend. Overridable in tests.
final appConfigProblemProvider = Provider<ConfigProblem?>(
  (ref) => AppConfig.problem,
);
