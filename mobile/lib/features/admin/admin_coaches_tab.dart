import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/models.dart';

class AdminCoachesTab extends StatefulWidget {
  const AdminCoachesTab({super.key});

  @override
  State<AdminCoachesTab> createState() => _AdminCoachesTabState();
}

class _AdminCoachesTabState extends State<AdminCoachesTab> {
  List<Coach> _coaches = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/coaches', query: {'search': _search.isEmpty ? null : _search}) as List;
      _coaches = data.map((e) => Coach.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({Coach? coach}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CoachForm(coach: coach),
    );
    if (saved == true) _load();
  }

  Future<void> _openActivities(Coach c) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CoachActivitiesSheet(coach: c),
    );
  }

  Future<void> _toggleActive(Coach c) async {
    try {
      await ApiClient.instance.put('/coaches/${c.id}', body: {'is_active': !c.isActive});
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _remove(Coach c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove coach?'),
        content: Text('Remove ${c.name}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.delete('/coaches/${c.id}');
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin-coaches-fab',
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add Coach'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Search by name or email...', prefixIcon: Icon(Icons.search)),
              onChanged: (v) {
                _search = v;
                _load();
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _coaches.isEmpty
                        ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No coaches found.')))])
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                            itemCount: _coaches.length,
                            itemBuilder: (context, i) {
                              final c = _coaches[i];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: ListTile(
                                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text('${c.email}\n${c.phone ?? "-"}'),
                                  isThreeLine: true,
                                  leading: CircleAvatar(
                                    backgroundColor: c.isActive ? AppColors.success.withOpacity(0.15) : AppColors.danger.withOpacity(0.15),
                                    child: Icon(Icons.sports, color: c.isActive ? AppColors.success : AppColors.danger),
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (v) {
                                      if (v == 'edit') _openForm(coach: c);
                                      if (v == 'activities') _openActivities(c);
                                      if (v == 'toggle') _toggleActive(c);
                                      if (v == 'delete') _remove(c);
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                      const PopupMenuItem(value: 'activities', child: Text('Manage Activities')),
                                      PopupMenuItem(value: 'toggle', child: Text(c.isActive ? 'Deactivate' : 'Activate')),
                                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CoachForm extends StatefulWidget {
  final Coach? coach;
  const _CoachForm({this.coach});

  @override
  State<_CoachForm> createState() => _CoachFormState();
}

class _CoachFormState extends State<_CoachForm> {
  late final _nameCtrl = TextEditingController(text: widget.coach?.name ?? '');
  late final _emailCtrl = TextEditingController(text: widget.coach?.email ?? '');
  late final _phoneCtrl = TextEditingController(text: widget.coach?.phone ?? '');
  final _passwordCtrl = TextEditingController();
  bool _saving = false;

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty || _emailCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name and email are required')));
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.coach != null) {
        final body = <String, dynamic>{'name': _nameCtrl.text.trim(), 'phone': _phoneCtrl.text.trim()};
        if (_emailCtrl.text.trim() != widget.coach!.email) body['email'] = _emailCtrl.text.trim();
        if (_passwordCtrl.text.isNotEmpty) body['password'] = _passwordCtrl.text;
        await ApiClient.instance.put('/coaches/${widget.coach!.id}', body: body);
      } else {
        if (_passwordCtrl.text.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password is required for a new coach')));
          setState(() => _saving = false);
          return;
        }
        await ApiClient.instance.post('/coaches', body: {
          'name': _nameCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'password': _passwordCtrl.text,
        });
      }
      if (mounted) Navigator.of(context).pop(true);
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
    final editing = widget.coach != null;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(editing ? 'Edit Coach' : 'Add Coach', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email / Login ID')),
            const SizedBox(height: 12),
            TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: InputDecoration(labelText: editing ? 'New Password (optional)' : 'Password'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(editing ? 'Save' : 'Create'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoachActivitiesSheet extends StatefulWidget {
  final Coach coach;
  const _CoachActivitiesSheet({required this.coach});

  @override
  State<_CoachActivitiesSheet> createState() => _CoachActivitiesSheetState();
}

class _CoachActivitiesSheetState extends State<_CoachActivitiesSheet> {
  bool _loading = true;
  bool _saving = false;
  List<Activity> _all = [];
  Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/activities'),
        ApiClient.instance.get('/coaches/${widget.coach.id}/activities'),
      ]);
      _all = (results[0] as List).map((e) => Activity.fromJson(e as Map<String, dynamic>)).toList();
      _selected = (results[1] as List).map((e) => (e as Map<String, dynamic>)['activity_id'] as int).toSet();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ApiClient.instance.put('/coaches/${widget.coach.id}/activities', body: {'activity_ids': _selected.toList()});
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Activities for ${widget.coach.name}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _all.isEmpty
                      ? const Center(child: Text('No activities exist yet.'))
                      : ListView(
                          children: _all
                              .map((a) => CheckboxListTile(
                                    title: Text(a.name),
                                    value: _selected.contains(a.id),
                                    onChanged: (v) => setState(() {
                                      if (v == true) {
                                        _selected.add(a.id);
                                      } else {
                                        _selected.remove(a.id);
                                      }
                                    }),
                                  ))
                              .toList(),
                        ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
