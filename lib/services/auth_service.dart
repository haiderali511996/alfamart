import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/enums.dart';
import '../core/security.dart';
import '../data/models/app_user.dart';
import '../data/repositories/repository.dart';
import 'app_services.dart';
import 'biometric_service.dart';

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Login state for the app. Only admins and managers have accounts;
/// cashiers are tracked as records, they do not log in.
class AuthService extends ChangeNotifier {
  AuthService(this.services, this.biometrics);

  final AppServices services;
  final BiometricService biometrics;

  static const maxFailedAttempts = 5;
  static const lockDuration = Duration(minutes: 5);

  AppUser? _current;
  bool? _hasUsers;

  AppUser? get currentUser => _current;
  bool get isLoggedIn => _current != null;
  bool get isAdmin => _current?.isAdmin ?? false;
  bool? get hasUsers => _hasUsers;

  Actor get actor => _current == null ? Actor.system : Actor(_current!.id, _current!.username);

  Future<void> init() async {
    final users = await services.users.query(limit: 1);
    _hasUsers = users.isNotEmpty;
    notifyListeners();
  }

  Future<AppUser?> _findByUsername(String username) async {
    final list = await services.users.query(where: 'username = ? COLLATE NOCASE', args: [username.trim()]);
    return list.isEmpty ? null : list.first;
  }

  Future<AppUser> createUser({
    required String username,
    required String fullName,
    required String password,
    required UserRole role,
  }) async {
    final name = username.trim();
    if (!RegExp(r'^[A-Za-z0-9_.]{3,30}$').hasMatch(name)) {
      throw AuthException('Username: 3-30 letters, numbers, dot or underscore');
    }
    if (await _findByUsername(name) != null) {
      throw AuthException('Username "$name" already exists');
    }
    final strength = PasswordHasher.validateStrength(password);
    if (strength != null) throw AuthException(strength);
    final salt = PasswordHasher.newSalt();
    final hash = await compute(_hashIsolate, [password, salt]);
    final user = AppUser(
      id: const Uuid().v4(),
      username: name,
      fullName: fullName.trim(),
      role: role,
      passwordHash: hash,
      salt: salt,
      iterations: PasswordHasher.defaultIterations,
    );
    await services.users.save(user, _current == null ? Actor(user.id, user.username) : actor);
    _hasUsers = true;
    notifyListeners();
    return user;
  }

  Future<void> login(String username, String password) async {
    final user = await _findByUsername(username);
    if (user == null) throw AuthException('Invalid username or password');
    if (!user.isActive) throw AuthException('This account is disabled. Contact the admin.');
    final now = DateTime.now();
    if (user.lockedUntil != null && user.lockedUntil!.isAfter(now)) {
      final mins = user.lockedUntil!.difference(now).inMinutes + 1;
      throw AuthException('Too many wrong attempts. Try again in $mins min.');
    }
    final ok = await compute(_verifyIsolate, [password, user.salt, user.passwordHash, user.iterations]);
    if (!ok) {
      final attempts = user.failedAttempts + 1;
      final locked = attempts >= maxFailedAttempts;
      await services.users.save(
        user.copyWith(
          failedAttempts: locked ? 0 : attempts,
          lockedUntil: locked ? now.add(lockDuration) : null,
        ),
        Actor(user.id, user.username),
        audit: locked,
      );
      throw AuthException(locked
          ? 'Too many wrong attempts. Account locked for ${lockDuration.inMinutes} minutes.'
          : 'Invalid username or password (${maxFailedAttempts - attempts} attempts left)');
    }
    await _completeLogin(user, 'login');
  }

  Future<void> loginWithBiometrics() async {
    final userId = await biometrics.linkedUserId();
    if (userId == null) throw AuthException('Fingerprint login is not set up on this device');
    final user = await services.users.getById(userId);
    if (user == null || !user.isActive) {
      await biometrics.unlink();
      throw AuthException('Fingerprint login is no longer valid. Please log in with password.');
    }
    final ok = await biometrics.authenticate('Scan your fingerprint to log in as ${user.fullName}');
    if (!ok) throw AuthException('Fingerprint not recognised');
    await _completeLogin(user, 'login (fingerprint)');
  }

  Future<void> _completeLogin(AppUser user, String how) async {
    final updated = user.copyWith(failedAttempts: 0, clearLock: true, lastLogin: DateTime.now());
    await services.users.save(updated, Actor(user.id, user.username), audit: false);
    await Repository.writeAudit(services.database.db, Actor(user.id, user.username), how, 'Session',
        user.id, '${user.username} logged in');
    _current = updated;
    notifyListeners();
  }

  Future<void> logout({String reason = 'logout'}) async {
    if (_current != null) {
      await Repository.writeAudit(
          services.database.db, actor, reason, 'Session', _current!.id, '${_current!.username} logged out');
    }
    _current = null;
    notifyListeners();
  }

  Future<void> changePassword(String oldPw, String newPw) async {
    final user = _current!;
    final fresh = (await services.users.getById(user.id))!;
    final ok = await compute(_verifyIsolate, [oldPw, fresh.salt, fresh.passwordHash, fresh.iterations]);
    if (!ok) throw AuthException('Current password is wrong');
    await setPassword(fresh, newPw);
  }

  /// Admin reset or self change.
  Future<void> setPassword(AppUser user, String newPw) async {
    final strength = PasswordHasher.validateStrength(newPw);
    if (strength != null) throw AuthException(strength);
    final salt = PasswordHasher.newSalt();
    final hash = await compute(_hashIsolate, [newPw, salt]);
    final updated = user.copyWith(
      passwordHash: hash,
      salt: salt,
      iterations: PasswordHasher.defaultIterations,
      failedAttempts: 0,
      clearLock: true,
    );
    await services.users.save(updated, actor);
    if (_current?.id == user.id) _current = updated;
    notifyListeners();
  }

  Future<void> updateUser(AppUser user) async {
    if (_current?.id == user.id && (!user.isActive || user.role != UserRole.admin) && _current!.isAdmin) {
      final admins = await services.users.query(where: "role = 'admin' AND is_active = 1");
      if (admins.length <= 1) throw AuthException('At least one active admin is required');
    }
    if (!user.isActive && await biometrics.linkedUserId() == user.id) await biometrics.unlink();
    await services.users.save(user, actor);
    if (_current?.id == user.id) _current = user;
    notifyListeners();
  }
}

String _hashIsolate(List<Object> a) => PasswordHasher.hash(a[0] as String, a[1] as String);

bool _verifyIsolate(List<Object> a) =>
    PasswordHasher.verify(a[0] as String, a[1] as String, a[2] as String, a[3] as int);
