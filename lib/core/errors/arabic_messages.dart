import 'app_failure.dart';
import 'error_codes.dart';

/// Single source of truth for worker-facing Arabic copy. Every string marked
/// "contract" is copied verbatim from `docs/GRINDING_APP_BACKEND_CONTRACT.md`
/// §5/§9/§10 (a unit test compares them against the contract file byte for
/// byte). Backend `error.message` is English and technical and is NEVER shown:
/// an unknown code falls back to [genericError], not to the backend text.
class ArabicMessages {
  ArabicMessages._();

  // ── Screens and actions (contract §10) ─────────────────────────────────
  static const String appTitle = 'الجاروشة';
  static const String pinScreenTitle = 'تسجيل الدخول — الجاروشة';
  static const String loginButton = 'دخول';
  static const String logout = 'تسجيل الخروج';
  static const String scanButton = 'مسح رقم';
  static const String manualEntryLabel = 'رقم الرول أو الطبلية (12 خانة)';
  static const String checkButton = 'تحقق';
  static const String readyList = 'جاهز للجرش';
  static const String inGrindingList = 'قيد الجرش';
  static const String startButton = 'بدء الجرش';
  static const String completeButton = 'تأكيد انتهاء الجرش';
  static const String startConfirmAction = 'بدء';
  static const String completeConfirmTitle = 'هل تم جرش هذه المادة فعليًا؟';
  static const String completeConfirmAction = 'نعم، تم الجرش';
  static const String cancel = 'إلغاء';
  static const String startSuccess = 'بدأ الجرش.';
  static const String completeSuccess = 'تم الجرش فعليًا';
  static const String directScrapTag = 'جرش مباشر';
  static const String sourceRoll = 'رول';
  static const String sourcePallet = 'طبلية';
  static const String selectionTitle = 'الرقم موجود لرول وطبلية';
  static const String selectionText = 'اختر المادة التي تريد جرشها';
  static const String emptyList = 'لا توجد أوامر';

  /// Contract §10: «بدء جرش {رقم الأمر}؟». [orderNumber] should already be
  /// wrapped in a bidi isolate by the caller (`Bidi.isolate`).
  static String startConfirmTitle(String orderNumber) =>
      'بدء جرش $orderNumber؟';

  // ── Status copy (contract §4.2 table, §9, §11) ─────────────────────────
  static const String pendingApprovalMessage =
      'بانتظار موافقة المدير — لا يمكن بدء الجرش بعد.';
  static const String pendingApprovalLabel = 'بانتظار موافقة المدير';
  static const String notEligibleLabel = 'غير مؤهل للجرش';
  static const String legacyCompleted =
      'تم الجرش قبل تفعيل نظام تتبع الجرش الجديد';
  static const String completedLabel = 'تم الجرش';

  /// Local fallbacks for a missing `statusLabel` on statuses the contract
  /// gives no Arabic label for. Listed for owner sign-off.
  static const String rejectedLabel = 'مرفوض';
  static const String cancelledLabel = 'ملغى';

  // ── Errors (contract §10) ──────────────────────────────────────────────
  static const String pinInvalid = 'الرمز السري غير صحيح.';
  static const String workerNotAllowed =
      'هذا الموظف غير مخوّل باستخدام تطبيق الجاروشة.';
  static const String sessionRequired = 'يلزم تسجيل الدخول في تطبيق الجاروشة.';
  static const String sessionInvalid =
      'جلسة تطبيق الجاروشة غير صالحة. سجّل الدخول مجدداً.';
  static const String sessionExpired =
      'انتهت جلسة تطبيق الجاروشة. سجّل الدخول مجدداً.';
  static const String identifierInvalid =
      'يجب أن يتكون الرقم من 12 خانة بالضبط.';
  static const String sourceNotFound = 'لا يوجد رول أو طبلية بهذا الرقم.';
  static const String identifierAmbiguous =
      'الرقم موجود لرول وطبلية، أي واحدة تريد جرشها؟';
  static const String approvalRequired =
      'أمر الجرش ما زال بانتظار موافقة المدير.';
  static const String orderNotReady = 'أمر الجرش غير جاهز للجرش.';
  static const String orderNotInProgress = 'لم يبدأ جرش هذا الأمر بعد.';
  static const String orderAlreadyCompleted = 'تم جرش هذا الأمر مسبقاً.';
  static const String sourceStateChanged =
      'تغيّرت حالة الرول أو الطبلية ولم يُنفَّذ الإجراء.';
  static const String orderNotFound = 'أمر الجرش غير موجود.';
  static const String idempotencyKeyReused =
      'تم استخدام مفتاح الطلب هذا لإجراء مختلف.';

  /// Contract §10 "Unknown error".
  static const String genericError = 'تعذر تنفيذ العملية. حاول مرة أخرى.';

  /// Contract §10 "Network lost".
  static const String networkLost = 'انقطع الاتصال — أعد المحاولة';

  // ── Non-contract copy (reported for owner sign-off) ────────────────────

  /// Operator App wording for `VALIDATION_ERROR`.
  static const String validationError =
      'بيانات الطلب غير صالحة. تأكد من الحقول المطلوبة.';
  static const String backingUserInvalid =
      'حساب الموظف غير مهيأ. تواصل مع المسؤول.';

  /// Contract §4.1 "device not authorized: contact admin".
  static const String deviceNotAuthorized =
      'هذا الجهاز غير مخوّل. تواصل مع المسؤول.';

