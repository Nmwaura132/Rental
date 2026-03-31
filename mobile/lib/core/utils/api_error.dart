import 'package:dio/dio.dart';

/// Extracts a user-friendly error message from a Dio exception or any error.
String apiError(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      // DRF returns { "detail": "..." } or { "field": ["error"] }
      if (data['detail'] != null) return data['detail'].toString();
      final first = data.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
      if (first is String) return first;
    }
    if (data is String && data.isNotEmpty) return data;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Request timed out. Check your connection.';
      case DioExceptionType.connectionError:
        return 'Cannot reach server. Check your connection.';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 401) return 'Session expired. Please log in again.';
        if (code == 403) return 'You do not have permission to do this.';
        if (code == 404) return 'Resource not found.';
        if (code != null && code >= 500) return 'Server error. Please try again later.';
        return 'Request failed (HTTP $code).';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
  return 'Something went wrong. Please try again.';
}
