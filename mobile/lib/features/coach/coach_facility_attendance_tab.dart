import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/auth_storage.dart';
import '../../core/models.dart';
import '../shared/notification_bell_action.dart';

String _isoDate(DateTime d) => d.toIso8601String().substring(0, 10);

class CoachFacilityAttendanceTab extends StatefulWidget {
  const CoachFacilityAttendanceTab({super.key});

  @override
  State<CoachFacilityAttendanceTab> createState() => _CoachFacilityAttendanceTabState();
}

class _CoachFacilityAttendanceTabState extends State<CoachFacilityAttendanceTab> {
  int? _coachId;

  List<dynamic> _myAttendance = [];
  bool _myAttendanceLoading = true;

  DateTime _dateFrom = DateTime.now();
  DateTime _dateTo = DateTime.now();
  List<AdminAttendanceRecord> _records = [];
  bool _recordsLoading = true;

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

  Color _statusColor(String status) {
    if (status == 'PRESENT') return AppColors.success;
    if (status == 'ABSENT') return AppColors.danger;
    if (status == 'NOT_CONFIRM') return Colors.indigo;
    return AppColors.warning;
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

  String _approvalLabel(String status) => status == 'PENDING' ? 'Awaiting Admin' : status;

  Future<void> _viewPhoto(AdminAttendanceRecord r) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Photo — ${r.studentName}'),
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
                return const Center(child: Text('Photo not available.'));
              }
              return ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(snapshot.data!, fit: BoxFit.contain));
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

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
                  Text('My Facility Attendance', style: Theme.of(context).textTheme.titleMedium),
                  const Text('Your own manual attendance history — one entry per day, set from your Dashboard. Once submitted it can\'t be changed; only admin can correct it.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
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
                              Text('Marked at ${_fmtTime(a['entry_time'] as String?)}', style: const TextStyle(fontSize: 12)),
                              Chip(
                                label: Text(a['status'] as String, style: const TextStyle(fontSize: 10, color: Colors.white)),
                                backgroundColor: _statusColor(a['status'] as String),
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
                            Wrap(
                              spacing: 4,
                              children: [
                                Chip(
                                  label: Text(r.status, style: const TextStyle(fontSize: 10, color: Colors.white)),
                                  backgroundColor: _statusColor(r.status),
                                  visualDensity: VisualDensity.compact,
                                ),
                                Chip(
                                  label: Text(_approvalLabel(r.approvalStatus), style: const TextStyle(fontSize: 10, color: Colors.white)),
                                  backgroundColor: _approvalColor(r.approvalStatus),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          ],
                        ),
                        Text('${r.activityName} · ${r.classDate}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (r.hasSelfie)
                              OutlinedButton(
                                onPressed: () => _viewPhoto(r),
                                child: const Text('View Photo'),
                              ),
                            const Text('Locked', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          ],
                        ),
                      ],
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}
