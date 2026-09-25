/// Field labels of the order card and queue rows. Not in the contract's §10
/// table (it lists what to show, not the labels) — reported for owner
/// sign-off.
class OrderCopy {
  OrderCopy._();

  static const String source = 'المصدر';
  static const String number = 'الرقم';
  static const String material = 'المادة';
  static const String expectedWeight = 'الوزن المتوقع';
  static const String quantity = 'الكمية';
  static const String line = 'الخط';
  static const String product = 'المنتج';
  static const String startedBy = 'بدأ الجرش';
  static const String startedAt = 'وقت البدء';
  static const String completedBy = 'أكمل الجرش';
  static const String completedAt = 'وقت الانتهاء';
  static const String orderTitleFallback = 'أمر الجرش';
}
