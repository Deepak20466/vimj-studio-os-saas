import 'dart:typed_data';
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
  int? _removingId;
  int? _approvalBusyId;

  // --- Coach attendance (separate CRUD) ---
  bool _coachRecordsLoading = true;
  List<Map<String, dynamic>> _coachRecords = [];
  int? _coachFilterId;
  DateTime? _coachFilterDateFrom;
  DateTime? _coachFilterDateTo;
  int? _removingCoachId;

  @override
  void initState() {
    super.initState();
    _load();
    _loadRecords();
    _loadCoachRecords();
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
    await _loadCoachRecords();
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

  Future<void> _loadCoachRecords() async {
    setState(() => _coachRecordsLoading = true);
    try {
      final query = <String, dynamic>{};
      if (_coachFilterId != null) query['coach_id'] = _coachFilterId;
      if (_coachFilterDateFrom != null) query['date_from'] = _coachFilterDateFrom!.toIso8601String().substring(0, 10);
      if (_coachFilterDateTo != null) query['date_to'] = _coachFilterDateTo!.toIso8601String().substring(0, 10);
      final data = await ApiClient.instance.get('/attendance/coaches', query: query) as List;
      _coachRecords = data.cast<Map<String, dynamic>>();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _coachRecordsLoading = false);
    }
  }

  Future<void> _pickCoachFilterDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _coachFilterDateFrom : _coachFilterDateTo) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => isFrom ? _coachFilterDateFrom = picked : _coachFilterDateTo = picked);
    _loadCoachRecords();
  }

  Future<void> _openCoachManualEntry() async {
    final marked = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CoachManualEntryForm(coaches: _coaches),
    );
    if (marked == true) _loadCoachRecords();
  }

  Future<void> _openEditCoachRecord(Map<String, dynamic> r) async {
    String status = r['status'] as String? ?? 'PRESENT';
    final entryCtrl = TextEditingController(text: r['entry_time'] != null ? (r['entry_time'] as String).substring(11, 16) : '');
    final exitCtrl = TextEditingController(text: r['exit_time'] != null ? (r['exit_time'] as String).substring(11, 16) : '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Edit Coach Attendance — ${r['coach_name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: entryCtrl, decoration: const InputDecoration(labelText: 'Entry time (HH:MM)')),
              TextField(controller: exitCtrl, decoration: const InputDecoration(labelText: 'Exit time (HH:MM)')),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'PRESENT', child: Text('Present')),
                  DropdownMenuItem(value: 'ABSENT', child: Text('Absent')),
                  DropdownMenuItem(value: 'LEAVE', child: Text('Leave')),
                  DropdownMenuItem(value: 'INCOMPLETE', child: Text('Incomplete')),
                ],
                onChanged: (v) => setDialogState(() => status = v ?? status),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                try {
                  await ApiClient.instance.put('/attendance/coaches/${r['id']}', body: {
                    if (entryCtrl.text.trim().isNotEmpty) 'entry_time': '${entryCtrl.text.trim()}:00',
                    if (exitCtrl.text.trim().isNotEmpty) 'exit_time': '${exitCtrl.text.trim()}:00',
                    'status': status,
                  });
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
    entryCtrl.dispose();
    exitCtrl.dispose();
    if (saved == true) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coach attendance updated')));
      _loadCoachRecords();
    }
  }

  Future<void> _removeCoachRecord(Map<String, dynamic> r) async {
    final id = r['id'] as int;
    if (_removingCoachId == id) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete coach attendance record?'),
        content: Text('Delete this attendance record for ${r['coach_name']} on ${r['date']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _removingCoachId = id);
    try {
      await ApiClient.instance.delete('/attendance/coaches/$id');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coach attendance record deleted')));
      _loadCoachRecords();
    } on ApiException catch (e) {
      if (mounted) {
        final message = e.statusCode == 404 ? 'Already deleted — refreshing list' : e.message;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        if (e.statusCode == 404) _loadCoachRecords();
      }
    } finally {
      if (mounted) setState(() => _removingCoachId = null);
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
    if (_removingId == r.id) return; // already in flight — ignore a double tap
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
    setState(() => _removingId = r.id);
    try {
      await ApiClient.instance.delete('/attendance/students/${r.id}');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attendance record deleted')));
      _refreshAll();
    } on ApiException catch (e) {
      if (mounted) {
        // A 404 here means the record is already gone (deleted from another
        // session/device, or a duplicate tap raced this same request) — the
        // end state the admin wanted is already true, so refresh instead of
        // leaving a stale row on screen with a confusing permanent error.
        final message = e.statusCode == 404 ? 'Already deleted — refreshing list' : e.message;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        if (e.statusCode == 404) _refreshAll();
      }
    } finally {
      if (mounted) setState(() => _removingId = null);
    }
  }

  Future<String?> _promptReason(String title) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Reason (optional)'), maxLines: 2),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Confirm')),
        ],
      ),
    ).then((value) {
      ctrl.dispose();
      return value;
    });
  }

  Future<void> _decideApproval(AdminAttendanceRecord r, bool approve) async {
    setState(() => _approvalBusyId = r.id);
    try {
      if (approve) {
        await ApiClient.instance.put('/attendance/students/${r.id}/approve', body: {'note': null});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attendance approved and locked')));
      } else {
        final note = await _promptReason('Reason for rejecting');
        if (note == null) {
          setState(() => _approvalBusyId = null);
          return; // cancelled the dialog
        }
        await ApiClient.instance.put('/attendance/students/${r.id}/reject', body: {'note': note.isEmpty ? null : note});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attendance rejected and locked')));
      }
      _loadRecords();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _approvalBusyId = null);
    }
  }

  Color _approvalColor(String status) {
    switch (status) {
      case 'APPROVED':
        return AppColors.success;
      case 'REJECTED':
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  Future<void> _viewSelfie(AdminAttendanceRecord r) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Selfie — ${r.studentName}'),
        content: SizedBox(
          width: 280,
          height: 280,
          child: FutureBuilder<Uint8List>(
            future: ApiClient.instance.getBytes('/attendance/selfie/${r.id}').then((b) => Uint8List.fromList(b)),
            builder: (ctx, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return const Center(child: Text('Selfie not available.'));
              }
              return ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(snapshot.data!, fit: BoxFit.contain));
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
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
                          ),
                        )),
                  const SizedBox(height: 20),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    child: Text('Student Attendance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
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
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(child: Text(r.studentName, style: const TextStyle(fontWeight: FontWeight.bold))),
                                    Wrap(
                                      spacing: 4,
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
                                        Chip(
                                          label: Text(r.approvalStatus, style: const TextStyle(fontSize: 11, color: Colors.white)),
                                          backgroundColor: _approvalColor(r.approvalStatus),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${r.classDate} · ${r.activityName} · ${r.coachName ?? "-"} · ${r.markedManually ? "Manual" : "Coach"}',
                                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (r.hasSelfie)
                                      IconButton(icon: const Icon(Icons.photo_camera_outlined, size: 20), tooltip: 'View Selfie', onPressed: () => _viewSelfie(r)),
                                    if (r.approvalStatus == 'PENDING')
                                      _approvalBusyId == r.id
                                          ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                                          : Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.check_circle_outline, size: 20, color: AppColors.success),
                                                  tooltip: 'Approve',
                                                  onPressed: () => _decideApproval(r, true),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.cancel_outlined, size: 20, color: AppColors.danger),
                                                  tooltip: 'Reject',
                                                  onPressed: () => _decideApproval(r, false),
                                                ),
                                              ],
                                            ),
                                    IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _openEditRecord(r)),
                                    _removingId == r.id
                                        ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                                        : IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.danger), onPressed: () => _removeRecord(r)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        )),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Coach Attendance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      ElevatedButton.icon(
                        onPressed: _openCoachManualEntry,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Manual Entry'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      DropdownButton<int?>(
                        value: _coachFilterId,
                        hint: const Text('All coaches'),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('All coaches')),
                          ..._coaches.map((c) => DropdownMenuItem<int?>(value: c.id, child: Text(c.name))),
                        ],
                        onChanged: (v) {
                          setState(() => _coachFilterId = v);
                          _loadCoachRecords();
                        },
                      ),
                      OutlinedButton(
                        onPressed: () => _pickCoachFilterDate(true),
                        child: Text(_coachFilterDateFrom == null ? 'From date' : _coachFilterDateFrom!.toIso8601String().substring(0, 10)),
                      ),
                      OutlinedButton(
                        onPressed: () => _pickCoachFilterDate(false),
                        child: Text(_coachFilterDateTo == null ? 'To date' : _coachFilterDateTo!.toIso8601String().substring(0, 10)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_coachRecordsLoading)
                    const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
                  else if (_coachRecords.isEmpty)
                    const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No coach attendance records match these filters.')))
                  else
                    ..._coachRecords.map((r) {
                      final id = r['id'] as int;
                      final status = r['status'] as String? ?? 'PRESENT';
                      final entry = r['entry_time'] != null ? (r['entry_time'] as String).substring(11, 16) : '-';
                      final exit = r['exit_time'] != null ? (r['exit_time'] as String).substring(11, 16) : '-';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(r['coach_name'] as String? ?? '-'),
                          subtitle: Text('${r['date']} · Entry $entry · Exit $exit'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Chip(
                                label: Text(status, style: const TextStyle(fontSize: 11, color: Colors.white)),
                                backgroundColor: status == 'PRESENT'
                                    ? AppColors.success
                                    : status == 'ABSENT'
                                        ? AppColors.danger
                                        : AppColors.warning,
                                visualDensity: VisualDensity.compact,
                              ),
                              IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _openEditCoachRecord(r)),
                              _removingCoachId == id
                                  ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                                  : IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.danger), onPressed: () => _removeCoachRecord(r)),
                            ],
                          ),
                        ),
                      );
                    }),
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