  /// Operator App wording (shared Taleeb copy).
  static const String appNotConfigured =
      'إعدادات التطبيق غير مكتملة، يرجى التواصل مع المسؤول';
  static const String reconnecting = 'جاري تحديث الاتصال بالخادم...';

  /// Home banner for a START/COMPLETE whose outcome is unknown (app killed,
  /// connection lost, session ended mid-request). Never auto-sent.
  static const String pendingCommandTitle = 'إجراء سابق لم يتأكد';
  static String pendingStartBody(String orderNumber) =>
      'طلب «بدء الجرش» للأمر $orderNumber لم يصل تأكيده من الخادم.';
  static String pendingCompleteBody(String orderNumber) =>
      'طلب «تأكيد انتهاء الجرش» للأمر $orderNumber لم يصل تأكيده من الخادم.';
  static String pendingOtherWorker(String workerName) =>
      'أرسله الموظف: $workerName';
  static const String pendingOpenOrder = 'فتح الأمر';

  /// The saved request no longer matches the order's current state; tapping
  /// sends the SAME request id once so the server can confirm (replayed) or
  /// definitively reject it.
  static const String verifyPreviousRequest = 'تحقق من الطلب السابق';

  static const String logoutConfirmTitle = 'تسجيل الخروج؟';
  static const String logoutConfirmBody =
      'سيتم إنهاء جلستك على هذا الجهاز. الأوامر قيد الجرش تبقى كما هي.';
  static const String logoutBlockedInFlight =
      'لا يمكن تسجيل الخروج أثناء تنفيذ إجراء. انتظر حتى ينتهي.';

  /// A number shared by a roll and a pallet was answered with ONE item
  /// (`AUTO_RESOLVED`): the card names the other item so a worker holding
  /// it notices before acting. [otherLabel] is «رول» / «طبلية».
  static String sharedNumberNotice(String otherLabel, String? otherStatus) =>
      otherStatus == null
      ? 'الرقم نفسه موجود أيضاً ل$otherLabel.'
      : 'الرقم نفسه موجود أيضاً ل$otherLabel ($otherStatus).';

  /// Start / complete confirmation on a shared number. [itemDefinite] is
  /// «الرول» / «الطبلية».
  static String sharedNumberConfirmWarning(String itemDefinite) =>
      'الرقم نفسه موجود لرول وطبلية — تأكد أن المادة التي أمامك هي $itemDefinite.';
  static const String sourceRollDefinite = 'الرول';
  static const String sourcePalletDefinite = 'الطبلية';

  static const String sessionEndsAt = 'تنتهي الجلسة';
  static const String retry = 'إعادة المحاولة';
  static const String ok = 'حسناً';
  static const String enterManually = 'إدخال الرقم يدويًا';
  static const String cameraStarting = 'جاري تشغيل الكاميرا…';
  static const String cameraPermissionRequired =
      'يلزم إذن الكاميرا لمسح الرقم.';
  static const String allowCamera = 'السماح بالكاميرا';
  static const String cameraPermissionBlocked =
      'إذن الكاميرا مرفوض. فعّله من إعدادات التطبيق.';
  static const String openAppSettings = 'فتح الإعدادات';
  static const String cameraUnavailable = 'تعذر تشغيل الكاميرا.';
  static const String noCameraOnDevice = 'لا توجد كاميرا متاحة على هذا الجهاز.';
  static const String scanHint = 'وجّه الكاميرا نحو ملصق الرول أو الطبلية';

  /// Maps any [AppFailure] to worker-facing Arabic copy.
  static String forFailure(AppFailure failure) {
    return switch (failure) {
      NetworkFailure() => networkLost,
      TimeoutFailure() => networkLost,
      CancelledFailure() => genericError,
      ServerFailure() => genericError,
      ApiFailure(:final code) => forCode(code),
      AppNotConfiguredFailure() => appNotConfigured,
      DeviceNotAuthorizedFailure() => deviceNotAuthorized,
      SessionExpiredFailure() => sessionRequired,
      UnknownFailure() => genericError,
    };
  }

  /// `error.code` → Arabic. Unknown codes → [genericError], never the
  /// backend's English `message`.
  static String forCode(String code) => _codeToMessage[code] ?? genericError;

  static const Map<String, String> _codeToMessage = <String, String>{
    ErrorCodes.operatorPinInvalid: pinInvalid,
    ErrorCodes.workerNotAllowed: workerNotAllowed,
    ErrorCodes.sessionRequired: sessionRequired,
    ErrorCodes.sessionInvalid: sessionInvalid,
    ErrorCodes.sessionExpired: sessionExpired,
    ErrorCodes.identifierInvalid: identifierInvalid,
    ErrorCodes.sourceNotFound: sourceNotFound,
    ErrorCodes.identifierAmbiguous: identifierAmbiguous,
    ErrorCodes.approvalRequired: approvalRequired,
    ErrorCodes.orderNotReady: orderNotReady,
    ErrorCodes.orderNotInProgress: orderNotInProgress,
    ErrorCodes.orderAlreadyCompleted: orderAlreadyCompleted,
    ErrorCodes.sourceStateChanged: sourceStateChanged,
    ErrorCodes.orderNotFound: orderNotFound,
    ErrorCodes.idempotencyKeyReused: idempotencyKeyReused,
    ErrorCodes.validationError: validationError,
    ErrorCodes.operatorBackingUserInvalid: backingUserInvalid,
  };
}
