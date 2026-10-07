import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/auth_storage.dart';
import '../../core/models.dart';
import '../../core/export_helper.dart';
import '../../core/search_utils.dart';
import '../shared/notification_bell_action.dart';

String _isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

const _coachAttendancePageSize = 500;

class CoachFacilityAttendanceTab extends StatefulWidget {
  const CoachFacilityAttendanceTab({super.key});

  @override
  State<CoachFacilityAttendanceTab> createState() =>
      _CoachFacilityAttendanceTabState();
}

class _CoachFacilityAttendanceTabState
    extends State<CoachFacilityAttendanceTab> {
  int? _coachId;

  List<dynamic> _myAttendance = [];
  bool _myAttendanceLoading = true;

  DateTime _viewMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  String? _selectedDate = _isoDate(DateTime.now());
  List<AdminAttendanceRecord> _records = [];
  bool _recordsLoading = true;
  String _attendanceSearch = '';
  bool _searchAllDates = false;
  List<AdminAttendanceRecord> _allDateSearchResults = [];
  bool _allDateSearchLoading = false;
  bool _allDateSearchHasMore = false;
  Timer? _allDateSearchDebounce;
  int _allDateSearchRequestId = 0;
  bool _showStudentAttendanceRecords = true;
  String? _attendanceStatusFilter;
  String? _approvalFilter;
  int? _activityFilter;

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

  @override
  void dispose() {
    _allDateSearchDebounce?.cancel();
    super.dispose();
  }

  void _onAttendanceSearchChanged(String value) {
    setState(() => _attendanceSearch = value);
    _allDateSearchDebounce?.cancel();
    if (_searchAllDates) {
      _allDateSearchDebounce = Timer(
        const Duration(milliseconds: 300),
        _searchAllAttendanceDates,
      );
    }
  }

  void _setSearchAllDates(bool value) {
    if (value == _searchAllDates) return;
    _allDateSearchDebounce?.cancel();
    setState(() {
      _searchAllDates = value;
      _allDateSearchRequestId++;
      _allDateSearchResults = [];
      _allDateSearchHasMore = false;
      _allDateSearchLoading = false;
    });
    if (value && _attendanceSearch.trim().isNotEmpty) {
      _searchAllAttendanceDates();
    }
  }

  Map<String, dynamic> _allDateSearchQuery({required int offset}) => {
        'search': _attendanceSearch.trim(),
        'limit': _coachAttendancePageSize,
        'offset': offset,
        if (_attendanceStatusFilter != null)
          'status_filter': _attendanceStatusFilter,
        if (_approvalFilter != null) 'approval_status': _approvalFilter,
        if (_activityFilter != null) 'activity_id': _activityFilter,
      };

  Future<void> _searchAllAttendanceDates() async {
    if (!mounted) return;
    _allDateSearchDebounce?.cancel();
    final term = _attendanceSearch.trim();
    final requestId = ++_allDateSearchRequestId;
    if (term.isEmpty || !_searchAllDates) {
      if (mounted) {
        setState(() {
          _allDateSearchResults = [];
          _allDateSearchHasMore = false;
          _allDateSearchLoading = false;
        });
      }
      return;
    }
    setState(() {
      _allDateSearchLoading = true;
      _allDateSearchHasMore = false;
      _allDateSearchResults = [];
    });
    try {
      final data = await ApiClient.instance.get('/attendance/students',
          query: _allDateSearchQuery(offset: 0)) as List;
      if (!mounted || requestId != _allDateSearchRequestId) return;
      setState(() {
        _allDateSearchResults = data
            .map((e) =>
                AdminAttendanceRecord.fromJson(e as Map<String, dynamic>))
            .toList();
        _allDateSearchHasMore = data.length == _coachAttendancePageSize;
      });
    } on ApiException catch (e) {
      if (mounted && requestId == _allDateSearchRequestId) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted && requestId == _allDateSearchRequestId) {
        setState(() => _allDateSearchLoading = false);
      }
    }
  }

  Future<void> _loadMoreAllDateSearchResults() async {
    if (!_allDateSearchHasMore || _allDateSearchLoading) return;
    final requestId = _allDateSearchRequestId;
    setState(() => _allDateSearchLoading = true);
    try {
      final data = await ApiClient.instance.get('/attendance/students',
              query: _allDateSearchQuery(offset: _allDateSearchResults.length))
          as List;
      if (!mounted || requestId != _allDateSearchRequestId) return;
      final knownIds = _allDateSearchResults.map((record) => record.id).toSet();
      final next = data
          .map((e) => AdminAttendanceRecord.fromJson(e as Map<String, dynamic>))
          .where((record) => knownIds.add(record.id));
      setState(() {
        _allDateSearchResults.addAll(next);
        _allDateSearchHasMore = data.length == _coachAttendancePageSize;
      });
    } on ApiException catch (e) {
      if (mounted && requestId == _allDateSearchRequestId) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted && requestId == _allDateSearchRequestId) {
        setState(() => _allDateSearchLoading = false);
      }
    }
  }

  Future<void> _loadMyAttendance() async {
    if (_coachId == null) return;
    setState(() => _myAttendanceLoading = true);
    try {
      final data =
          await ApiClient.instance.get('/coaches/$_coachId/attendance') as List;
      _myAttendance = data;
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _myAttendanceLoading = false);
    }
  }

  Future<void> _loadMonthRecords() async {
    setState(() => _recordsLoading = true);
    try {
      final data = await ApiClient.instance.getAllPages(
        '/attendance/students',
        query: {
          'date_from': _isoDate(_monthStart),
          'date_to': _isoDate(_monthEnd),
        },
      );
      _records = data
          .map((e) => AdminAttendanceRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
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

  Future<void> _export(String kind, {String? day}) async {
    try {
      final query = <String, dynamic>{
        'month': _viewMonth.month,
        'year': _viewMonth.year,
        'kind': kind,
        'fmt': 'pdf'
      };
      if (day != null) query['day'] = int.parse(day.substring(8, 10));
      final bytes = await ApiClient.instance.getBytes('/reports', query: query);
      await shareExportedFile(bytes,
          '${kind}_${_viewMonth.year}_${_viewMonth.month}${day == null ? '' : '_$day'}.pdf');
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    }
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

  String _approvalLabel(String status) =>
      status == 'PENDING' ? 'Awaiting Admin' : status;

  Future<void> _viewPhoto(AdminAttendanceRecord r) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Photo — ${r.studentName}'),
        content: SizedBox(
          width: 280,
          height: 280,
          child: FutureBuilder<Uint8List>(
            future: ApiClient.instance
                .getBytes('/attendance/selfie/${r.id}')
                .then((b) => Uint8List.fromList(b)),
            builder: (ctx, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return const Center(child: Text('Photo not available.'));
              }
              return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(snapshot.data!, fit: BoxFit.contain));
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close'))
        ],
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
            color: isToday || isSelected
                ? AppColors.brandOrange
                : AppColors.textMuted.withOpacity(0.25),
            width: isToday || isSelected ? 1.4 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${day.day}',
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Row(
              children: [
                if (facility != null)
                  _dot(_statusColor(facility['status'] as String)),
                ...statuses.map((s) => _dot(_statusColor(s))),
              ],
            ),
            if (students.isNotEmpty)
              Text('${students.length}',
                  style:
                      const TextStyle(fontSize: 9, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendar() {
    return Column(
      children: [
        Row(
          children: [
            IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _goMonth(-1)),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      DateFormat('MMMM yyyy').format(_viewMonth),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: _goToday,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Today'),
                  ),
                ],
              ),
            ),
            IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _goMonth(1)),
          ],
        ),
        if (_recordsLoading || _myAttendanceLoading)
          const LinearProgressIndicator(),
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
                child: Text(w,
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textMuted)),
              ),
            for (var i = 0; i < _leadingBlanks; i++) const SizedBox.shrink(),
            for (var d = 1; d <= _daysInMonth; d++)
              _dayCell(DateTime(_viewMonth.year, _viewMonth.month, d)),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailPanel({
    bool includeHeader = true,
    bool includeToolbar = true,
    bool includeResults = true,
  }) {
    final key = _selectedDate;
    if (key == null && !_searchAllDates) {
      return const Text(
        'Click a day on the calendar above to view its attendance.',
        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
      );
    }
    final facility = key == null ? null : _facilityByDate[key];
    final students = _searchAllDates
        ? _allDateSearchResults
        : (key == null
            ? const <AdminAttendanceRecord>[]
            : _studentByDate[key] ?? const <AdminAttendanceRecord>[]);
    final visibleStudents = students
        .where((r) =>
            matchesSearchQuery(
              [
                r.studentName,
                r.activityName,
                r.status,
                r.approvalStatus,
                r.classDate,
                r.timestamp,
                r.id,
                r.studentId,
                r.classId,
                r.activityId,
                r.coachName,
              ],
              _attendanceSearch,
            ) &&
            (_attendanceStatusFilter == null ||
                r.status == _attendanceStatusFilter) &&
            (_approvalFilter == null || _approvalFilter == r.approvalStatus) &&
            (_activityFilter == null || r.activityId == _activityFilter))
        .toList();
    final activityNames = <int, String>{
      for (final record in [..._records, ..._allDateSearchResults])
        record.activityId: record.activityName,
    };
    if (_activityFilter != null) {
      activityNames.putIfAbsent(
          _activityFilter!, () => 'Activity $_activityFilter');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (includeHeader) ...[
          Text(
              _searchAllDates
                  ? 'Attendance across all dates'
                  : DateFormat('EEEE, MMM d, yyyy')
                      .format(DateTime.parse(key!)),
              style: Theme.of(context).textTheme.titleMedium),
          if (!_searchAllDates) ...[
            const SizedBox(height: 14),
            Text('My Facility Attendance',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            if (facility == null)
              const Text('No facility attendance marked on this date.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted))
            else
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(
                    label: Text(facility['status'] as String,
                        style:
                            const TextStyle(fontSize: 10, color: Colors.white)),
                    backgroundColor: _statusColor(facility['status'] as String),
                    visualDensity: VisualDensity.compact,
                  ),
                  Text(
                      'Marked at ${_fmtTime(facility['entry_time'] as String?)} — locked',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            const SizedBox(height: 18),
          ],
          Row(
            children: [
              Expanded(
                child: Text('Student Attendance',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              if (!_showStudentAttendanceRecords)
                Tooltip(
                  message: '${visibleStudents.length} matching student records',
                  child: Chip(
                    label: Text('${visibleStudents.length}'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              if (!_showStudentAttendanceRecords)
                TextButton.icon(
                  key: const ValueKey('toggle-coach-student-attendance'),
                  onPressed: () =>
                      setState(() => _showStudentAttendanceRecords = true),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Show'),
                ),
            ],
          ),
        ],
        if (includeToolbar && _showStudentAttendanceRecords)
          _buildStudentAttendanceToolbar(),
        if (includeResults && _showStudentAttendanceRecords) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              DropdownButton<String?>(
                value: _attendanceStatusFilter,
                hint: const Text('All statuses'),
                items: const [
                  DropdownMenuItem<String?>(
                      value: null, child: Text('All statuses')),
                  DropdownMenuItem<String?>(
                      value: 'PRESENT', child: Text('Present')),
                  DropdownMenuItem<String?>(
                      value: 'ABSENT', child: Text('Absent')),
                  DropdownMenuItem<String?>(
                      value: 'LEAVE', child: Text('Leave')),
                  DropdownMenuItem<String?>(
                      value: 'NOT_CONFIRM', child: Text('Not Confirm')),
                ],
                onChanged: (v) {
                  setState(() => _attendanceStatusFilter = v);
                  if (_searchAllDates) _searchAllAttendanceDates();
                },
              ),
              DropdownButton<String?>(
                value: _approvalFilter,
                hint: const Text('All reviews'),
                items: const [
                  DropdownMenuItem<String?>(
                      value: null, child: Text('All reviews')),
                  DropdownMenuItem<String?>(
                      value: 'PENDING', child: Text('Pending')),
                  DropdownMenuItem<String?>(
                      value: 'APPROVED', child: Text('Approved')),
                  DropdownMenuItem<String?>(
                      value: 'REJECTED', child: Text('Rejected')),
                ],
                onChanged: (v) {
                  setState(() => _approvalFilter = v);
                  if (_searchAllDates) _searchAllAttendanceDates();
                },
              ),
              DropdownButton<int?>(
                value: _activityFilter,
                hint: const Text('All activities'),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('All activities')),
                  ...activityNames.entries
                      .map((entry) => DropdownMenuItem<int?>(
                            value: entry.key,
                            child: Text(entry.value),
                          )),
                ],
                onChanged: (v) {
                  setState(() => _activityFilter = v);
                  if (_searchAllDates) _searchAllAttendanceDates();
                },
              ),
              if (_attendanceSearch.isNotEmpty ||
                  _attendanceStatusFilter != null ||
                  _approvalFilter != null ||
                  _activityFilter != null)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _attendanceSearch = '';
                      _attendanceStatusFilter = null;
                      _approvalFilter = null;
                      _activityFilter = null;
                    });
                    if (_searchAllDates) _searchAllAttendanceDates();
                  },
                  child: const Text('Clear filters'),
                ),
            ],
          ),
          if (_searchAllDates && _attendanceSearch.trim().isEmpty)
            const Text(
                'Enter a search term to search attendance across all dates.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted))
          else if (_allDateSearchLoading && _allDateSearchResults.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (students.isEmpty && _searchAllDates)
            const Text(
                'No attendance records match this search across all dates.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted))
          else if (students.isEmpty)
            const Text('No student attendance marked on this date.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted))
          else if (visibleStudents.isEmpty)
            const Text('No student attendance matches this search.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted))
          else
            ...visibleStudents.map((r) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: AppColors.textMuted.withOpacity(0.2)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(r.studentName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 4,
                              children: [
                                Chip(
                                  label: Text(r.status,
                                      style: const TextStyle(
                                          fontSize: 10, color: Colors.white)),
                                  backgroundColor: _statusColor(r.status),
                                  visualDensity: VisualDensity.compact,
                                ),
                                Chip(
                                  label: Text(_approvalLabel(r.approvalStatus),
                                      style: const TextStyle(
                                          fontSize: 10, color: Colors.white)),
                                  backgroundColor:
                                      _approvalColor(r.approvalStatus),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Text(r.activityName,
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                      if (_searchAllDates)
                        Text(r.classDate,
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 12)),
                      if (r.hasSelfie) ...[
                        const SizedBox(height: 6),
                        OutlinedButton(
                            onPressed: () => _viewPhoto(r),
                            child: const Text('View Photo')),
                      ],
                    ],
                  ),
                )),
          if (_searchAllDates && _allDateSearchHasMore)
            Center(
              child: OutlinedButton.icon(
                onPressed: _allDateSearchLoading
                    ? null
                    : _loadMoreAllDateSearchResults,
                icon: _allDateSearchLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more),
                label: Text(_allDateSearchLoading
                    ? 'Loading more matches…'
                    : 'Load more matches'),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildStudentAttendanceToolbar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  labelText: 'Search attendance',
                  hintText: _searchAllDates
                      ? 'Search all attendance dates'
                      : 'Student, activity, or status',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _attendanceSearch.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'Clear search',
                          onPressed: () => _onAttendanceSearchChanged(''),
                        ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: _onAttendanceSearchChanged,
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Hide student attendance records',
              child: TextButton.icon(
                key: const ValueKey('toggle-coach-student-attendance'),
                onPressed: () =>
                    setState(() => _showStudentAttendanceRecords = false),
                icon: const Icon(Icons.visibility_off_outlined),
                label: const Text('Hide'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ToggleButtons(
          key: const ValueKey('coach-attendance-search-scope'),
          isSelected: [!_searchAllDates, _searchAllDates],
          onPressed: (index) => _setSearchAllDates(index == 1),
          constraints: const BoxConstraints(minHeight: 30, minWidth: 112),
          borderRadius: BorderRadius.circular(8),
          children: const [Text('Selected day'), Text('All dates')],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('Attendance'),
          actions: const [NotificationBellAction(), SizedBox(width: 4)]),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadMyAttendance();
          await _loadMonthRecords();
        },
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Wrap(spacing: 8, children: [
                    OutlinedButton(
                        onPressed: _selectedDate == null
                            ? null
                            : () =>
                                _export('classes_detail', day: _selectedDate),
                        child: const Text('Day Classes & Attendance PDF')),
                    OutlinedButton(
                        onPressed: () => _export('students_summary'),
                        child: const Text('Monthly Attendance & Classes PDF')),
                    OutlinedButton(
                        onPressed: () => _export('fees_paid'),
                        child: const Text('Fees Paid PDF')),
                    OutlinedButton(
                        onPressed: () => _export('fees_pending'),
                        child: const Text('Fees Pending PDF')),
                  ]),
                  Card(
                    child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: _buildCalendar()),
                  ),
                  const SizedBox(height: 16),
                ]),
              ),
            ),
            if (_selectedDate == null && !_searchAllDates)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: _buildDetailPanel(),
                    ),
                  ),
                ),
              )
            else if (_showStudentAttendanceRecords)
              SliverMainAxisGroup(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: _buildDetailPanel(
                            includeToolbar: false,
                            includeResults: false,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _CoachAttendanceSearchHeaderDelegate(
                      child: _buildStudentAttendanceToolbar(),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: _buildDetailPanel(
                            includeHeader: false,
                            includeToolbar: false,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 72)),
                ],
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: _buildDetailPanel(
                        includeToolbar: false,
                        includeResults: false,
                      ),
                    ),
                  ),
                ),
              ),
            const SliverPadding(
              padding: EdgeInsets.only(bottom: 90),
              sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoachAttendanceSearchHeaderDelegate
    extends SliverPersistentHeaderDelegate {
  const _CoachAttendanceSearchHeaderDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => 120;

  @override
  double get maxExtent => 120;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);
    return SizedBox.expand(
      child: Material(
        color: theme.colorScheme.surface,
        elevation: overlapsContent ? 2 : 0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: child,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_CoachAttendanceSearchHeaderDelegate oldDelegate) =>
      child != oldDelegate.child;
}
