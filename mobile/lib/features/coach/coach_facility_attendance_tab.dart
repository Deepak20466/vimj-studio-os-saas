import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/auth_storage.dart';
import '../../core/export_helper.dart';
import '../../core/models.dart';
import '../shared/notification_bell_action.dart';

const _monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _isoDate(DateTime d) => d.toIso8601String().substring(0, 10);
String _todayStr() => _isoDate(DateTime.now());

class CoachFacilityAttendanceTab extends StatefulWidget {
  const CoachFacilityAttendanceTab({super.key});

  @override
  State<CoachFacilityAttendanceTab> createState() => _CoachFacilityAttendanceTabState();
}

class _CoachFacilityAttendanceTabState extends State<CoachFacilityAttendanceTab> {
  int? _coachId;
  bool _reportDownloading = false;
  int _reportMonth = DateTime.now().month;
  int _reportYear = DateTime.now().year;

  List<dynamic> _myAttendance = [];
  bool _myAttendanceLoading = true;

  DateTime _dateFrom = DateTime.now();
  DateTime _dateTo = DateTime.now();
  List<AdminAttendanceRecord> _records = [];
  bool _recordsLoading = true;
  int? _busyId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final session = await AuthStorage.load();
    _coachId = session?.userId;
    _loadMyAttendance();
    _loadRecords();
  }

  Future<void> _loadMyAttendance() async {
    if (_coachId == null) return;
    setState(() => _myAttendanceLoading = true);
    try {
      final data = await ApiClient.instance.get('/coaches/$_coachId/attendance') as List;
      _myAttendance = data;
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _myAttendanceLoading = false);
    }
  }

  Future<void> _loadRecords() async {
    setState(() => _recordsLoading = true);
    try {
      final data = await ApiClient.instance.get('/attendance/students', query: {
        'date_from': _isoDate(_dateFrom),
        'date_to': _isoDate(_dateTo),
      }) as List;
      _records = data.map((e) => AdminAttendanceRecord.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _recordsLoading = false);
    }
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _dateFrom : _dateTo,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => isFrom ? _dateFrom = picked : _dateTo = picked);
    _loadRecords();
  }

  Future<void> _downloadMonthlyReport() async {
    setState(() => _reportDownloading = true);
    try {
      final bytes = await ApiClient.instance.getBytes('/reports/export/coach-monthly', query: {'month': _reportMonth, 'year': _reportYear, 'fmt': 'pdf'});
      final monthStr = _reportMonth.toString().padLeft(2, '0');
      await shareExportedFile(bytes, 'monthly_report_${_reportYear}_$monthStr.pdf');
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _reportDownloading = false);
    }
  }

  bool _canEdit(AdminAttendanceRecord r) => r.classDate == _todayStr();

  Future<void> _changeStatus(AdminAttendanceRecord r, String status) async {
    setState(() => _busyId = r.id);
    try {
      await ApiClient.instance.put('/attendance/students/${r.id}', body: {'status': status});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attendance updated')));
      _loadRecords();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _remove(AdminAttendanceRecord r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove attendance record?'),
        content: Text('Remove the attendance record for ${r.studentName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busyId = r.id);
    try {
      await ApiClient.instance.delete('/attendance/students/${r.id}');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attendance record deleted')));
      _loadRecords();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Color _statusColor(String status) => status == 'PRESENT' ? AppColors.success : (status == 'ABSENT' ? AppColors.danger : AppColors.warning);

  String _fmtTime(String? iso) {
    if (iso == null) return '-';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '-';
    final local = dt.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$h:${local.minute.toString().padLeft(2, '0')} $suffix';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance'), actions: const [NotificationBellAction(), SizedBox(width: 4)]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Monthly Report', style: Theme.of(context).textTheme.titleMedium),
                  const Text('Download a PDF of your students\' attendance and fee status for a month, broken down by activity.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      DropdownButton<int>(
                        value: _reportMonth,
                        items: List.generate(12, (i) => i + 1).map((m) => DropdownMenuItem(value: m, child: Text(_monthNames[m]))).toList(),
                        onChanged: (v) => setState(() => _reportMonth = v ?? _reportMonth),
                      ),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          keyboardType: TextInputType.number,
                          controller: TextEditingController(text: _reportYear.toString()),
                          onChanged: (v) => _reportYear = int.tryParse(v) ?? _reportYear,
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _reportDownloading ? null : _downloadMonthlyReport,
                        child: _reportDownloading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Download PDF'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('My Facility Attendance', style: Theme.of(context).textTheme.titleMedium),
                  const Text('Your own geofenced check-in/check-out history. Set only by Check In / Check Out on your Dashboard.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  const SizedBox(height: 10),
                  if (_myAttendanceLoading)
                    const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                  else if (_myAttendance.isEmpty)
                    const Text('No facility attendance recorded yet.', style: TextStyle(color: AppColors.textMuted))
                  else
                    ..._myAttendance.map((a) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text((a['date'] as String).substring(0, 10), style: const TextStyle(fontSize: 12)),
                              Text('In: ${_fmtTime(a['entry_time'] as String?)} · Out: ${_fmtTime(a['exit_time'] as String?)}', style: const TextStyle(fontSize: 12)),
                              Chip(
                                label: Text(a['status'] as String, style: const TextStyle(fontSize: 10, color: Colors.white)),
                                backgroundColor: a['status'] == 'PRESENT' ? AppColors.success : AppColors.danger,
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Student Attendance', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: () => _pickDate(true), child: Text('From ${_isoDate(_dateFrom)}'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: () => _pickDate(false), child: Text('To ${_isoDate(_dateTo)}'))),
            ],
          ),
          const SizedBox(height: 12),
          if (_recordsLoading)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
          else if (_records.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'No attendance records marked in this range. Records appear here once you mark student '
                  "attendance for a class — if you don't have any classes yet, ask your admin to assign you one.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            )
          else
            ..._records.map((r) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text(r.studentName, style: const TextStyle(fontWeight: FontWeight.bold))),
                            Chip(
                              label: Text(r.status, style: const TextStyle(fontSize: 10, color: Colors.white)),
                              backgroundColor: _statusColor(r.status),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        Text('${r.activityName} · ${r.classDate}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        const SizedBox(height: 8),
                        if (_busyId == r.id)
                          const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                        else if (_canEdit(r))
                          Wrap(
                            spacing: 6,
                            children: [
                              ...['PRESENT', 'ABSENT', 'LEAVE'].where((s) => s != r.status).map((s) => OutlinedButton(
                                    onPressed: () => _changeStatus(r, s),
                                    child: Text('Mark ${s[0]}${s.substring(1).toLowerCase()}'),
                                  )),
                              OutlinedButton(
                                onPressed: () => _remove(r),
                                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                                child: const Text('Delete'),
                              ),
                            ],
                          )
                        else
                          const Text('Locked (past class)', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}
