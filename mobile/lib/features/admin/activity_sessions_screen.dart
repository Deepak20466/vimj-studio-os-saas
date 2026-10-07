import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/models.dart';
import '../shared/pinned_search_section.dart';

const _allDays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const _allMonths = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
const _monthNames = [
  '',
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec'
];
const _statusOptions = ['PRESENT', 'ABSENT', 'LEAVE', 'NOT_CONFIRM'];

String _sessionLabel(String s) => s == 'NOT_CONFIRM'
    ? 'Not Confirm'
    : (s.isEmpty ? s : (s[0] + s.substring(1).toLowerCase()));

Color _statusColor(String status) {
  if (status == 'PRESENT') return AppColors.success;
  if (status == 'UNMARKED') return AppColors.warning;
  if (status == 'NOT_CONFIRM') return Colors.indigo;
  return AppColors.danger;
}

class ActivitySessionsScreen extends StatefulWidget {
  final Activity activity;
  const ActivitySessionsScreen({super.key, required this.activity});

  @override
  State<ActivitySessionsScreen> createState() => _ActivitySessionsScreenState();
}

class _ActivitySessionsScreenState extends State<ActivitySessionsScreen> {
  List<Batch> _batches = [];
  List<Coach> _coaches = [];
  bool _loading = true;
  int? _removingId;
  String _search = '';
  int? _coachFilter;
  String? _dayFilter;
  String? _locationFilter;

  List<Batch> get _visibleBatches => _batches.where((b) {
        final query = _search.trim().toLowerCase();
        final matchesSearch = query.isEmpty ||
            '${_sessionLabel(b.sessionPeriod)} ${b.startTime} ${b.endTime} '
                    '${b.daysOfWeek.join(' ')} ${b.location} ${_coachName(b.coachId)}'
                .toLowerCase()
                .contains(query);
        return matchesSearch &&
            (_coachFilter == null || b.coachId == _coachFilter) &&
            (_dayFilter == null || b.daysOfWeek.contains(_dayFilter)) &&
            (_locationFilter == null || b.location == _locationFilter);
      }).toList();

  bool get _hasFilters =>
      _search.isNotEmpty ||
      _coachFilter != null ||
      _dayFilter != null ||
      _locationFilter != null;

