import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/providers/theme_provider.dart';
import 'shared/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Suppress MIUI/accessibility-service semantics assertion spam in debug mode.
  // These fire from the OS accessibility layer — NOT from app code.
  // Remove this block if you ever need to debug semantics issues.
  assert(() {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString();
      if (msg.contains('parentDataDirty') || msg.contains('RenderBox was not laid out')) {
        return; // swallow MIUI accessibility noise
      }
      original?.call(details);
    };
    return true;
  }());

  runApp(const ProviderScope(child: RentalManagerApp()));
}

class RentalManagerApp extends ConsumerWidget {
  const RentalManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Rental Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
