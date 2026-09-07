import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';

class AdminSettingsTab extends StatefulWidget {
  const AdminSettingsTab({super.key});

  @override
  State<AdminSettingsTab> createState() => _AdminSettingsTabState();
}

class _AdminSettingsTabState extends State<AdminSettingsTab> {
  Map<String, dynamic>? _me;
  bool _loading = true;
  bool _saving = false;
  late final _emailCtrl = TextEditingController();
  final _currentPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/auth/me') as Map<String, dynamic>;
      _me = data;
      _emailCtrl.text = data['email'] as String;
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_currentPasswordCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter your current password to confirm changes')));
      return;
    }
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{'current_password': _currentPasswordCtrl.text};
      if (_emailCtrl.text.trim() != _me?['email']) body['email'] = _emailCtrl.text.trim();
      if (_newPasswordCtrl.text.isNotEmpty) body['new_password'] = _newPasswordCtrl.text;
      final data = await ApiClient.instance.put('/auth/me', body: body) as Map<String, dynamic>;
      _me = data;
      _emailCtrl.text = data['email'] as String;
      _currentPasswordCtrl.clear();
      _newPasswordCtrl.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account updated')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _currentPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('My Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text(_me?['name'] as String? ?? '', style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 16),
              TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email / Login ID')),
              const SizedBox(height: 12),
              TextField(
                controller: _newPasswordCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New Password (optional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _currentPasswordCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Current Password (required to save)'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save Changes'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
