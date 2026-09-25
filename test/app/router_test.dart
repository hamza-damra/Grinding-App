import 'package:flutter_grinding_app/app/router.dart';
import 'package:flutter_grinding_app/app/routes.dart';
import 'package:flutter_test/flutter_test.dart';

String? _redirect(
  String location, {
  bool configMissing = false,
  bool resolving = false,
  bool authenticated = false,
}) => resolveAuthRedirect(
  location: location,
  configMissing: configMissing,
  authResolving: resolving,
  isAuthenticated: authenticated,
);

void main() {
  test('missing configuration wins over everything', () {
    for (final location in <String>[
      AppRoutes.splashPath,
      AppRoutes.pinPath,
      AppRoutes.homePath,
      AppRoutes.orderPath,
    ]) {
      expect(
        _redirect(location, configMissing: true, authenticated: true),
        AppRoutes.configPath,
      );
    }
    expect(_redirect(AppRoutes.configPath, configMissing: true), isNull);
  });

  test('splash holds while the first auth state resolves', () {
    expect(
      _redirect(AppRoutes.homePath, resolving: true),
      AppRoutes.splashPath,
    );
    expect(_redirect(AppRoutes.splashPath, resolving: true), isNull);
  });

  test('unauthenticated → PIN from anywhere', () {
    expect(_redirect(AppRoutes.splashPath), AppRoutes.pinPath);
    expect(_redirect(AppRoutes.orderPath), AppRoutes.pinPath);
    expect(_redirect(AppRoutes.scanPath), AppRoutes.pinPath);
    expect(_redirect(AppRoutes.pinPath), isNull);
  });

  test('authenticated → Home and its children only', () {
    expect(
      _redirect(AppRoutes.pinPath, authenticated: true),
      AppRoutes.homePath,
    );
    expect(
      _redirect(AppRoutes.splashPath, authenticated: true),
      AppRoutes.homePath,
    );
    expect(_redirect(AppRoutes.homePath, authenticated: true), isNull);
    expect(_redirect(AppRoutes.orderPath, authenticated: true), isNull);
    expect(_redirect(AppRoutes.scanPath, authenticated: true), isNull);
  });
}
