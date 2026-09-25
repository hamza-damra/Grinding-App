import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lifecycle_resume_notifier.dart';

/// Mounts a single [AppLifecycleListener] for the lifetime of the app and
/// forwards `resumed` events to [LifecycleResumeNotifier]. Mount this
/// widget exactly once near the root of the widget tree.
class AppResumeWatcher extends ConsumerStatefulWidget {
  const AppResumeWatcher({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppResumeWatcher> createState() => _AppResumeWatcherState();
}

class _AppResumeWatcherState extends ConsumerState<AppResumeWatcher> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onResume: () => ref.read(lifecycleResumeProvider.notifier).onResume(),
    );
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
