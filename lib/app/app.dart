import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/arabic_messages.dart';
import '../core/lifecycle/app_resume_watcher.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/app_snackbar.dart';
import '../features/grinding_auth/presentation/state/session_invalidation_listener.dart';
import '../features/grinding_orders/presentation/state/grinding_resume_coordinator.dart';
import 'router.dart';

class GrindingApp extends ConsumerWidget {
  const GrindingApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    // App-lifetime watchers (Riverpod disposes unwatched notifiers):
    // - bridges session-terminal responses from inside Dio to the auth
    //   cleanup without a provider cycle;
    // - resume: verify the session, re-check the open order, refresh queues.
    ref.watch(sessionInvalidationListenerProvider);
    ref.watch(grindingResumeCoordinatorProvider);
    return AppResumeWatcher(
      child: MaterialApp.router(
        title: ArabicMessages.appTitle,
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(
                  MediaQuery.of(context).textScaler.scale(1).clamp(1.0, 1.2),
                ),
              ),
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
        routerConfig: router,
      ),
    );
  }
}
