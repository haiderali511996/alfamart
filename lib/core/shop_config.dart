/// Fixed shop rules.
class ShopConfig {
  ShopConfig._();

  /// Counters run the same hours every day.
  static const dutyStart = '07:00';
  static const dutyEnd = '20:00';
  static const dutyLabel = '7:00 AM – 8:00 PM';

  /// Every counter starts the day with Rs 19,000 in the drawer.
  static const openingCash = 19000 * 100;
}
