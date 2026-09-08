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
  bool _recordsLoading = true;
  List<DailyMissingRow> _missing = [];
  List<AdminAttendanceRecord> _records = [];
  List<Activity> _activities = [];
  List<Coach> _coaches = [];

  int? _filterActivityId;
  String? _filterStatus;
  DateTime? _filterDateFrom;
  DateTime? _filterDateTo;

  @override
  void initState() {
    super.initState();
    _load();
    _loadRecords();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/attendance/daily-missing'),
        ApiClient.instance.get('/activities'),
        ApiClient.instance.get('/coaches'),
      ]);
      _missing = (results[0] as List).map((e) => DailyMissingRow.fromJson(e as Map<String, dynamic>)).toList();
      _activities = (results[1] as List).map((e) => Activity.fromJson(e as Map<String, dynamic>)).toList();
      _coaches = (results[2] as List).map((e) => Coach.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadRecords() async {
    setState(() => _recordsLoading = true);
    try {
      final query = <String, dynamic>{};
      if (_filterActivityId != null) query['activity_id'] = _filterActivityId;
      if (_filterStatus != null) query['status_filter'] = _filterStatus;
      if (_filterDateFrom != null) query['date_from'] = _filterDateFrom!.toIso8601String().substring(0, 10);
      if (_filterDateTo != null) query['date_to'] = _filterDateTo!.toIso8601String().substring(0, 10);
      final data = await ApiClient.instance.get('/attendance/students', query: query) as List;
      _records = data.map((e) => AdminAttendanceRecord.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _recordsLoading = false);
    }
  }

  Future<void> _refreshAll() async {
    await _load();
    await _loadRecords();
  }

  Future<void> _openManualEntry() async {
    final marked = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _ManualEntryForm(),
    );
    if (marked == true) _refreshAll();
  }

  Future<void> _openReassign(DailyMissingRow m) async {
    int? coveringCoachId;
    final reasonCtrl = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Reassign — ${m.activityName} (${m.date})', style: Theme.of(ctx).textTheme.titleLarge),
                Text('${m.coachName} is marked absent for this class; pick a substitute coach to cover it.', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: coveringCoachId,
                  decoration: const InputDecoration(labelText: 'Substitute Coach'),
                  items: _coaches.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                  onChanged: (v) => setSheetState(() => coveringCoachId = v),
                ),
                const SizedBox(height: 12),
                TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reason for substitution'), maxLines: 3),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () async {
                    if (coveringCoachId == null || reasonCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Pick a substitute coach and reason')));
                      return;
                    }
                    try {
                      await ApiClient.instance.post('/swap/admin-assign', body: {
                        'original_coach_id': m.coachId,
                        'covering_coach_id': coveringCoachId,
                        'class_id': m.classId,
                        'date': m.date,
                        'reason': reasonCtrl.text.trim(),
                      });
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    } on ApiException catch (e) {
                      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  },
                  child: const Text('Reassign'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    reasonCtrl.dispose();
    if (saved == true) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Class reassigned to substitute coach')));
      _load();
    }
  }

  Future<void> _openEditRecord(AdminAttendanceRecord r) async {
    String status = r.status;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Edit Attendance — ${r.studentName}'),
          content: DropdownButtonFormField<String>(
            initialValue: status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: const [
              DropdownMenuItem(value: 'PRESENT', child: Text('Present')),
              DropdownMenuItem(value: 'ABSENT', child: Text('Absent')),
              DropdownMenuItem(value: 'LEAVE', child: Text('Leave')),
            ],
            onChanged: (v) => setDialogState(() => status = v ?? status),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                try {
                  await ApiClient.instance.put('/attendance/students/${r.id}', body: {'status': status});
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } on ApiException catch (e) {
                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attendance updated')));
      _refreshAll();
    }
  }

  Future<void> _removeRecord(AdminAttendanceRecord r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete attendance record?'),
        content: Text('Delete this attendance record for ${r.studentName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.delete('/attendance/students/${r.id}');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attendance record deleted')));
      _refreshAll();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _pickFilterDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _filterDateFrom : _filterDateTo) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => isFrom ? _filterDateFrom = picked : _filterDateTo = picked);
    _loadRecords();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin-attendance-fab',
        onPressed: _openManualEntry,
        icon: const Icon(Icons.edit_calendar_outlined),
        label: const Text('Manual Entry'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshAll,
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
                            trailing: TextButton(onPressed: () => _openReassign(m), child: const Text('Reassign')),
                          ),
                        )),
                  const SizedBox(height: 20),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    child: Text('All Attendance Records', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      DropdownButton<int?>(
                        value: _filterActivityId,
                        hint: const Text('All activities'),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('All activities')),
                          ..._activities.map((a) => DropdownMenuItem<int?>(value: a.id, child: Text(a.name))),
                        ],
                        onChanged: (v) {
                          setState(() => _filterActivityId = v);
                          _loadRecords();
                        },
                      ),
                      DropdownButton<String?>(
                        value: _filterStatus,
                        hint: const Text('All statuses'),
                        items: const [
                          DropdownMenuItem<String?>(value: null, child: Text('All statuses')),
                          DropdownMenuItem<String?>(value: 'PRESENT', child: Text('Present')),
                          DropdownMenuItem<String?>(value: 'ABSENT', child: Text('Absent')),
                          DropdownMenuItem<String?>(value: 'LEAVE', child: Text('Leave')),
                        ],
                        onChanged: (v) {
                          setState(() => _filterStatus = v);
                          _loadRecords();
                        },
                      ),
                      OutlinedButton(
                        onPressed: () => _pickFilterDate(true),
                        child: Text(_filterDateFrom == null ? 'From date' : _filterDateFrom!.toIso8601String().substring(0, 10)),
                      ),
                      OutlinedButton(
                        onPressed: () => _pickFilterDate(false),
                        child: Text(_filterDateTo == null ? 'To date' : _filterDateTo!.toIso8601String().substring(0, 10)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_recordsLoading)
                    const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
                  else if (_records.isEmpty)
                    const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No attendance records match these filters.')))
                  else
                    ..._records.map((r) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(r.studentName),
                            subtitle: Text('${r.classDate} · ${r.activityName} · ${r.coachName ?? "-"} · ${r.markedManually ? "Manual" : "Coach"}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Chip(
                                  label: Text(r.status, style: const TextStyle(fontSize: 11, color: Colors.white)),
                                  backgroundColor: r.status == 'PRESENT'
                                      ? AppColors.success
                                      : r.status == 'ABSENT'
                                          ? AppColors.danger
                                          : AppColors.warning,
                                  visualDensity: VisualDensity.compact,
                                ),
                                IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _openEditRecord(r)),
                                IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.danger), onPressed: () => _removeRecord(r)),
                              ],
                            ),
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
                    initialValue: _activityId,
                    decoration: const InputDecoration(labelText: 'Activity'),
                    items: _activities.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                    onChanged: _onActivityChanged,
                  ),
            const SizedBox(height: 12),
            if (_loadingDetail) const Center(child: CircularProgressIndicator()),
            if (!_loadingDetail && _activityId != null) ...[
              DropdownButtonFormField<int>(
                initialValue: _classId,
                decoration: const InputDecoration(labelText: 'Class'),
                items: _classes.map((c) => DropdownMenuItem(value: c.id, child: Text('${c.date} (${c.startTime}-${c.endTime})'))).toList(),
                onChanged: (v) => setState(() => _classId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _studentId,
                decoration: const InputDecoration(labelText: 'Student'),
                items: _roster.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                onChanged: (v) => setState(() => _studentId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
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
