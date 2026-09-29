import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the bundled Geist fonts for a widget test.
///
/// WHY: `flutter test` does not load an app's fonts. Text is drawn in a
/// placeholder whose glyphs are about twice as wide as Geist, so a layout test
/// reports overflows that do not happen on a phone, and cannot be trusted for
/// the ones that do. Call this from `setUpAll` in any test that checks layout.
Future<void> loadKasaFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(rootBundle.load('assets/fonts/$file'));
    }
    await loader.load();
  }

  await load('Geist', [
    'Geist-Regular.ttf',
    'Geist-Medium.ttf',
    'Geist-SemiBold.ttf',
  ]);
  await load('Geist Mono', [
    'GeistMono-Regular.ttf',
    'GeistMono-Medium.ttf',
  ]);
}
