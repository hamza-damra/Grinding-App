import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Riverpod notifier that publishes a debounced "the app just resumed"
/// signal as a monotonically-increasing tick counter. Controllers that
/// want to refresh on resume `ref.listen` to this provider and call their
/// own refresh once per tick.
///
/// The debounce prevents rapid resume events (e.g. when Android emits
/// `inactive → resumed → inactive → resumed` while pulling down the
/// notification shade) from triggering several refreshes in a row.
class LifecycleResumeNotifier extends Notifier<int> {
  LifecycleResumeNotifier({this.debounce = const Duration(milliseconds: 500)});

  final Duration debounce;
  Timer? _debounceTimer;

  @override
  int build() {
    ref.onDispose(() => _debounceTimer?.cancel());
    return 0;
  }

  /// Called by the lifecycle observer when the app moves to `resumed`.
  /// The resulting tick fires after [debounce] elapses without another
  /// resume event.
  void onResume() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      // Increment so listeners see prev != next and fire exactly once.
      state = state + 1;
    });
  }
}

final lifecycleResumeProvider = NotifierProvider<LifecycleResumeNotifier, int>(
  LifecycleResumeNotifier.new,
);
