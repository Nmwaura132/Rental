import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';

class ServerUrlNotifier extends Notifier<String> {
  @override
  String build() {
    _load();
    return AppConstants.apiBaseUrl;
  }

  Future<void> _load() async {
    // Forcing app to ignore cached URLs for now to fix connection issues!
    // We can re-enable SharedPreferences loading once the Ngrok tunnel is stable.
  }

  Future<void> setUrl(String url) async {
    state = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', url);
  }
}

final serverUrlProvider = NotifierProvider<ServerUrlNotifier, String>(() {
  return ServerUrlNotifier();
});
