import '../../core/enums.dart';
import '../../core/money.dart';
import 'entity.dart';

class Purchase implements Entity {
  Purchase({
    required this.id,
    required this.date,
    required this.amount,
    this.supplier = '',
    this.invoiceNo = '',
    this.method = PaymentMethod.cash,
    this.description = '',
    this.meta,
  });

  @override
  final String id;
  final String date;
  final int amount;
  final String supplier;
  final String invoiceNo;
  final PaymentMethod method;
  final String description;
  @override
  final RecordMeta? meta;

  factory Purchase.fromMap(Map<String, Object?> m) => Purchase(
        id: m['id'] as String,
        date: m['date'] as String,
        amount: asInt(m['amount']),
        supplier: (m['supplier'] as String?) ?? '',
        invoiceNo: (m['invoice_no'] as String?) ?? '',
        method: PaymentMethod.parse(m['payment_method'] as String?),
        description: (m['description'] as String?) ?? '',
        meta: RecordMeta.fromMap(m),
      );

  @override
  Map<String, Object?> toMap() => {
        'id': id,
        'date': date,
        'amount': amount,
        'supplier': supplier,
        'invoice_no': invoiceNo,
        'payment_method': method.name,
        'description': description,
      };

  @override
  String describe() => 'Purchase $date ${Money.format(amount)} from "$supplier" via ${method.label}';
}
