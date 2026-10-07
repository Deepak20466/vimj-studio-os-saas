import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/auth_storage.dart';
import '../admin/admin_home.dart';
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
    // Begin waking the API before reading local session state so the health
    // request can overlap startup and the first dashboard or login request.
    unawaited(ApiClient.instance.warmUp());

    // A stored session is trusted on its own — no re-authentication gate on every
    // app open. The client's explicit ask (2026-09-14): once logged in, stay logged
    // in until Logout is pressed; the backend's rotating 30-day refresh token
    // already keeps the session alive indefinitely with normal use (see
    // ApiClient._tryRefresh). A prior biometric-unlock-on-launch gate used to force
    // a fingerprint (or password-login fallback on decline/failure) every single
    // time the app opened even with a perfectly valid session — that was the actual
    // cause of the app feeling like it "locked" on its own. Removed rather than
    // made optional: there was no settings toggle for it anywhere, so it was pure
    // friction with no way to turn it off.
    final session = await AuthStorage.load();
    if (!mounted) return;

    if (session == null) {
      _goToLogin();
      return;
    }

    _goToHome(session.role);
  }

  void _goToLogin() {
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  void _goToHome(String role) {
    switch (role) {
      case 'COACH':
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const CoachHome()));
        break;
      case 'ADMIN':
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AdminHome()));
        break;
      default:
        // The backend rejects student logins outright, so a stored session
        // with any other role means stale/corrupt local state.
        AuthStorage.clear();
        _goToLogin();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.brandOrangeBright,
              AppColors.brandOrangeDark,
              AppColors.brandYellowBright
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20)),
                child: Image.asset('assets/images/logo.jpeg',
                    width: 100, height: 100, fit: BoxFit.contain),
              ),
              const SizedBox(height: 16),
              const Text(
                'VIMJ Studio',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
