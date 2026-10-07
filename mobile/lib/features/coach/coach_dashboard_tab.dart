import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api_client.dart';
import '../../core/auth_storage.dart';
import '../../core/models.dart';
import '../../core/offline_queue.dart';
import '../../core/sync_service.dart';
import 'mark_attendance_screen.dart';
import '../shared/notification_bell_action.dart';
import '../shared/pinned_search_section.dart';

const _myAttendanceStatusLabels = {
  'PRESENT': 'Present',
  'ABSENT': 'Absent',
  'NOT_CONFIRM': 'Not Confirm'
};

class CoachDashboardTab extends StatefulWidget {
  const CoachDashboardTab({super.key});

  @override
  State<CoachDashboardTab> createState() => _CoachDashboardTabState();
}

class _CoachDashboardTabState extends State<CoachDashboardTab> {
  List<ClassSession> _classes = [];
  Map<int, Map<String, dynamic>> _summaries = {};
  bool _loading = false;
  bool _classesLoaded = false;
  bool _attendanceLoaded = false;
  bool _attendanceError = false;
  String? _error;
  String _coachName = '';
  String? _myStatus;
  String? _pendingStatus;
  bool _actionLoading = false;
  int _pendingSync = 0;
  String _classSearch = '';
  int? _activityFilter;
  int _loadVersion = 0;

