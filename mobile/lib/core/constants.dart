class AppConstants {
  AppConstants._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8020',
  );
  static const String mediaBaseUrl = String.fromEnvironment(
    'MEDIA_BASE_URL',
    defaultValue: 'http://10.0.2.2:9000',
  );

  static String resolveMediaUrl(String url) {
    return url
        .replaceFirst(RegExp(r'http://minio(:\d+)?'), mediaBaseUrl)
        .replaceFirst(RegExp(r'http://localhost(:\d+)?'), mediaBaseUrl);
  }

  static const String appName = 'Kasa';
  static const String currency = 'KES';
}
