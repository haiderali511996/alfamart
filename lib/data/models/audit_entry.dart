class AuditEntry {
  AuditEntry({
    required this.id,
    required this.timestamp,
    required this.userName,
    required this.action,
    required this.entity,
    required this.entityId,
    required this.summary,
    this.before,
    this.after,
  });

  final int id;
  final DateTime timestamp;
  final String userName;
  final String action;
  final String entity;
  final String entityId;
  final String summary;
  final String? before;
  final String? after;

  factory AuditEntry.fromMap(Map<String, Object?> m) => AuditEntry(
        id: m['id'] as int,
        timestamp: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
        userName: (m['user_name'] as String?) ?? '',
        action: m['action'] as String,
        entity: m['entity'] as String,
        entityId: (m['entity_id'] as String?) ?? '',
        summary: (m['summary'] as String?) ?? '',
        before: m['before_json'] as String?,
        after: m['after_json'] as String?,
      );
}
