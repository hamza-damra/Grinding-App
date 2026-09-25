class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;

  /// Responsive card padding — mirrors the sibling Roll Production app's
  /// scheme so SectionCard renders the same on phone vs. tablet.
  static const double cardPadMobile = 16;
  static const double cardPadTablet = 24;
}

class AppRadius {
  AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;
}

class AppSizes {
  AppSizes._();

  static const double buttonHeight = 56;

  /// The order screen's single physical-command button (START / COMPLETE):
  /// taller than a regular action so it is easy to hit with work gloves.
  static const double commandButtonHeight = 72;

  /// The home screen's «مسح رقم» button — the primary shop-floor action.
  static const double scanButtonHeight = 88;
  static const double inputHeight = 56;
  static const double cardPadding = 16;
  static const double iconSm = 18;
  static const double iconMd = 24;
  static const double iconLg = 32;
}

class AppBorders {
  AppBorders._();

  static const double thin = 1;
  static const double thick = 1.5;
}
