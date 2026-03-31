import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage();

/// Reads the authenticated user's role ('landlord', 'caretaker', 'tenant')
/// from secure storage. Returns null if not logged in.
///
/// Use [ref.watch(userRoleProvider).valueOrNull] in widgets — returns null
/// while loading (safe default: full tabs shown; route guard blocks access).
/// Invalidate after login/logout so the new role is picked up immediately.
final userRoleProvider = FutureProvider.autoDispose<String?>((ref) async {
  return _storage.read(key: 'user_role');
});
