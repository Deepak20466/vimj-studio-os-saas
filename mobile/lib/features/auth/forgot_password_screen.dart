import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/auth_api.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  bool _codeRequested = false;
  bool _loading = false;
  String? _message;

  Future<void> _requestCode() async {
    if (_emailCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await AuthApi.forgotPassword(_emailCtrl.text.trim());
      setState(() {
        _codeRequested = true;
        _message = 'If that email is registered, a reset code has been sent via SMS/WhatsApp.';
      });
    } on ApiException catch (e) {
      setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_tokenCtrl.text.trim().isEmpty || _newPasswordCtrl.text.length < 8) {
      setState(() => _message = 'Enter the reset code and a password of at least 8 characters.');
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthApi.resetPassword(_tokenCtrl.text.trim(), _newPasswordCtrl.text);
      if (!mounted) return;
      setState(() => _message = 'Password reset. You can now sign in.');
    } on ApiException catch (e) {
      setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _tokenCtrl.dispose();
    _newPasswordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_message != null) ...[
              Text(_message!, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _emailCtrl,
              enabled: !_codeRequested,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Account email'),
            ),
            const SizedBox(height: 12),
            if (!_codeRequested)
              ElevatedButton(
                onPressed: _loading ? null : _requestCode,
                child: const Text('Send reset code'),
              )
            else ...[
              TextField(
                controller: _tokenCtrl,
                decoration: const InputDecoration(labelText: 'Reset code'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newPasswordCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loading ? null : _resetPassword,
                child: const Text('Reset password'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
