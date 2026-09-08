import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api_client.dart';
import '../../core/auth_storage.dart';
import '../../core/location_service.dart';
import '../../core/geofence.dart';
import '../../core/api_config.dart';
import '../../core/models.dart';
import '../../core/offline_queue.dart';
import '../../core/sync_service.dart';
import 'mark_attendance_screen.dart';

class CoachDashboardTab extends StatefulWidget {
  const CoachDashboardTab({super.key});

  @override
  State<CoachDashboardTab> createState() => _CoachDashboardTabState();
}

class _CoachDashboardTabState extends State<CoachDashboardTab> {
  List<ClassSession> _classes = [];
  Map<int, Map<String, dynamic>> _summaries = {};
  bool _loading = true;
  String? _error;
  String _coachName = '';
  bool _entryDone = false;
  bool _exitDone = false;
  bool _actionLoading = false;
  int _pendingSync = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await AuthStorage.load();
      _coachName = session?.name ?? '';
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final results = await Future.wait([
        ApiClient.instance.get('/activities/classes/my', query: {'class_date': today}),
        session != null ? ApiClient.instance.get('/coaches/${session.userId}/attendance') : Future.value([]),
      ]);
      _classes = (results[0] as List).map((e) => ClassSession.fromJson(e as Map<String, dynamic>)).toList();
      final attendance = results[1] as List;
      Map<String, dynamic>? todayRecord;
      for (final e in attendance) {
        final a = e as Map<String, dynamic>;
        if ((a['date'] as String).substring(0, 10) == today) {
          todayRecord = a;
          break;
        }
      }
      _entryDone = todayRecord?['entry_time'] != null;
      _exitDone = todayRecord?['exit_time'] != null;
      _pendingSync = await OfflineQueue.pendingCount();
      final summaryPairs = await Future.wait(_classes.map((c) async {
        try {
          final s = await ApiClient.instance.get('/activities/classes/${c.id}/summary') as Map<String, dynamic>;
          return MapEntry(c.id, s);
        } on ApiException {
          return MapEntry(c.id, <String, dynamic>{});
        }
      }));
      _summaries = Map.fromEntries(summaryPairs);
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Failed to load today\'s classes';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleEntry() async {
    await _handleGeofencedAction('/attendance/coach-entry', isEntry: true);
  }

  Future<void> _handleExit() async {
    await _handleGeofencedAction('/attendance/coach-exit', isEntry: false);
  }

  Future<void> _handleGeofencedAction(String path, {required bool isEntry}) async {
    setState(() => _actionLoading = true);
    try {
      final position = await LocationService.getCurrentPosition();
      final within = Geofence.isWithin(
        position.latitude,
        position.longitude,
        FacilityConfig.lat,
        FacilityConfig.lng,
        radiusMeters: FacilityConfig.radiusMeters,
      );
      if (!within && mounted) {
        _showSnack('You appear to be outside the facility. The server will reject this if you are not within range.');
      }
      await ApiClient.instance.post(path, body: {
        'location_lat': position.latitude,
        'location_lng': position.longitude,
      });
      setState(() {
        if (isEntry) {
          _entryDone = true;
        } else {
          _exitDone = true;
        }
      });
      if (mounted) _showSnack(isEntry ? 'Checked in successfully' : 'Checked out successfully');
    } on ApiException catch (e) {
      if (mounted) _showSnack(e.message, isError: true);
    } catch (e) {
      if (mounted) _showSnack('Could not get your location. Enable GPS and try again.', isError: true);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _syncNow() async {
    final result = await SyncService.syncNow();
    _pendingSync = await OfflineQueue.pendingCount();
    if (!mounted) return;
    setState(() {});
    _showSnack('Synced ${result.synced} record(s)${result.failed > 0 ? ', ${result.failed} failed' : ''}');
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Colors.red : null),
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
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _actionLoading || _entryDone ? null : _handleEntry,
                          icon: const Icon(Icons.login),
                          label: Text(_entryDone ? 'Checked In' : 'Check In'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _actionLoading || !_entryDone || _exitDone ? null : _handleExit,
                          icon: const Icon(Icons.logout),
                          label: Text(_exitDone ? 'Checked Out' : 'Check Out'),
                        ),
                      ),
                    ],
                  ),
                  if (_pendingSync > 0)
                    Card(
                      color: Colors.amber.shade50,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      child: ListTile(
                        leading: const Icon(Icons.cloud_upload_outlined),
                        title: Text('$_pendingSync attendance record(s) queued offline'),
                        trailing: TextButton(onPressed: _syncNow, child: const Text('Sync now')),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text("Today's Classes", style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_classes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('No classes scheduled today.')),
                    )
                  else
                    ..._classes.map((c) {
                      final s = _summaries[c.id];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: const Icon(Icons.fitness_center),
                            title: Text('${c.startTime} - ${c.endTime}'),
                            subtitle: s == null || s.isEmpty
                                ? const Text('-')
                                : Text('Students: ${s['enrolled_count']} · Marked: ${s['marked_count']} · Paid/Unpaid: ${s['fee_paid_count']}/${s['fee_unpaid_count']}', style: const TextStyle(fontSize: 12)),
                            isThreeLine: s != null && s.isNotEmpty,
                            trailing: ElevatedButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => MarkAttendanceScreen(classSession: c)),
                              ),
                              child: const Text('Mark'),
                            ),
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
