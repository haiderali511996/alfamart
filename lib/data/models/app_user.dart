import '../../core/enums.dart';
import 'entity.dart';

class AppUser implements Entity {
  AppUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.passwordHash,
    required this.salt,
    required this.iterations,
    this.isActive = true,
    this.failedAttempts = 0,
    this.lockedUntil,
    this.lastLogin,
    this.meta,
  });

  @override
  final String id;
  final String username;
  final String fullName;
  final UserRole role;
  final String passwordHash;
  final String salt;
  final int iterations;
  final bool isActive;
  final int failedAttempts;
  final DateTime? lockedUntil;
  final DateTime? lastLogin;
  @override
  final RecordMeta? meta;

  bool get isAdmin => role == UserRole.admin;

  factory AppUser.fromMap(Map<String, Object?> m) => AppUser(
        id: m['id'] as String,
        username: m['username'] as String,
        fullName: m['full_name'] as String,
        role: UserRole.parse(m['role'] as String),
        passwordHash: m['password_hash'] as String,
        salt: m['salt'] as String,
        iterations: asInt(m['iterations']),
        isActive: asInt(m['is_active']) == 1,
        failedAttempts: asInt(m['failed_attempts']),
        lockedUntil: m['locked_until'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(asInt(m['locked_until'])),
        lastLogin: m['last_login'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(asInt(m['last_login'])),
        meta: RecordMeta.fromMap(m),
      );

  @override
  Map<String, Object?> toMap() => {
        'id': id,
        'username': username,
        'full_name': fullName,
        'role': role.name,
        'password_hash': passwordHash,
        'salt': salt,
        'iterations': iterations,
        'is_active': isActive ? 1 : 0,
        'failed_attempts': failedAttempts,
        'locked_until': lockedUntil?.millisecondsSinceEpoch,
        'last_login': lastLogin?.millisecondsSinceEpoch,
      };

  AppUser copyWith({
    String? fullName,
    UserRole? role,
    String? passwordHash,
    String? salt,
    int? iterations,
    bool? isActive,
    int? failedAttempts,
    DateTime? lockedUntil,
    bool clearLock = false,
    DateTime? lastLogin,
  }) =>
      AppUser(
        id: id,
        username: username,
        fullName: fullName ?? this.fullName,
        role: role ?? this.role,
        passwordHash: passwordHash ?? this.passwordHash,
        salt: salt ?? this.salt,
        iterations: iterations ?? this.iterations,
        isActive: isActive ?? this.isActive,
        failedAttempts: failedAttempts ?? this.failedAttempts,
        lockedUntil: clearLock ? null : (lockedUntil ?? this.lockedUntil),
        lastLogin: lastLogin ?? this.lastLogin,
        meta: meta,
      );

  @override
  String describe() => 'User $username (${role.label})${isActive ? '' : ' [inactive]'}';
}
