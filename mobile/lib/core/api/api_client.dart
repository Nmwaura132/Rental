import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../navigation_key.dart';
import '../providers/server_url_provider.dart';

const _storage = FlutterSecureStorage();

final publicDioProvider = Provider<Dio>((ref) {
  final baseUrl = ref.watch(serverUrlProvider);
  return Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
    ),
  );
});

/// Base Dio instance with JWT auth interceptor.
/// Rebuilt whenever the server URL changes.
final dioProvider = Provider<Dio>((ref) {
  final baseUrl = ref.watch(serverUrlProvider);
  
  // Dedicated Dio for refreshing (no auth interceptor to avoid circular dependency)
  final refreshDio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'Content-Type': 'application/json',
    },
  ));

  dio.interceptors.add(_AuthInterceptor(dio: dio, refreshDio: refreshDio));
  return dio;
});

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor({required Dio dio, required Dio refreshDio}) 
      : _dio = dio, _refreshDio = refreshDio;
      
  final Dio _dio;
  final Dio _refreshDio;

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _storage.read(key: 'access_token');
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    
    // RECURSION GUARD: If the request that failed WAS the refresh request,
    // don't try to refresh again. Just logout.
    if (err.requestOptions.path.contains('/auth/token/refresh/')) {
      await _storage.deleteAll();
      _navigateToLogin();
      return handler.next(err);
    }

    if (err.response?.statusCode == 401) {
      final refreshed = await _tryRefreshToken();
      if (refreshed) {
        try {
          final token = await _storage.read(key: 'access_token');
          err.requestOptions.headers['Authorization'] = 'Bearer $token';
          
          // Use the original dio to retry the request
          final response = await _dio.fetch(err.requestOptions);
          return handler.resolve(response);
        } on DioException catch (retryErr) {
          // Retry failed - likely token still invalid or network issue during retry
          if (retryErr.response?.statusCode == 401) {
             await _storage.deleteAll();
             _navigateToLogin();
          }
          return handler.reject(retryErr);
        }
      }
      
      // Refresh failed (e.g. refresh token expired)
      await _storage.deleteAll();
      _navigateToLogin();
    }
    handler.next(err);
  }

  void _navigateToLogin() {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      ctx.go('/login');
    }
  }

  Future<bool> _tryRefreshToken() async {
    try {
      final refresh = await _storage.read(key: 'refresh_token');
      if (refresh == null) return false;
      
      // Use the CLEAN refreshDio to avoid interceptor recursion
      final resp = await _refreshDio.post(
        '/api/v1/auth/token/refresh/',
        data: {'refresh': refresh},
      );
      await _storage.write(key: 'access_token', value: resp.data['access']);
      // WHY: backend has ROTATE_REFRESH_TOKENS=True + BLACKLIST_AFTER_ROTATION=True.
      // Each refresh issues a new refresh token and blacklists the old one. Without
      // persisting the rotated token here, the next 401 finds a blacklisted refresh
      // and force-logs the user out.
      final newRefresh = resp.data['refresh'];
      if (newRefresh != null) {
        await _storage.write(key: 'refresh_token', value: newRefresh);
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
