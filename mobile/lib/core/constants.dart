class AppConstants {
  AppConstants._();

  static const String apiBaseUrl = 'https://rwrwarkqwn77gwu6zbky1ppo.37.221.93.219.sslip.io';

  // Rewrites Docker-internal MinIO URLs to the public MinIO host.
  static String resolveMediaUrl(String url) {
    return url
        .replaceFirst(RegExp(r'http://minio(:\d+)?'), 'http://37.221.93.219:9000')
        .replaceFirst(RegExp(r'http://localhost(:\d+)?'), 'http://37.221.93.219:9000');
  }

  static const String appName = 'Rental Manager';

  // Currency symbol — change to match your region (e.g. 'USD', 'NGN', 'ZAR', 'UGX')
  static const String currency = 'KES';

  // ── Dev picker credentials (never ship these to production) ────────────────
  static const String devLandlordPhone = '+254100368483';
  static const String devLandlordPassword = 'DevLandlord@2026';
  static const String devTenantPhone = '+254722870015';
  static const String devTenantPassword = 'DevTenant@2026';
}
