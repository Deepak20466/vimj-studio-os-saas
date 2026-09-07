import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/models.dart';

class AdminAttendanceTab extends StatefulWidget {
  const AdminAttendanceTab({super.key});

  @override
  State<AdminAttendanceTab> createState() => _AdminAttendanceTabState();
}

class _AdminAttendanceTabState extends State<AdminAttendanceTab> {
  bool _loading = true;
  List<DailyMissingRow> _missing = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/attendance/daily-missing') as List;
      _missing = data.map((e) => DailyMissingRow.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openManualEntry() async {
    final marked = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ManualEntryForm(),
    );
    if (marked == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openManualEntry,
        icon: const Icon(Icons.edit_calendar_outlined),
        label: const Text('Manual Entry'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    child: Text('Coaches Missing Attendance Today', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  const SizedBox(height: 8),
                  if (_missing.isEmpty)
                    const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('All coaches have marked attendance for ended classes today.')))
                  else
                    ..._missing.map((m) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                            title: Text(m.coachName),
                            subtitle: Text('${m.activityName} · ${m.date} · ends ${m.endTime}'),
                          ),
                        )),
                ],
              ),
            ),
    );
  }
}

class _ManualEntryForm extends StatefulWidget {
  const _ManualEntryForm();

  @override
  State<_ManualEntryForm> createState() => _ManualEntryFormState();
}

class _ManualEntryFormState extends State<_ManualEntryForm> {
  List<Activity> _activities = [];
  List<ClassSession> _classes = [];
  List<RosterStudent> _roster = [];
  int? _activityId;
  int? _classId;
  int? _studentId;
  String _status = 'PRESENT';
  bool _loadingActivities = true;
  bool _loadingDetail = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    try {
      final data = await ApiClient.instance.get('/activities') as List;
      _activities = data.map((e) => Activity.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loadingActivities = false);
    }
  }

  Future<void> _onActivityChanged(int? id) async {
    setState(() {
      _activityId = id;
      _classId = null;
      _studentId = null;
      _classes = [];
      _roster = [];
      _loadingDetail = id != null;
    });
    if (id == null) return;
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/activities/$id/classes'),
        ApiClient.instance.get('/activities/$id/roster'),
      ]);
      _classes = (results[0] as List).map((e) => ClassSession.fromJson(e as Map<String, dynamic>)).toList();
      _roster = (results[1] as List).map((e) => RosterStudent.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  Future<void> _submit() async {
    if (_classId == null || _studentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select an activity, class, and student')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await ApiClient.instance.post('/attendance/mark-student/manual', body: {
        'student_id': _studentId,
        'class_id': _classId,
        'status': _status,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
            Text('Manual Attendance Entry', style: Theme.of(context).textTheme.titleLarge),
            const Text('Bypasses geofence and selfie requirements.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 16),
            _loadingActivities
                ? const Center(child: CircularProgressIndicator())
                : DropdownButtonFormField<int>(
                    value: _activityId,
                    decoration: const InputDecoration(labelText: 'Activity'),
                    items: _activities.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                    onChanged: _onActivityChanged,
                  ),
            const SizedBox(height: 12),
            if (_loadingDetail) const Center(child: CircularProgressIndicator()),
            if (!_loadingDetail && _activityId != null) ...[
              DropdownButtonFormField<int>(
                value: _classId,
                decoration: const InputDecoration(labelText: 'Class'),
                items: _classes.map((c) => DropdownMenuItem(value: c.id, child: Text('${c.date} (${c.startTime}-${c.endTime})'))).toList(),
                onChanged: (v) => setState(() => _classId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: _studentId,
                decoration: const InputDecoration(labelText: 'Student'),
                items: _roster.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                onChanged: (v) => setState(() => _studentId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'PRESENT', child: Text('Present')),
                  DropdownMenuItem(value: 'ABSENT', child: Text('Absent')),
                  DropdownMenuItem(value: 'LEAVE', child: Text('Leave')),
                ],
                onChanged: (v) => setState(() => _status = v ?? 'PRESENT'),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Record'),
            ),
          ],
        ),
      ),
    );
  }
}
