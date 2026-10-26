import '../../core/enums.dart';
import '../../core/money.dart';
import 'entity.dart';

class Expense implements Entity {
  Expense({
    required this.id,
    required this.date,
    required this.amount,
    required this.category,
    this.counterId,
    this.cashierId,
    this.method = PaymentMethod.cash,
    this.description = '',
    this.meta,
  });

  @override
  final String id;
  final String date;
  final int amount;
  final String category;

  /// Null counter = general shop expense not paid from a counter.
  final String? counterId;
  final String? cashierId;
  final PaymentMethod method;
  final String description;
  @override
  final RecordMeta? meta;

  /// Only cash expenses paid from a counter reduce that drawer's cash.
  bool get reducesDrawer => counterId != null && method == PaymentMethod.cash;

  factory Expense.fromMap(Map<String, Object?> m) => Expense(
        id: m['id'] as String,
        date: m['date'] as String,
        amount: asInt(m['amount']),
        category: (m['category'] as String?) ?? 'Other',
        counterId: m['counter_id'] as String?,
        cashierId: m['cashier_id'] as String?,
        method: PaymentMethod.parse(m['payment_method'] as String?),
        description: (m['description'] as String?) ?? '',
        meta: RecordMeta.fromMap(m),
      );

  @override
  Map<String, Object?> toMap() => {
        'id': id,
        'date': date,
        'amount': amount,
        'category': category,
        'counter_id': counterId,
        'cashier_id': cashierId,
        'payment_method': method.name,
        'description': description,
      };

  @override
  String describe() => 'Expense $date ${Money.format(amount)} [$category] via ${method.label}';
}
