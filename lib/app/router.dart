import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/config_providers.dart';
import '../core/errors/arabic_messages.dart';
import '../core/theme/colors.dart';
import '../features/grinding_auth/presentation/screens/pin_screen.dart';
import '../features/grinding_auth/presentation/state/grinding_auth_controller.dart';
import '../features/grinding_auth/presentation/state/grinding_auth_state.dart';
import '../features/grinding_orders/presentation/screens/order_screen.dart';
import '../features/home/presentation/screens/home_screen.dart';
import '../features/scanner/presentation/scanner_screen.dart';
import 'config_missing_screen.dart';
import 'routes.dart';
import 'splash_screen.dart';

/// Adapter that lets go_router re-run its redirect when the auth state
/// changes (Operator App `_RouterAuthListenable`). Not a state container.
class _RouterAuthListenable extends ChangeNotifier {
  _RouterAuthListenable(this._ref) {
    _authSub = _ref.listen<AsyncValue<GrindingAuthState>>(
      grindingAuthControllerProvider,
      (previous, next) => notifyListeners(),
      fireImmediately: false,
    );
  }

  final Ref _ref;
  late final ProviderSubscription<AsyncValue<GrindingAuthState>> _authSub;

  @override
  void dispose() {
    _authSub.close();
    super.dispose();
  }
}

/// Pure redirect resolution, extracted so the precedence rules can be
/// unit-tested without the router.
@visibleForTesting
String? resolveAuthRedirect({
  required String location,
  required bool configMissing,
  required bool authResolving,
  required bool isAuthenticated,
}) {
  if (configMissing) {
    return location == AppRoutes.configPath ? null : AppRoutes.configPath;
  }
  if (authResolving) {
    return location == AppRoutes.splashPath ? null : AppRoutes.splashPath;
  }
  if (!isAuthenticated) {
    return location == AppRoutes.pinPath ? null : AppRoutes.pinPath;
  }
  if (location == AppRoutes.homePath ||
      location.startsWith('${AppRoutes.homePath}/')) {
    return null;
  }
  return AppRoutes.homePath;
}

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'rootNavigator');

final appRouterProvider = Provider<GoRouter>((ref) {
  final listenable = _RouterAuthListenable(ref);
  ref.onDispose(listenable.dispose);

  return GoRouter(
    initialLocation: AppRoutes.splashPath,
    navigatorKey: rootNavigatorKey,
    debugLogDiagnostics: false,
    refreshListenable: listenable,
    redirect: (context, state) {
      final authAsync = ref.read(grindingAuthControllerProvider);
      return resolveAuthRedirect(
        location: state.matchedLocation,
        configMissing: ref.read(appConfigProblemProvider) != null,
        // Hold on the splash only while the FIRST value resolves; a login in
        // progress keeps its previous value and must not bounce to splash.
        authResolving: authAsync.isLoading && !authAsync.hasValue,
        isAuthenticated: authAsync.valueOrNull is GrindingAuthAuthenticated,
      );
    },
    routes: [
      GoRoute(
        name: AppRoutes.splash,
        path: AppRoutes.splashPath,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        name: AppRoutes.config,
        path: AppRoutes.configPath,
        builder: (context, state) => const ConfigMissingScreen(),
      ),
      GoRoute(
        name: AppRoutes.pin,
        path: AppRoutes.pinPath,
        builder: (context, state) => const PinScreen(),
      ),
      GoRoute(
        name: AppRoutes.home,
        path: AppRoutes.homePath,
        builder: (context, state) => const HomeScreen(),
        routes: [
          GoRoute(
            name: AppRoutes.order,
            path: 'order',
            builder: (context, state) => const OrderScreen(),
          ),
          GoRoute(
            name: AppRoutes.scan,
            path: 'scan',
            builder: (context, state) => const ScannerScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => const Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Center(child: Text(ArabicMessages.genericError)),
    ),
  );
});
