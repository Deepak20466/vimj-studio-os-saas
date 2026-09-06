import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../core/auth_storage.dart';
import '../../core/biometric_service.dart';
import '../coach/coach_home.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final session = await AuthStorage.load();
    if (!mounted) return;

    if (session == null) {
      _goToLogin();
      return;
    }

    final biometricAvailable = await BiometricService.isAvailable();
    if (biometricAvailable) {
      final ok = await BiometricService.authenticate();
      if (!mounted) return;
      if (!ok) {
        // Biometric declined/failed — fall back to password login rather than
        // silently letting them in.
        _goToLogin();
        return;
      }
    }

    _goToHome(session.role);
  }

  void _goToLogin() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  void _goToHome(String role) {
    if (role != 'COACH') {
      // Only coach sessions are ever meant to persist — the backend rejects
      // student logins outright, and the login screen clears an admin
      // session immediately after login. A stored session with any other
      // role means stale/corrupt local state, so drop it and start over.
      AuthStorage.clear();
      _goToLogin();
      return;
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const CoachHome()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brandBlue,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.sports_gymnastics, color: Colors.white, size: 64),
            SizedBox(height: 16),
            Text(
              'VIMJ Studio',
              style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}
