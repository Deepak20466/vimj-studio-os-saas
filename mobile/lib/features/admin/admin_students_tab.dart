import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/models.dart';
import 'report_screen.dart';

class AdminStudentsTab extends StatefulWidget {
  const AdminStudentsTab({super.key});

  @override
  State<AdminStudentsTab> createState() => _AdminStudentsTabState();
}

class _AdminStudentsTabState extends State<AdminStudentsTab> {
  List<Student> _students = [];
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
      final data = await ApiClient.instance.get('/students', query: {'search': _search.isEmpty ? null : _search}) as List;
      _students = data.map((e) => Student.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({Student? student}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _StudentForm(student: student),
    );
    if (saved == true) _load();
  }

  Future<void> _toggleActive(Student s) async {
    try {
      await ApiClient.instance.put('/students/${s.id}', body: {'is_active': !s.isActive});
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _remove(Student s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove student?'),
        content: Text('Remove ${s.name}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.delete('/students/${s.id}');
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin-students-fab',
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add Student'),
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
                    child: _students.isEmpty
                        ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No students found.')))])
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                            itemCount: _students.length,
                            itemBuilder: (context, i) {
                              final s = _students[i];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: ListTile(
                                  title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text('${s.email}\n${s.phone ?? "-"}'),
                                  isThreeLine: true,
                                  leading: CircleAvatar(
                                    backgroundColor: s.isActive ? AppColors.success.withOpacity(0.15) : AppColors.danger.withOpacity(0.15),
                                    child: Icon(Icons.person, color: s.isActive ? AppColors.success : AppColors.danger),
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (v) {
                                      if (v == 'report') {
                                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReportScreen(isCoach: false, id: s.id, name: s.name)));
                                      }
                                      if (v == 'edit') _openForm(student: s);
                                      if (v == 'toggle') _toggleActive(s);
                                      if (v == 'delete') _remove(s);
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(value: 'report', child: Text('View Report')),
                                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                      PopupMenuItem(value: 'toggle', child: Text(s.isActive ? 'Deactivate' : 'Activate')),
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

class _StudentForm extends StatefulWidget {
  final Student? student;
  const _StudentForm({this.student});

  @override
  State<_StudentForm> createState() => _StudentFormState();
}

class _StudentFormState extends State<_StudentForm> {
  late final _nameCtrl = TextEditingController(text: widget.student?.name ?? '');
  late final _emailCtrl = TextEditingController(text: widget.student?.email ?? '');
  late final _phoneCtrl = TextEditingController(text: widget.student?.phone ?? '');
  late final _phoneSecondaryCtrl = TextEditingController(text: widget.student?.phoneSecondary ?? '');
  final _passwordCtrl = TextEditingController();
  bool _saving = false;

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name is required')));
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.student != null) {
        final body = <String, dynamic>{
          'name': _nameCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'phone_secondary': _phoneSecondaryCtrl.text.trim(),
        };
        if (_passwordCtrl.text.isNotEmpty) body['password'] = _passwordCtrl.text;
        await ApiClient.instance.put('/students/${widget.student!.id}', body: body);
      } else {
        final body = <String, dynamic>{
          'name': _nameCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'phone_secondary': _phoneSecondaryCtrl.text.trim(),
        };
        if (_emailCtrl.text.trim().isNotEmpty) body['email'] = _emailCtrl.text.trim();
        if (_passwordCtrl.text.isNotEmpty) body['password'] = _passwordCtrl.text;
        await ApiClient.instance.post('/students', body: body);
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
    _phoneSecondaryCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.student != null;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(editing ? 'Edit Student' : 'Add Student', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              enabled: !editing,
              decoration: InputDecoration(labelText: 'Email', helperText: editing ? 'Email cannot be changed here' : null),
            ),
            const SizedBox(height: 12),
            TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            TextField(controller: _phoneSecondaryCtrl, decoration: const InputDecoration(labelText: 'Emergency Contact'), keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: InputDecoration(labelText: editing ? 'New Password (optional)' : 'Password (optional)'),
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
