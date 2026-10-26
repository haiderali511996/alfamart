import '../../core/money.dart';
import 'entity.dart';

/// One cashier's duty on one counter: the sales they took, split by payment
/// method, plus the opening float and the cash counted at hand-over so the
/// drawer can be reconciled.
class ShiftSale implements Entity {
  ShiftSale({
    required this.id,
    required this.date,
    required this.counterId,
    required this.cashierId,
    this.startTime = '',
    this.endTime = '',
    this.openingCash = 0,
    this.cash = 0,
    this.pos = 0,
    this.online = 0,
    this.jazzcash = 0,
    this.closingCash,
    this.notes = '',
    this.meta,
  });

  @override
  final String id;
  final String date;
  final String counterId;
  final String cashierId;
  final String startTime;
  final String endTime;
  final int openingCash;
  final int cash;
  final int pos;
  final int online;
  final int jazzcash;

  /// Physically counted cash at the end of the shift (null = not counted).
  final int? closingCash;
  final String notes;
  @override
  final RecordMeta? meta;

  int get totalSale => cash + pos + online + jazzcash;

  factory ShiftSale.fromMap(Map<String, Object?> m) => ShiftSale(
        id: m['id'] as String,
        date: m['date'] as String,
        counterId: m['counter_id'] as String,
        cashierId: m['cashier_id'] as String,
        startTime: (m['start_time'] as String?) ?? '',
        endTime: (m['end_time'] as String?) ?? '',
        openingCash: asInt(m['opening_cash']),
        cash: asInt(m['cash']),
        pos: asInt(m['pos']),
        online: asInt(m['online']),
        jazzcash: asInt(m['jazzcash']),
        closingCash: m['closing_cash'] == null ? null : asInt(m['closing_cash']),
        notes: (m['notes'] as String?) ?? '',
        meta: RecordMeta.fromMap(m),
      );

  @override
  Map<String, Object?> toMap() => {
        'id': id,
        'date': date,
        'counter_id': counterId,
        'cashier_id': cashierId,
        'start_time': startTime,
        'end_time': endTime,
        'opening_cash': openingCash,
        'cash': cash,
        'pos': pos,
        'online': online,
        'jazzcash': jazzcash,
        'closing_cash': closingCash,
        'notes': notes,
      };

  @override
  String describe() => 'Shift sale $date total ${Money.format(totalSale)} '
      '(cash ${Money.format(cash)}, POS ${Money.format(pos)}, online ${Money.format(online)}, '
      'JazzCash ${Money.format(jazzcash)})';
}
