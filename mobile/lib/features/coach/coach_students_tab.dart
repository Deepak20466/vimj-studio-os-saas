import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/auth_storage.dart';
import '../../core/models.dart';

class CoachStudentsTab extends StatefulWidget {
  const CoachStudentsTab({super.key});

  @override
  State<CoachStudentsTab> createState() => _CoachStudentsTabState();
}

class _CoachStudentsTabState extends State<CoachStudentsTab> {
  List<CoachActivityLink> _activities = [];
  final Map<int, List<RosterStudent>> _rosterByActivity = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final session = await AuthStorage.load();
      if (session == null) return;
      final data = await ApiClient.instance.get('/coaches/${session.userId}/activities') as List;
      _activities = data.map((e) => CoachActivityLink.fromJson(e as Map<String, dynamic>)).toList();
      final rosters = await Future.wait(_activities.map((a) => ApiClient.instance.get('/activities/${a.activityId}/roster')));
      _rosterByActivity.clear();
      for (var i = 0; i < _activities.length; i++) {
        final list = (rosters[i] as List).map((e) => RosterStudent.fromJson(e as Map<String, dynamic>)).toList();
        _rosterByActivity[_activities[i].activityId] = list;
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddStudentForm(activities: _activities),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Students')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'coach-students-fab',
        onPressed: _activities.isEmpty ? null : _openForm,
        icon: const Icon(Icons.add),
        label: const Text('Add Student'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _activities.isEmpty
                  ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('You are not assigned to any activity yet.')))])
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                      children: _activities.map((a) {
                        final roster = _rosterByActivity[a.activityId] ?? [];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a.activityName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 6),
                                if (roster.isEmpty)
                                  const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No students enrolled yet.', style: TextStyle(color: AppColors.textMuted)))
                                else
                                  ...roster.map((s) => ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: const Icon(Icons.person_outline),
                                        title: Text(s.name),
                                        subtitle: Text(s.email),
                                      )),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
            ),
    );
  }
}

class _AddStudentForm extends StatefulWidget {
  final List<CoachActivityLink> activities;
  const _AddStudentForm({required this.activities});

  @override
  State<_AddStudentForm> createState() => _AddStudentFormState();
}

class _AddStudentFormState extends State<_AddStudentForm> {
  late int? _activityId = widget.activities.isNotEmpty ? widget.activities.first.activityId : null;
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _phoneSecondaryCtrl = TextEditingController();
  bool _saving = false;

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().isEmpty || _phoneSecondaryCtrl.text.trim().isEmpty || _activityId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name, both phone numbers, and activity are required')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiClient.instance.post('/students', body: {
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'phone_secondary': _phoneSecondaryCtrl.text.trim(),
        'activity_id': _activityId,
      });
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
    _phoneCtrl.dispose();
    _phoneSecondaryCtrl.dispose();
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
            Text('Add Student', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _activityId,
              decoration: const InputDecoration(labelText: 'Activity'),
              items: widget.activities.map((a) => DropdownMenuItem(value: a.activityId, child: Text(a.activityName))).toList(),
              onChanged: (v) => setState(() => _activityId = v),
            ),
            const SizedBox(height: 12),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Primary Phone'), keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            TextField(controller: _phoneSecondaryCtrl, decoration: const InputDecoration(labelText: 'Emergency Contact'), keyboardType: TextInputType.phone),
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