  List<ClassSession> get _visibleClasses => _classes
      .where((c) =>
          'class ${c.id} activity ${c.activityId} ${c.startTime} ${c.endTime}'
              .toLowerCase()
              .contains(_classSearch.trim().toLowerCase()) &&
          (_activityFilter == null || c.activityId == _activityFilter))
      .toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await AuthStorage.load();
      if (!mounted || version != _loadVersion) return;
      setState(() => _coachName = session?.name ?? '');
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await Future.wait([
        _loadClasses(today, version),
        _loadAttendance(session, today, version),
        _loadPendingSync(version),
      ]);
    } catch (_) {
      if (mounted && version == _loadVersion) {
        setState(
            () => _error = 'Could not load dashboard data. Pull to retry.');
      }
    } finally {
      if (mounted && version == _loadVersion) setState(() => _loading = false);
    }
  }

  Future<void> _loadClasses(String today, int version) async {
    try {
      final data = await ApiClient.instance.get(
        '/activities/classes/my',
        query: {'class_date': today},
      ) as List;
      final classes = data
          .map((e) => ClassSession.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _classes = classes;
        _classesLoaded = true;
      });
      unawaited(_loadClassSummaries(classes, version));
    } on ApiException catch (e) {
      if (mounted && version == _loadVersion) {
        setState(() {
          _classesLoaded = true;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted && version == _loadVersion) {
        setState(() {
          _classesLoaded = true;
          _error = 'Could not load classes. Pull to retry.';
        });
      }
    }
  }

  Future<void> _loadAttendance(
      AuthSession? session, String today, int version) async {
    if (session == null) {
      if (mounted && version == _loadVersion) {
        setState(() {
          _attendanceLoaded = true;
          _attendanceError = true;
        });
      }
      return;
    }
    try {
      final attendance = await ApiClient.instance
          .get('/coaches/${session.userId}/attendance') as List;
      Map<String, dynamic>? todayRecord;
      for (final e in attendance) {
        final a = e as Map<String, dynamic>;
        if ((a['date'] as String).substring(0, 10) == today) {
          todayRecord = a;
          break;
        }
      }
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _myStatus = todayRecord?['status'] as String?;
        _attendanceLoaded = true;
        _attendanceError = false;
      });
    } on ApiException catch (e) {
      if (mounted && version == _loadVersion) {
        setState(() {
          _attendanceLoaded = true;
          _attendanceError = true;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted && version == _loadVersion) {
        setState(() {
          _attendanceLoaded = true;
          _attendanceError = true;
          _error = 'Could not check attendance. Pull to retry.';
        });
      }
    }
  }

  Future<void> _loadPendingSync(int version) async {
    try {
      final count = await OfflineQueue.pendingCount();
      if (mounted && version == _loadVersion)
        setState(() => _pendingSync = count);
    } catch (_) {
      // The dashboard remains usable if the local offline queue is unavailable.
    }
  }

  Future<void> _loadClassSummaries(
      List<ClassSession> classes, int version) async {
    final pairs = await Future.wait(classes.map((c) async {
      try {
        final s = await ApiClient.instance
            .get('/activities/classes/${c.id}/summary') as Map<String, dynamic>;
        return MapEntry(c.id, s);
      } on ApiException {
        return MapEntry(c.id, <String, dynamic>{});
      } catch (_) {
        return MapEntry(c.id, <String, dynamic>{});
      }
    }));
    if (mounted && version == _loadVersion) {
      setState(() => _summaries = Map.fromEntries(pairs));
    }
  }

  Future<void> _submitMyAttendance() async {
    if (_pendingStatus == null) return;
    setState(() => _actionLoading = true);
    try {
      await ApiClient.instance
          .post('/attendance/coach-mark', body: {'status': _pendingStatus});
      setState(() {
        _myStatus = _pendingStatus;
        _pendingStatus = null;
      });
      if (mounted)
        _showSnack(
            'Marked ${_myAttendanceStatusLabels[_myStatus]} — submitted, awaiting admin');
    } on ApiException catch (e) {
      if (mounted) _showSnack(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _syncNow() async {
    final result = await SyncService.syncNow();
    _pendingSync = await OfflineQueue.pendingCount();
    if (!mounted) return;
    setState(() {});
    _showSnack(
        'Synced ${result.synced} record(s)${result.failed > 0 ? ', ${result.failed} failed' : ''}');
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message), backgroundColor: isError ? Colors.red : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset('assets/images/logo.jpeg', fit: BoxFit.cover),
          ),
        ),
        title: Text('Hi, $_coachName'),
        actions: const [NotificationBellAction(), SizedBox(width: 4)],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Card(
                  child: ListTile(
                      title: Text(_error!,
                          style: const TextStyle(color: Colors.red)),
                      trailing: IconButton(
                          icon: const Icon(Icons.refresh), onPressed: _load))),
            Text('My Attendance Today',
                style: Theme.of(context).textTheme.titleMedium),
            const Text(
              'Manual entry — no location needed. Pick a status, change it as needed, then press Submit to '
              'lock it in. Once submitted, only admin can correct it.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            if (!_attendanceLoaded || _attendanceError)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    if (!_attendanceError)
                      const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_attendanceError
                          ? 'Attendance could not be checked. Pull to retry.'
                          : "Checking today's attendance..."),
                    ),
                  ],
                ),
              )
            else if (_myStatus != null)
              Chip(
                  label: Text(
                      '${_myAttendanceStatusLabels[_myStatus] ?? _myStatus} — locked'))
            else ...[
              Wrap(
                spacing: 8,
                children: _myAttendanceStatusLabels.entries
                    .map((e) => _pendingStatus == e.key
                        ? ElevatedButton(
                            onPressed: _actionLoading ||
                                    !_attendanceLoaded ||
                                    _attendanceError
                                ? null
                                : () => setState(() => _pendingStatus = e.key),
                            child: Text(e.value),
                          )
                        : OutlinedButton(
                            onPressed: _actionLoading ||
                                    !_attendanceLoaded ||
                                    _attendanceError
                                ? null
                                : () => setState(() => _pendingStatus = e.key),
                            child: Text(e.value),
                          ))
                    .toList(),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _actionLoading ||
                        !_attendanceLoaded ||
                        _attendanceError ||
                        _pendingStatus == null
                    ? null
                    : _submitMyAttendance,
                child: Text(_actionLoading ? 'Submitting...' : 'Submit'),
              ),
            ],
            if (_pendingSync > 0)
              Card(
                color: Colors.amber.shade50,
                margin: const EdgeInsets.symmetric(vertical: 12),
                child: ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title:
                      Text('$_pendingSync attendance record(s) queued offline'),
                  trailing: TextButton(
                      onPressed: _syncNow, child: const Text('Sync now')),
                ),
              ),
            const SizedBox(height: 8),
            PinnedSearchSection(
              padding: const EdgeInsets.symmetric(vertical: 4),
              search: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Today's Classes",
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                      decoration: InputDecoration(
                          labelText: 'Search classes',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _classSearch.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () =>
                                      setState(() => _classSearch = ''),
                                  icon: const Icon(Icons.clear))),
                      onChanged: (v) => setState(() => _classSearch = v)),
                ],
              ),
              results: Column(children: [
                Wrap(spacing: 8, children: [
                  DropdownButton<int?>(
                      value: _activityFilter,
                      hint: const Text('All activities'),
                      items: [
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('All activities')),
                        ..._classes.map((c) => c.activityId).toSet().map((id) =>
                            DropdownMenuItem<int?>(
                                value: id, child: Text('Activity #$id')))
                      ],
                      onChanged: (v) => setState(() => _activityFilter = v)),
                  if (_classSearch.isNotEmpty || _activityFilter != null)
                    TextButton(
                        onPressed: () => setState(() {
                              _classSearch = '';
                              _activityFilter = null;
                            }),
                        child: const Text('Clear filters'))
                ]),
                if (!_classesLoaded)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_classes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No classes scheduled today.')),
                  )
                else if (_visibleClasses.isEmpty)
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('No results found.')))
                else
                  ..._visibleClasses.map((c) {
                    final s = _summaries[c.id];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: const Icon(Icons.fitness_center),
                          title: Text('${c.startTime} - ${c.endTime}'),
                          subtitle: s == null
                              ? const Text('Loading class details...')
                              : s.isEmpty
                                  ? const Text('-')
                                  : Text(
                                      'Students: ${s['enrolled_count']} · Marked: ${s['marked_count']} · Paid/Unpaid: ${s['fee_paid_count']}/${s['fee_unpaid_count']}',
                                      style: const TextStyle(fontSize: 12)),
                          isThreeLine: s != null && s.isNotEmpty,
                          trailing: ElevatedButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      MarkAttendanceScreen(classSession: c)),
                            ),
                            child: const Text('Mark'),
                          ),
                        ),
                      ),
                    );
                  }),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
