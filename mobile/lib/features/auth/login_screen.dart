import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/auth_api.dart';
import '../admin/admin_home.dart';
import '../coach/coach_home.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  String? _loadingMessage;
  Timer? _loadingMessageTimer;
  Timer? _cooldownTimer;
  DateTime? _cooldownUntil;
  Duration? _cooldownRemaining;

  @override
  void initState() {
    super.initState();
    // Wake a sleeping production API while the user enters credentials; this
    // stays in the background and never blocks the login screen.
    unawaited(ApiClient.instance.warmUp());
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _loadingMessage = null;
    });
    _loadingMessageTimer?.cancel();
    _loadingMessageTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || !_loading) return;
      setState(() =>
          _loadingMessage = 'Waking up the service can take a little while.');
    });
    try {
      // Splash and this screen already start the health warm-up before the
      // user submits. Let the login request proceed alone here instead of
      // opening a second connection alongside it after a long idle.
      final session =
          await AuthApi.login(_emailCtrl.text.trim(), _passwordCtrl.text);
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
            builder: (_) => session.role == 'ADMIN'
                ? const AdminHome()
                : const CoachHome()),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
      if (e.statusCode == 429 && e.retryAfter != null) {
        _startLoginCooldown(e.retryAfter!);
      }
    } on Exception catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '').trim();
      setState(() => _error = message.isEmpty
          ? 'Could not sign in. Check your internet connection and try again.'
          : 'Could not sign in: $message');
    } finally {
      _loadingMessageTimer?.cancel();
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMessage = null;
        });
      }
    }
  }

  void _startLoginCooldown(Duration duration) {
    _cooldownTimer?.cancel();
    _cooldownUntil = DateTime.now().add(duration);
    _updateLoginCooldown();
    if (_cooldownUntil != null) {
      _cooldownTimer = Timer.periodic(
          const Duration(seconds: 1), (_) => _updateLoginCooldown());
    }
  }

  void _updateLoginCooldown() {
    final until = _cooldownUntil;
    if (!mounted || until == null) return;
    final remaining = until.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _cooldownTimer?.cancel();
      _cooldownTimer = null;
      _cooldownUntil = null;
      setState(() => _cooldownRemaining = null);
      return;
    }
    setState(() => _cooldownRemaining = remaining);
  }

  String _formatCooldown(Duration remaining) {
    final seconds = remaining.inSeconds;
    final minutes = seconds ~/ 60;
    final restSeconds = seconds % 60;
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final restMinutes = minutes % 60;
      return '${hours}h ${restMinutes}m';
    }
    if (minutes > 0) {
      return '${minutes}m ${restSeconds.toString().padLeft(2, '0')}s';
    }
    return '${seconds}s';
  }

  @override
  void dispose() {
    _loadingMessageTimer?.cancel();
    _cooldownTimer?.cancel();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
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
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 30,
                        offset: const Offset(0, 12))
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/logo.jpeg',
                        width: 120,
                        height: 120,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'VIMJ Studio',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.brandOrange,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sign in',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 32),
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(_error!,
                              style: const TextStyle(color: Colors.red)),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        // This card is always white regardless of the app's light/dark
                        // theme setting, so the typed text color must be pinned dark too —
                        // otherwise dark mode's default light input text is nearly
                        // invisible here.
                        style: const TextStyle(color: AppColors.text),
                        cursorColor: AppColors.brandOrange,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          labelStyle: TextStyle(color: AppColors.textMuted),
                          floatingLabelStyle:
                              TextStyle(color: AppColors.brandOrangeDark),
                          filled: true,
                          fillColor: Colors.white,
                          hintStyle: TextStyle(color: AppColors.textMuted),
                          prefixIcon: Icon(Icons.email_outlined,
                              color: AppColors.brandOrange),
                        ),
                        validator: (v) => (v == null || !v.contains('@'))
                            ? 'Enter a valid email'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: _obscure,
                        style: const TextStyle(color: AppColors.text),
                        cursorColor: AppColors.brandOrange,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          labelStyle:
                              const TextStyle(color: AppColors.textMuted),
                          floatingLabelStyle:
                              const TextStyle(color: AppColors.brandOrangeDark),
                          filled: true,
                          fillColor: Colors.white,
                          hintStyle:
                              const TextStyle(color: AppColors.textMuted),
                          prefixIcon: const Icon(Icons.lock_outline,
                              color: AppColors.brandOrange),
                          suffixIcon: IconButton(
                            icon: Icon(
                                _obscure
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: AppColors.brandOrange),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Enter your password'
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _loading
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const ForgotPasswordScreen())),
                          child: const Text('Forgot password?'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loading || _cooldownRemaining != null
                            ? null
                            : _submit,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Text(_cooldownRemaining == null
                                ? 'Sign in'
                                : 'Try again in ${_formatCooldown(_cooldownRemaining!)}'),
                      ),
                      if (_loadingMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _loadingMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
