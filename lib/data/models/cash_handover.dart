import '../../core/money.dart';
import 'entity.dart';

/// Cash a purchaser takes out of a cashier's drawer (e.g. to buy stock).
class CashHandover implements Entity {
  CashHandover({
    required this.id,
    required this.date,
    required this.counterId,
    required this.cashierId,
    required this.purchaserName,
    required this.amount,
    this.time = '',
    this.purpose = '',
    this.meta,
  });

  @override
  final String id;
  final String date;
  final String time;
  final String counterId;
  final String cashierId;
  final String purchaserName;
  final int amount;
  final String purpose;
  @override
  final RecordMeta? meta;

  factory CashHandover.fromMap(Map<String, Object?> m) => CashHandover(
        id: m['id'] as String,
        date: m['date'] as String,
        time: (m['time'] as String?) ?? '',
        counterId: m['counter_id'] as String,
        cashierId: m['cashier_id'] as String,
        purchaserName: (m['purchaser_name'] as String?) ?? '',
        amount: asInt(m['amount']),
        purpose: (m['purpose'] as String?) ?? '',
        meta: RecordMeta.fromMap(m),
      );

  @override
  Map<String, Object?> toMap() => {
        'id': id,
        'date': date,
        'time': time,
        'counter_id': counterId,
        'cashier_id': cashierId,
        'purchaser_name': purchaserName,
        'amount': amount,
        'purpose': purpose,
      };

  @override
  String describe() => 'Cash to purchaser "$purchaserName" $date ${Money.format(amount)}';
}
