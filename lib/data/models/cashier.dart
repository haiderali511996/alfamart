import 'entity.dart';

class Cashier implements Entity {
  Cashier({
    required this.id,
    required this.name,
    this.phone = '',
    this.counterId,
    this.isActive = true,
    this.meta,
  });

  @override
  final String id;
  final String name;
  final String phone;

  /// Usual counter of this cashier (they can still be put on any counter).
  final String? counterId;
  final bool isActive;
  @override
  final RecordMeta? meta;

  factory Cashier.fromMap(Map<String, Object?> m) => Cashier(
        id: m['id'] as String,
        name: m['name'] as String,
        phone: (m['phone'] as String?) ?? '',
        counterId: m['counter_id'] as String?,
        isActive: asInt(m['is_active']) == 1,
        meta: RecordMeta.fromMap(m),
      );

  @override
  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'counter_id': counterId,
        'is_active': isActive ? 1 : 0,
      };

  @override
  String describe() => 'Cashier $name';
}
