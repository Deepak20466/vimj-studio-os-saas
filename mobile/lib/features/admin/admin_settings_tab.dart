import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/models.dart';
import '../shared/theme_toggle_tile.dart';

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

  bool _loadingAcademy = true;
  bool _savingAcademy = false;
  late final _academyNameCtrl = TextEditingController();
  late final _academyPhoneCtrl = TextEditingController();
  late final _academyEmailCtrl = TextEditingController();
  late final _academyAddressCtrl = TextEditingController();
  late final _academyDescriptionCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _loadCoaches();
    _loadAcademy();
  }

  Future<void> _loadAcademy() async {
    setState(() => _loadingAcademy = true);
    try {
      final data = await ApiClient.instance.get('/academy') as Map<String, dynamic>;
      _academyNameCtrl.text = data['name'] as String? ?? '';
      _academyPhoneCtrl.text = data['phone'] as String? ?? '';
      _academyEmailCtrl.text = data['email'] as String? ?? '';
      _academyAddressCtrl.text = data['address'] as String? ?? '';
      _academyDescriptionCtrl.text = data['description'] as String? ?? '';
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loadingAcademy = false);
    }
  }

  Future<void> _submitAcademy() async {
    setState(() => _savingAcademy = true);
    try {
      await ApiClient.instance.put('/academy', body: {
        'name': _academyNameCtrl.text.trim(),
        'phone': _academyPhoneCtrl.text.trim(),
        'email': _academyEmailCtrl.text.trim(),
        'address': _academyAddressCtrl.text.trim(),
        'description': _academyDescriptionCtrl.text.trim(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Academy profile updated')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _savingAcademy = false);
    }
  }

  Future<void> _toggleCoachActive(Coach c) async {
    try {
      await ApiClient.instance.put('/coaches/${c.id}', body: {'is_active': !c.isActive});
      _loadCoaches();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
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

  Future<void> _openResetAll() async {
    final confirmCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Reset All Data?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This permanently erases all attendance, fee, and notification records for every '
                'student and coach. Users, activities, and batches are kept so the app keeps '
                'working right after. This cannot be undone.',
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
              child: const Text('Reset All Data', style: TextStyle(color: AppColors.danger)),
            ),
          ],
        ),
      ),
    );
    confirmCtrl.dispose();
    if (confirmed != true) return;
    try {
      final data = await ApiClient.instance.post('/reset/all') as Map<String, dynamic>;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['detail'] as String? ?? 'All data has been reset')));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openAddCoach() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _AddCoachForm(),
    );
    if (saved == true) _loadCoaches();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _currentPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _academyNameCtrl.dispose();
    _academyPhoneCtrl.dispose();
    _academyEmailCtrl.dispose();
    _academyAddressCtrl.dispose();
    _academyDescriptionCtrl.dispose();
    super.dispose();
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
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Card(child: ThemeToggleTile()),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
          ),
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
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Academy Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              const Text('Shown on generated fee receipts and available to coaches.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(height: 16),
              if (_loadingAcademy)
                const Center(child: CircularProgressIndicator())
              else ...[
                TextField(controller: _academyNameCtrl, decoration: const InputDecoration(labelText: 'Academy Name')),
                const SizedBox(height: 12),
                TextField(controller: _academyPhoneCtrl, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone),
                const SizedBox(height: 12),
                TextField(controller: _academyEmailCtrl, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 12),
                TextField(controller: _academyAddressCtrl, decoration: const InputDecoration(labelText: 'Address')),
                const SizedBox(height: 12),
                TextField(controller: _academyDescriptionCtrl, decoration: const InputDecoration(labelText: 'Description'), maxLines: 2),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _savingAcademy ? null : _submitAcademy,
                  child: _savingAcademy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save Changes'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Coach Accounts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            TextButton.icon(onPressed: _openAddCoach, icon: const Icon(Icons.add), label: const Text('Add Coach')),
          ],
        ),
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
                                title: Row(
                                  children: [
                                    Flexible(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                                    const SizedBox(width: 8),
                                    Chip(
                                      label: Text(c.isActive ? 'Active' : 'Inactive', style: const TextStyle(color: Colors.white, fontSize: 11)),
                                      backgroundColor: c.isActive ? AppColors.success : AppColors.danger,
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ],
                                ),
                                subtitle: Text(c.email),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'credentials') _openCoachCredentials(c);
                                    if (v == 'toggle') _toggleCoachActive(c);
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(value: 'credentials', child: Text('Change Login')),
                                    PopupMenuItem(value: 'toggle', child: Text(c.isActive ? 'Deactivate' : 'Activate')),
                                  ],
                                ),
                              ),
                            ))
                        .toList(),
                  ),
        const SizedBox(height: 24),
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
                'Reset all attendance, fee, and notification history back to a clean slate. Users, '
                'students, coaches, activities, and batches are kept.',
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _openResetAll,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                child: const Text('Reset All Data'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AddCoachForm extends StatefulWidget {
  const _AddCoachForm();

  @override
  State<_AddCoachForm> createState() => _AddCoachFormState();
}

class _AddCoachFormState extends State<_AddCoachForm> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _saving = false;

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty || _emailCtrl.text.trim().isEmpty || _passwordCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name, login email, and password are required')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiClient.instance.post('/coaches', body: {
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'password': _passwordCtrl.text,
      });
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coach created')));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
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
            Text('Add Coach', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Login Email (User ID)'), keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 12),
            TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            TextField(controller: _passwordCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Create'),
            ),
          ],
        ),
      ),
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
