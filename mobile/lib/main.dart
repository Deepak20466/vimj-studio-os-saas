import 'package:flutter/material.dart';
import 'core/app_theme.dart';
import 'core/notification_service.dart';
import 'core/sync_service.dart';
import 'core/theme_controller.dart';
import 'features/auth/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.load();
  await NotificationService.init();
  SyncService.start();
  runApp(const VimjApp());
}

class VimjApp extends StatelessWidget {
  const VimjApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'VIMJ Studio',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeMode,
          home: const SplashScreen(),
        );
      },
    );
  }
}
