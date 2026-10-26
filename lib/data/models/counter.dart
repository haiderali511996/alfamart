import 'entity.dart';

class Counter implements Entity {
  Counter({required this.id, required this.name, this.sortOrder = 0, this.isActive = true, this.meta});

  @override
  final String id;
  final String name;
  final int sortOrder;
  final bool isActive;
  @override
  final RecordMeta? meta;

  factory Counter.fromMap(Map<String, Object?> m) => Counter(
        id: m['id'] as String,
        name: m['name'] as String,
        sortOrder: asInt(m['sort_order']),
        isActive: asInt(m['is_active']) == 1,
        meta: RecordMeta.fromMap(m),
      );

  @override
  Map<String, Object?> toMap() =>
      {'id': id, 'name': name, 'sort_order': sortOrder, 'is_active': isActive ? 1 : 0};

  @override
  String describe() => 'Counter $name';
}
