import '../../core/money.dart';
import 'entity.dart';

/// Cash handed to a purchaser up front, e.g. Rs 2 lac before the day starts.
class PurchaserAdvance implements Entity {
  PurchaserAdvance({
    required this.id,
    required this.date,
    required this.purchaserName,
    required this.amount,
    this.notes = '',
    this.meta,
  });

  @override
  final String id;
  final String date;
  final String purchaserName;
  final int amount;
  final String notes;
  @override
  final RecordMeta? meta;

  factory PurchaserAdvance.fromMap(Map<String, Object?> m) => PurchaserAdvance(
    id: m['id'] as String,
    date: m['date'] as String,
    purchaserName: (m['purchaser_name'] as String?) ?? '',
    amount: asInt(m['amount']),
    notes: (m['notes'] as String?) ?? '',
    meta: RecordMeta.fromMap(m),
  );

  @override
  Map<String, Object?> toMap() => {
    'id': id,
    'date': date,
    'purchaser_name': purchaserName,
    'amount': amount,
    'notes': notes,
  };

  @override
  String describe() => 'Advance to purchaser "$purchaserName" $date ${Money.format(amount)}';
}
