import 'package:intl/intl.dart';

/// All money is stored as integer paisa (1 Rupee = 100 paisa) so that
/// totals never suffer from floating point rounding errors.
class Money {
  Money._();

  static const symbol = 'Rs';
  static final _fmt = NumberFormat('#,##0.##', 'en_US');
  static final _fmtFixed = NumberFormat('#,##0.00', 'en_US');
  static final _compact = NumberFormat.compact(locale: 'en_US');

  /// Parses user input like "1,250.50" into paisa. Returns null when invalid.
  static int? tryParse(String? input) {
    if (input == null) return null;
    final cleaned = input.replaceAll(',', '').replaceAll(' ', '').trim();
    if (cleaned.isEmpty) return 0;
    final match = RegExp(r'^\d+(\.\d{0,2})?$').firstMatch(cleaned);
    if (match == null) return null;
    final parts = cleaned.split('.');
    final rupees = int.parse(parts[0]);
    var paisa = 0;
    if (parts.length > 1 && parts[1].isNotEmpty) {
      paisa = int.parse(parts[1].padRight(2, '0'));
    }
    return rupees * 100 + paisa;
  }

  static String format(int paisa, {bool withSymbol = true}) {
    final value = _fmt.format(paisa / 100);
    return withSymbol ? '$symbol $value' : value;
  }

  static String formatFixed(int paisa) => _fmtFixed.format(paisa / 100);

  static String compact(int paisa) => '$symbol ${_compact.format(paisa / 100)}';

  /// Value for pre-filling a text field (no grouping separators).
  static String toInput(int paisa) {
    if (paisa == 0) return '';
    if (paisa % 100 == 0) return (paisa ~/ 100).toString();
    return (paisa / 100).toStringAsFixed(2);
  }

  static double toDouble(int paisa) => paisa / 100;
}
