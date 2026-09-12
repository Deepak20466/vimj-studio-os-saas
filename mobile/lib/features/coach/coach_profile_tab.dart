import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/auth_api.dart';
import '../../core/auth_storage.dart';
import '../auth/login_screen.dart';
import '../shared/theme_toggle_tile.dart';

class CoachProfileTab extends StatefulWidget {
  const CoachProfileTab({super.key});

  @override
  State<CoachProfileTab> createState() => _CoachProfileTabState();
}

class _CoachProfileTabState extends State<CoachProfileTab> {
  Map<String, dynamic>? _me;
  bool _loading = true;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _currentPasswordCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _newPasswordCtrl.dispose();
    _currentPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/auth/me') as Map<String, dynamic>;
      _me = data;
      _nameCtrl.text = data['name'] as String? ?? '';
      _phoneCtrl.text = data['phone'] as String? ?? '';
      _emailCtrl.text = data['email'] as String? ?? '';
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitProfile() async {
    if (_currentPasswordCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter your current password to confirm changes')));
      return;
    }
    setState(() => _saving = true);
    try {
      final me = _me ?? {};
      final body = <String, dynamic>{'current_password': _currentPasswordCtrl.text};
      final name = _nameCtrl.text.trim();
      if (name.isNotEmpty && name != (me['name'] as String? ?? '')) body['name'] = name;
      final phone = _phoneCtrl.text.trim();
      if (phone != (me['phone'] as String? ?? '')) body['phone'] = phone;
      final email = _emailCtrl.text.trim();
      if (email.isNotEmpty && email != (me['email'] as String? ?? '')) body['email'] = email;
      if (_newPasswordCtrl.text.isNotEmpty) body['new_password'] = _newPasswordCtrl.text;

      final data = await ApiClient.instance.put('/auth/me', body: body) as Map<String, dynamic>;
      _me = data;
      _nameCtrl.text = data['name'] as String? ?? '';
      _phoneCtrl.text = data['phone'] as String? ?? '';
      _emailCtrl.text = data['email'] as String? ?? '';
      _newPasswordCtrl.clear();
      _currentPasswordCtrl.clear();

      // Keep the cached session name in sync so anywhere it's shown (e.g. an
      // app-bar greeting) doesn't go stale until the next login.
      final session = await AuthStorage.load();
      if (session != null) {
        await AuthStorage.save(AuthSession(
          userId: session.userId,
          name: data['name'] as String? ?? session.name,
          role: session.role,
          accessToken: session.accessToken,
          refreshToken: session.refreshToken,
        ));
      }

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openResetMine() async {
    final confirmCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Reset My Data?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This permanently erases your own attendance and leave history. It does '
                'not touch any other coach\'s data. This cannot be undone.',
              ),
              const SizedBox(height: 16),
              const Text('Type RESET to confirm', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(controller: confirmCtrl, autofocus: true, onChanged: (_) => setDialogState(() {})),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: confirmCtrl.text.trim().toUpperCase() == 'RESET' ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Reset My Data', style: TextStyle(color: AppColors.danger)),
            ),
          ],
        ),
      ),
    );
    confirmCtrl.dispose();
    if (confirmed != true) return;
    try {
      final data = await ApiClient.instance.post('/reset/mine') as Map<String, dynamic>;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['detail'] as String? ?? 'Your history has been reset')));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _logout() async {
    await AuthApi.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('My Profile', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          const Text(
                            'Update your name, phone, login email, or password.',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                          ),
                          const SizedBox(height: 16),
                          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _phoneCtrl,
                            decoration: const InputDecoration(labelText: 'Phone', hintText: '+91XXXXXXXXXX'),
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _emailCtrl,
                            decoration: const InputDecoration(labelText: 'Login Email (User ID)'),
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _newPasswordCtrl,
                            decoration: const InputDecoration(labelText: 'New Password (optional)', hintText: 'Leave blank to keep current password'),
                            obscureText: true,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _currentPasswordCtrl,
                            decoration: const InputDecoration(labelText: 'Current Password (required to confirm)'),
                            obscureText: true,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _saving ? null : _submitProfile,
                            child: _saving
                                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Save Changes'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Card(child: ThemeToggleTile()),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.danger.withOpacity(0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Danger Zone', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.danger)),
                        const SizedBox(height: 4),
                        const Text(
                          'Reset your own attendance and leave history back to a clean slate.',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _openResetMine,
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                          child: const Text('Reset My Data'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(onPressed: _logout, icon: const Icon(Icons.logout), label: const Text('Log out')),
                ],
              ),
            ),
    );
  }
}
