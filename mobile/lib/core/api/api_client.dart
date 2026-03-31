import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../providers/server_url_provider.dart';

const _storage = FlutterSecureStorage();

/// Base Dio instance with JWT auth interceptor.
/// Rebuilt whenever the server URL changes.
final dioProvider = Provider<Dio>((ref) {
  final baseUrl = ref.watch(serverUrlProvider);
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
    },
  ));

  dio.interceptors.add(_AuthInterceptor(dio));
  return dio;
});

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._dio);
  final Dio _dio;

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
    if (err.response?.statusCode == 401) {
      final refreshed = await _tryRefreshToken();
      if (refreshed) {
        final token = await _storage.read(key: 'access_token');
        err.requestOptions.headers['Authorization'] = 'Bearer $token';
        final response = await _dio.fetch(err.requestOptions);
        return handler.resolve(response);
      }
      await _storage.deleteAll();
    }
    handler.next(err);
  }

  Future<bool> _tryRefreshToken() async {
    try {
      final refresh = await _storage.read(key: 'refresh_token');
      if (refresh == null) return false;
      final resp = await _dio.post(
        '/api/v1/auth/token/refresh/',
        data: {'refresh': refresh},
      );
      await _storage.write(key: 'access_token', value: resp.data['access']);
      return true;
    } catch (_) {
      return false;
    }
  }
}