class _CoachManualEntryForm extends StatefulWidget {
  final List<Coach> coaches;
  const _CoachManualEntryForm({required this.coaches});

  @override
  State<_CoachManualEntryForm> createState() => _CoachManualEntryFormState();
}

class _CoachManualEntryFormState extends State<_CoachManualEntryForm> {
  int? _coachId;
  DateTime _date = DateTime.now();
  TimeOfDay? _entryTime;
  TimeOfDay? _exitTime;
  String _status = 'PRESENT';
  bool _submitting = false;

  String _fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Future<void> _submit() async {
    if (_coachId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a coach')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await ApiClient.instance.post('/attendance/coaches/manual', body: {
        'coach_id': _coachId,
        'date': _date.toIso8601String().substring(0, 10),
        if (_entryTime != null) 'entry_time': _fmtTime(_entryTime!),
        if (_exitTime != null) 'exit_time': _fmtTime(_exitTime!),
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
            Text('Manual Coach Attendance Entry', style: Theme.of(context).textTheme.titleLarge),
            const Text('Bypasses geofencing — for correcting or backfilling records.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _coachId,
              decoration: const InputDecoration(labelText: 'Coach'),
              items: widget.coaches.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
              onChanged: (v) => setState(() => _coachId = v),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text(_date.toIso8601String().substring(0, 10)),
              onTap: () async {
                final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (picked != null) setState(() => _date = picked);
              },
            ),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Entry Time'),
                    subtitle: Text(_entryTime?.format(context) ?? '-'),
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: _entryTime ?? TimeOfDay.now());
                      if (picked != null) setState(() => _entryTime = picked);
                    },
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Exit Time'),
                    subtitle: Text(_exitTime?.format(context) ?? '-'),
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: _exitTime ?? TimeOfDay.now());
                      if (picked != null) setState(() => _exitTime = picked);
                    },
                  ),
                ),
              ],
            ),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'PRESENT', child: Text('Present')),
                DropdownMenuItem(value: 'ABSENT', child: Text('Absent')),
                DropdownMenuItem(value: 'LEAVE', child: Text('Leave')),
                DropdownMenuItem(value: 'INCOMPLETE', child: Text('Incomplete')),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'PRESENT'),
            ),
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
