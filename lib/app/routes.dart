class AppRoutes {
  AppRoutes._();

  static const splash = 'splash';
  static const splashPath = '/';

  /// Shown instead of everything else when the build has no usable backend
  /// configuration (missing / non-HTTPS base URL, missing device key).
  static const config = 'config';
  static const configPath = '/config';

  static const pin = 'pin';
  static const pinPath = '/pin';

  static const home = 'home';
  static const homePath = '/home';

  /// The order card (after a scan, a manual entry, a queue row or a pending
  /// banner). Pushed on top of Home.
  static const order = 'order';
  static const orderPath = '/home/order';

  /// Camera scanner. Pushed on top of Home; pops with a `ScannerResult`.
  static const scan = 'scan';
  static const scanPath = '/home/scan';
}
