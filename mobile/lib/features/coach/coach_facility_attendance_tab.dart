import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/auth_storage.dart';
import '../../core/models.dart';
import '../shared/notification_bell_action.dart';

String _isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

class CoachFacilityAttendanceTab extends StatefulWidget {
  const CoachFacilityAttendanceTab({super.key});

  @override
  State<CoachFacilityAttendanceTab> createState() => _CoachFacilityAttendanceTabState();
}

class _CoachFacilityAttendanceTabState extends State<CoachFacilityAttendanceTab> {
  int? _coachId;

  List<dynamic> _myAttendance = [];
  bool _myAttendanceLoading = true;

  DateTime _viewMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  String? _selectedDate = _isoDate(DateTime.now());
  List<AdminAttendanceRecord> _records = [];
  bool _recordsLoading = true;

  DateTime get _monthStart => DateTime(_viewMonth.year, _viewMonth.month, 1);
  DateTime get _monthEnd => DateTime(_viewMonth.year, _viewMonth.month + 1, 0);
  int get _daysInMonth => _monthEnd.day;
  int get _leadingBlanks => _monthStart.weekday % 7; // 0 = Sunday

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final session = await AuthStorage.load();
    _coachId = session?.userId;
    _loadMyAttendance();
    _loadMonthRecords();
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

  Future<void> _loadMonthRecords() async {
    setState(() => _recordsLoading = true);
    try {
      final data = await ApiClient.instance.get('/attendance/students', query: {
        'date_from': _isoDate(_monthStart),
        'date_to': _isoDate(_monthEnd),
      }) as List;
      _records = data.map((e) => AdminAttendanceRecord.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _recordsLoading = false);
    }
  }

  Map<String, dynamic> get _facilityByDate {
    final map = <String, dynamic>{};
    for (final a in _myAttendance) {
      map[(a['date'] as String).substring(0, 10)] = a;
    }
    return map;
  }

  Map<String, List<AdminAttendanceRecord>> get _studentByDate {
    final map = <String, List<AdminAttendanceRecord>>{};
    for (final r in _records) {
      map.putIfAbsent(r.classDate, () => []).add(r);
    }
    return map;
  }

  void _goMonth(int delta) {
    setState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + delta, 1);
      _selectedDate = null;
    });
    _loadMonthRecords();
  }

  void _goToday() {
    final now = DateTime.now();
    setState(() {
      _viewMonth = DateTime(now.year, now.month, 1);
      _selectedDate = _isoDate(now);
    });
    _loadMonthRecords();
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

  Widget _dot(Color c) => Container(
        width: 6,
        height: 6,
        margin: const EdgeInsets.only(right: 2, top: 1),
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );

  Widget _dayCell(DateTime day) {
    final key = _isoDate(day);
    final facility = _facilityByDate[key];
    final students = _studentByDate[key] ?? const <AdminAttendanceRecord>[];
    final statuses = students.map((s) => s.status).toSet();
    final isToday = _isoDate(DateTime.now()) == key;
    final isSelected = _selectedDate == key;
    return GestureDetector(
      onTap: () => setState(() => _selectedDate = key),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandLight : AppColors.bg,
          border: Border.all(
            color: isToday || isSelected ? AppColors.brandOrange : AppColors.textMuted.withOpacity(0.25),
            width: isToday || isSelected ? 1.4 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${day.day}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Row(
              children: [
                if (facility != null) _dot(_statusColor(facility['status'] as String)),
                ...statuses.map((s) => _dot(_statusColor(s))),
              ],
            ),
            if (students.isNotEmpty)
              Text('${students.length}', style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendar() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _goMonth(-1)),
            Row(
              children: [
                Text(DateFormat('MMMM yyyy').format(_viewMonth), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 6),
                TextButton(onPressed: _goToday, child: const Text('Today')),
              ],
            ),
            IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _goMonth(1)),
          ],
        ),
        if (_recordsLoading || _myAttendanceLoading) const LinearProgressIndicator(),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 3,
          crossAxisSpacing: 3,
          childAspectRatio: 0.9,
          children: [
            for (final w in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
              Center(
                child: Text(w, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
              ),
            for (var i = 0; i < _leadingBlanks; i++) const SizedBox.shrink(),
            for (var d = 1; d <= _daysInMonth; d++) _dayCell(DateTime(_viewMonth.year, _viewMonth.month, d)),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailPanel() {
    final key = _selectedDate;
    if (key == null) {
      return const Text(
        'Click a day on the calendar above to view its attendance.',
        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
      );
    }
    final facility = _facilityByDate[key];
    final students = _studentByDate[key] ?? const <AdminAttendanceRecord>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(DateFormat('EEEE, MMM d, yyyy').format(DateTime.parse(key)), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 14),
        Text('My Facility Attendance', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        if (facility == null)
          const Text('No facility attendance marked on this date.', style: TextStyle(fontSize: 12, color: AppColors.textMuted))
        else
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(
                label: Text(facility['status'] as String, style: const TextStyle(fontSize: 10, color: Colors.white)),
                backgroundColor: _statusColor(facility['status'] as String),
                visualDensity: VisualDensity.compact,
              ),
              Text('Marked at ${_fmtTime(facility['entry_time'] as String?)} — locked', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
        const SizedBox(height: 18),
        Text('Student Attendance', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        if (students.isEmpty)
          const Text('No student attendance marked on this date.', style: TextStyle(fontSize: 12, color: AppColors.textMuted))
        else
          ...students.map((r) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.textMuted.withOpacity(0.2)),
                  borderRadius: BorderRadius.circular(8),
                ),
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
                    Text(r.activityName, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    if (r.hasSelfie) ...[
                      const SizedBox(height: 6),
                      OutlinedButton(onPressed: () => _viewPhoto(r), child: const Text('View Photo')),
                    ],
                  ],
                ),
              )),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance'), actions: const [NotificationBellAction(), SizedBox(width: 4)]),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadMyAttendance();
          await _loadMonthRecords();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(padding: const EdgeInsets.all(14), child: _buildCalendar()),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(padding: const EdgeInsets.all(14), child: _buildDetailPanel()),
            ),
          ],
        ),
      ),
    );
  }
}
