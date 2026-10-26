/// Columns every synchronisable table carries. They let the local SQLite
/// database act as the source of truth today and sync with a server later
/// (see `lib/sync`).
class RecordMeta {
  const RecordMeta({
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;

  factory RecordMeta.fromMap(Map<String, Object?> m) => RecordMeta(
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['created_at'] as int?) ?? 0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch((m['updated_at'] as int?) ?? 0),
        createdBy: m['created_by'] as String?,
        updatedBy: m['updated_by'] as String?,
      );
}

abstract class Entity {
  String get id;
  RecordMeta? get meta;

  /// Domain columns only; meta columns are managed by the repository.
  Map<String, Object?> toMap();

  /// One line description used in the audit log.
  String describe();
}

int asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
