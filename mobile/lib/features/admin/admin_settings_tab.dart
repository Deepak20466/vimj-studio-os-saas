import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/models.dart';

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

  List<Coach> _coaches = [];
  bool _loadingCoaches = true;
  String _coachSearch = '';

  @override
  void initState() {
    super.initState();
    _load();
    _loadCoaches();
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

  Future<void> _loadCoaches() async {
    setState(() => _loadingCoaches = true);
    try {
      final data = await ApiClient.instance.get('/coaches', query: {'search': _coachSearch.isEmpty ? null : _coachSearch}) as List;
      _coaches = data.map((e) => Coach.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loadingCoaches = false);
    }
  }

  Future<void> _openCoachCredentials(Coach coach) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CoachCredentialsForm(coach: coach),
    );
    _loadCoaches();
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
        const SizedBox(height: 20),
        const Text('Coach Accounts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(hintText: 'Search by name or email...', prefixIcon: Icon(Icons.search)),
          onChanged: (v) {
            _coachSearch = v;
            _loadCoaches();
          },
        ),
        const SizedBox(height: 12),
        _loadingCoaches
            ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
            : _coaches.isEmpty
                ? const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('No coaches found.')))
                : Column(
                    children: _coaches
                        .map((c) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(c.email),
                                trailing: TextButton(
                                  onPressed: () => _openCoachCredentials(c),
                                  child: const Text('Change Login'),
                                ),
                              ),
                            ))
                        .toList(),
                  ),
      ],
    );
  }
}

class _CoachCredentialsForm extends StatefulWidget {
  final Coach coach;
  const _CoachCredentialsForm({required this.coach});

  @override
  State<_CoachCredentialsForm> createState() => _CoachCredentialsFormState();
}

class _CoachCredentialsFormState extends State<_CoachCredentialsForm> {
  late final _emailCtrl = TextEditingController(text: widget.coach.email);
  final _passwordCtrl = TextEditingController();
  bool _saving = false;

  Future<void> _submit() async {
    final body = <String, dynamic>{};
    if (_emailCtrl.text.trim().isNotEmpty && _emailCtrl.text.trim() != widget.coach.email) body['email'] = _emailCtrl.text.trim();
    if (_passwordCtrl.text.isNotEmpty) body['password'] = _passwordCtrl.text;
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Change the login email or password before saving')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiClient.instance.put('/coaches/${widget.coach.id}', body: body);
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coach credentials updated')));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Change Credentials — ${widget.coach.name}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Login Email (User ID)')),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New Password (optional)'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