  Widget _filters() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(
                labelText: 'Search sessions',
                hintText: 'Coach, location, day, or time',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () => setState(() => _search = ''),
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear search',
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<int?>(
                  value: _coachFilter,
                  hint: const Text('All coaches'),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('All coaches')),
                    ..._coaches.map((c) => DropdownMenuItem<int?>(
                        value: c.id, child: Text(c.name))),
                  ],
                  onChanged: (value) => setState(() => _coachFilter = value),
                ),
                DropdownButton<String?>(
                  value: _dayFilter,
                  hint: const Text('All days'),
                  items: const [
                    DropdownMenuItem<String?>(
                        value: null, child: Text('All days')),
                    DropdownMenuItem(value: 'MON', child: Text('Monday')),
                    DropdownMenuItem(value: 'TUE', child: Text('Tuesday')),
                    DropdownMenuItem(value: 'WED', child: Text('Wednesday')),
                    DropdownMenuItem(value: 'THU', child: Text('Thursday')),
                    DropdownMenuItem(value: 'FRI', child: Text('Friday')),
                    DropdownMenuItem(value: 'SAT', child: Text('Saturday')),
                    DropdownMenuItem(value: 'SUN', child: Text('Sunday')),
                  ],
                  onChanged: (value) => setState(() => _dayFilter = value),
                ),
                DropdownButton<String?>(
                  value: _locationFilter,
                  hint: const Text('All locations'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('All locations')),
                    ..._batches.map((b) => b.location).toSet().map((location) =>
                        DropdownMenuItem<String?>(
                            value: location, child: Text(location))),
                  ],
                  onChanged: (value) => setState(() => _locationFilter = value),
                ),
                if (_hasFilters)
                  TextButton(
                    onPressed: () => setState(() {
                      _search = '';
                      _coachFilter = null;
                      _dayFilter = null;
                      _locationFilter = null;
                    }),
                    child: const Text('Clear filters'),
                  ),
              ],
            ),
          ],
        ),
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiClient.instance
            .get('/batches', query: {'activity_id': widget.activity.id}),
        ApiClient.instance.get('/coaches'),
      ]);
      _batches = (results[0] as List)
          .map((e) => Batch.fromJson(e as Map<String, dynamic>))
          .toList();
      _coaches = (results[1] as List)
          .map((e) => Coach.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _coachName(int? id) {
    if (id == null) return 'Unassigned';
    return _coaches
        .firstWhere((c) => c.id == id,
            orElse: () =>
                Coach(id: id, name: '#$id', email: '', isActive: true))
        .name;
  }

  Future<void> _openForm({Batch? batch}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SessionForm(
          activity: widget.activity, coaches: _coaches, editing: batch),
    );
    if (saved == true) _load();
  }

  Future<void> _remove(Batch b) async {
    if (_removingId == b.id) return; // already in flight — ignore a double tap
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete session?'),
        content: Text(
            'Delete this session (${_sessionLabel(b.sessionPeriod)}, ${b.startTime}-${b.endTime})? This also removes its generated classes and attendance.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _removingId = b.id);
    try {
      await ApiClient.instance.delete('/batches/${b.id}');
      _load();
    } on ApiException catch (e) {
      if (mounted) {
        // A 404 means this session is already gone (deleted elsewhere, or a
        // duplicate tap raced this same request) — refresh instead of leaving
        // a stale card on screen with a confusing permanent error.
        final message = e.statusCode == 404
            ? 'Already deleted — refreshing list'
            : e.message;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
        if (e.statusCode == 404) _load();
      }
    } finally {
      if (mounted) setState(() => _removingId = null);
    }
  }

  void _openRoster(Batch b) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            _SessionRosterScreen(activity: widget.activity, batch: b)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sessions: ${widget.activity.name}')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'sessions-fab',
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add Session'),
      ),
      body: _loading && _batches.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 90),
                children: [
                  PinnedSearchSection(
                    padding: EdgeInsets.zero,
                    search: _filters(),
                    results: ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount:
                          _visibleBatches.isEmpty ? 1 : _visibleBatches.length,
                      itemBuilder: (context, i) {
                        if (_visibleBatches.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(
                              child: Text(_batches.isEmpty
                                  ? 'No sessions scheduled yet for this activity.'
                                  : 'No results found.'),
                            ),
                          );
                        }
                        final b = _visibleBatches[i];
                        return Card(
                          margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                        child: Text(
                                            '${_sessionLabel(b.sessionPeriod)} · ${b.startTime}-${b.endTime}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold))),
                                    _removingId == b.id
                                        ? const Padding(
                                            padding: EdgeInsets.all(10),
                                            child: SizedBox(
                                                height: 16,
                                                width: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2)))
                                        : PopupMenuButton<String>(
                                            onSelected: (v) {
                                              if (v == 'roster') _openRoster(b);
                                              if (v == 'edit')
                                                _openForm(batch: b);
                                              if (v == 'delete') _remove(b);
                                            },
                                            itemBuilder: (_) => [
                                              const PopupMenuItem(
                                                  value: 'roster',
                                                  child: Text('Roster')),
                                              const PopupMenuItem(
                                                  value: 'edit',
                                                  child: Text('Edit')),
                                              const PopupMenuItem(
                                                  value: 'delete',
                                                  child: Text('Delete')),
                                            ],
                                          ),
                                  ],
                                ),
                                Text('Days: ${b.daysOfWeek.join(", ")}',
                                    style: const TextStyle(
                                        color: AppColors.textMuted)),
                                Text('Location: ${b.location}',
                                    style: const TextStyle(
                                        color: AppColors.textMuted)),
                                Text('Coach: ${_coachName(b.coachId)}',
                                    style: const TextStyle(
                                        color: AppColors.textMuted)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SessionForm extends StatefulWidget {
  final Activity activity;
  final List<Coach> coaches;
  final Batch? editing;
  const _SessionForm(
      {required this.activity, required this.coaches, this.editing});

  @override
  State<_SessionForm> createState() => _SessionFormState();
}

class _SessionFormState extends State<_SessionForm> {
  int? _coachId;
  late final _locationCtrl =
      TextEditingController(text: widget.editing?.location ?? '');
  String _sessionPeriod = 'MORNING';
  TimeOfDay _startTime = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 8, minute: 0);
  late List<String> _days = List.of(widget.editing?.daysOfWeek ?? []);
  late List<int> _months = List.of(widget.editing?.activeMonths ?? _allMonths);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _coachId = widget.editing?.coachId;
    if (widget.editing != null) {
      _sessionPeriod = widget.editing!.sessionPeriod;
      final st = widget.editing!.startTime.split(':');
      final et = widget.editing!.endTime.split(':');
      _startTime = TimeOfDay(hour: int.parse(st[0]), minute: int.parse(st[1]));
      _endTime = TimeOfDay(hour: int.parse(et[0]), minute: int.parse(et[1]));
    }
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Future<void> _submit() async {
    if (_locationCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Location is required')));
      return;
    }
    if (_days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select at least one day')));
      return;
    }
    setState(() => _saving = true);
    try {
      final body = {
        'activity_id': widget.activity.id,
        'coach_id': _coachId,
        'location': _locationCtrl.text.trim(),
        'session_period': _sessionPeriod,
        'start_time': _fmtTime(_startTime),
        'end_time': _fmtTime(_endTime),
        'days_of_week': _days,
        'active_months': _months,
      };
      if (widget.editing != null) {
        await ApiClient.instance
            .put('/batches/${widget.editing!.id}', body: body);
      } else {
        await ApiClient.instance.post('/batches', body: body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _locationCtrl.dispose();
    super.dispose();
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.brandYellow);

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing != null;
    return Padding(
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                editing
                    ? 'Edit Session'
                    : 'Add Session: ${widget.activity.name}',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
                controller: _locationCtrl,
                decoration: const InputDecoration(labelText: 'Location')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _sessionPeriod,
              decoration: const InputDecoration(labelText: 'Session'),
              items: const [
                DropdownMenuItem(value: 'MORNING', child: Text('Morning')),
                DropdownMenuItem(value: 'AFTERNOON', child: Text('Afternoon')),
                DropdownMenuItem(value: 'EVENING', child: Text('Evening')),
              ],
              onChanged: (v) => setState(() => _sessionPeriod = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _coachId,
              decoration: const InputDecoration(labelText: 'Coach'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Unassigned')),
                ...widget.coaches.map(
                    (c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
              ],
              onChanged: (v) => setState(() => _coachId = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Start Time'),
                    subtitle: Text(_startTime.format(context)),
                    onTap: () async {
                      final picked = await showTimePicker(
                          context: context, initialTime: _startTime);
                      if (picked != null) setState(() => _startTime = picked);
                    },
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('End Time'),
                    subtitle: Text(_endTime.format(context)),
                    onTap: () async {
                      final picked = await showTimePicker(
                          context: context, initialTime: _endTime);
                      if (picked != null) setState(() => _endTime = picked);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Days', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _allDays
                    .map((d) => _chip(
                        d,
                        _days.contains(d),
                        () => setState(() => _days.contains(d)
                            ? _days.remove(d)
                            : _days.add(d))))
                    .toList()),
            const SizedBox(height: 12),
            Text('Active Months',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _allMonths
                    .map((m) => _chip(
                        _monthNames[m],
                        _months.contains(m),
                        () => setState(() => _months.contains(m)
                            ? _months.remove(m)
                            : _months.add(m))))
                    .toList()),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(editing ? 'Save' : 'Create'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionRosterScreen extends StatefulWidget {
  final Activity activity;
  final Batch batch;
  const _SessionRosterScreen({required this.activity, required this.batch});

  @override
  State<_SessionRosterScreen> createState() => _SessionRosterScreenState();
}

class _SessionRosterScreenState extends State<_SessionRosterScreen> {
  DateTime _classDate = DateTime.now();
  Map<String, dynamic>? _roster;
  bool _loading = true;
  int? _updatingId;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.instance
          .get('/batches/${widget.batch.id}/roster', query: {
        'class_date': _classDate.toIso8601String().substring(0, 10)
      }) as Map<String, dynamic>;
      _roster = data;
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
        context: context,
        initialDate: _classDate,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (picked == null) return;
    setState(() => _classDate = picked);
    _load();
  }

  Future<void> _setStatus(int studentId, String status) async {
    final classId = _roster?['class_id'];
    if (classId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'No class session exists for this date yet. Generate sessions for this batch first.')));
      return;
    }
    setState(() => _updatingId = studentId);
    try {
      await ApiClient.instance.post('/attendance/mark-student/manual', body: {
        'class_id': classId,
        'student_id': studentId,
        'status': status
      });
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Attendance updated')));
      await _load();
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _updatingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roster = _roster;
    final allStudents =
        (roster?['students'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final q = _search.trim().toLowerCase();
    final students = q.isEmpty
        ? allStudents
        : allStudents
            .where(
                (s) => (s['student_name'] as String).toLowerCase().contains(q))
            .toList();
    return Scaffold(
      appBar: AppBar(
          title: Text(
              '${widget.activity.name} — ${_sessionLabel(widget.batch.sessionPeriod)} (${widget.batch.startTime}-${widget.batch.endTime})')),
      body: _loading && _roster == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Row(
                    children: [
                      OutlinedButton.icon(
                          onPressed: _pickDate,
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(
                              _classDate.toIso8601String().substring(0, 10))),
                      const SizedBox(width: 16),
                      if (roster != null)
                        Expanded(
                          child: Text(
                            'Present: ${roster['present_count']} · Absent/Leave: ${roster['absent_count']} · Not Confirm: ${roster['not_confirm_count']} · Unmarked: ${roster['unmarked_count']}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textMuted),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    decoration: const InputDecoration(
                        hintText: 'Search students...',
                        prefixIcon: Icon(Icons.search)),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                if (roster?['class_id'] != null)
                  TextButton.icon(
                    icon: Icon(roster?['has_group_photo'] == true
                        ? Icons.photo
                        : Icons.photo_outlined),
                    label: Text(roster?['has_group_photo'] == true
                        ? 'View Session Photo'
                        : 'No Session Photo Uploaded'),
                    onPressed: roster?['has_group_photo'] == true
                        ? () => showDialog<void>(
                            context: context,
                            builder: (_) => AlertDialog(
                                    title: const Text('Session Photo'),
                                    content: FutureBuilder<List<int>>(
                                        future: ApiClient.instance.getBytes(
                                            '/activities/classes/${roster!['class_id']}/group-photo'),
                                        builder: (context, snapshot) {
                                          if (snapshot.hasError)
                                            return const Text(
                                                'Photo could not be loaded');
                                          if (!snapshot.hasData)
                                            return const CircularProgressIndicator();
                                          return Image.memory(
                                              Uint8List.fromList(
                                                  snapshot.data!));
                                        }),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('Close'))
                                    ]))
                        : null,
                  ),
                if (roster != null && roster['class_id'] == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                        'No class session was generated for this batch on this date. Marking is disabled until one exists.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textMuted)),
                  ),
                Expanded(
                  child: students.isEmpty
                      ? Center(
                          child: Text(allStudents.isEmpty
                              ? 'No students enrolled in this activity yet.'
                              : 'No students match "$_search".'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                          itemCount: students.length,
                          itemBuilder: (context, i) {
                            final s = students[i];
                            final status = s['attendance_status'] as String;
                            final feeStatus = s['fee_status'] as String?;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                            child: Text(
                                                s['student_name'] as String,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold))),
                                        Chip(
                                          label: Text(status,
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.white)),
                                          backgroundColor: _statusColor(status),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        if (feeStatus != null) ...[
                                          const SizedBox(width: 6),
                                          Chip(
                                            label: Text(feeStatus,
                                                style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.white)),
                                            backgroundColor: feeStatus == 'PAID'
                                                ? AppColors.success
                                                : AppColors.danger,
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    _updatingId == s['student_id']
                                        ? const Center(
                                            child: SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2)))
                                        : Wrap(
                                            spacing: 6,
                                            children: _statusOptions
                                                .map((opt) => ChoiceChip(
                                                      label: Text(
                                                          _sessionLabel(opt)),
                                                      selected: status == opt,
                                                      onSelected: roster?[
                                                                  'class_id'] ==
                                                              null
                                                          ? null
                                                          : (_) => _setStatus(
                                                              s['student_id']
                                                                  as int,
                                                              opt),
                                                    ))
                                                .toList(),
                                          ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
