import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/models.dart';
import '../../core/offline_queue.dart';

const _statusLabels = {'PRESENT': 'Present', 'ABSENT': 'Absent', 'LEAVE': 'Leave', 'NOT_CONFIRM': 'Not Confirm'};

class _MarkedRecord {
  final int attendanceId;
  final String status;
  final String approvalStatus;
  final bool hasSelfie;
  _MarkedRecord({
    required this.attendanceId,
    required this.status,
    this.approvalStatus = 'PENDING',
    this.hasSelfie = false,
  });
}

class MarkAttendanceScreen extends StatefulWidget {
  final ClassSession classSession;
  const MarkAttendanceScreen({super.key, required this.classSession});

  @override
  State<MarkAttendanceScreen> createState() => _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends State<MarkAttendanceScreen> {
  List<RosterStudent> _roster = [];
  final Map<int, _MarkedRecord> _marked = {};
  bool _loading = true;
  int? _busyStudentId;

  @override
  void initState() {
    super.initState();
    _loadRoster();
  }

  Future<void> _loadRoster() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/activities/${widget.classSession.activityId}/roster'),
        ApiClient.instance.get('/attendance/students', query: {'class_id': widget.classSession.id}),
      ]);
      _roster = (results[0] as List).map((e) => RosterStudent.fromJson(e as Map<String, dynamic>)).toList();
      _marked.clear();
      for (final e in (results[1] as List)) {
        final m = e as Map<String, dynamic>;
        _marked[m['student_id'] as int] = _MarkedRecord(
          attendanceId: m['id'] as int,
          status: m['status'] as String,
          approvalStatus: m['approval_status'] as String? ?? 'PENDING',
          hasSelfie: m['has_selfie'] as bool? ?? false,
        );
      }
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Colors.red : null),
    );
  }

  Future<void> _markStudent(RosterStudent student, String status) async {
    setState(() => _busyStudentId = student.id);
    try {
      final result = await ApiClient.instance.post('/attendance/mark-student', body: {
        'student_id': student.id,
        'class_id': widget.classSession.id,
        'status': status,
      }) as Map<String, dynamic>;
      _showSnack('${student.name}: ${_statusLabels[status]} submitted, awaiting admin');
      setState(() => _marked[student.id] = _MarkedRecord(
            attendanceId: result['id'] as int,
            status: status,
            approvalStatus: result['approval_status'] as String? ?? 'PENDING',
            hasSelfie: result['has_selfie'] as bool? ?? false,
          ));
    } on ApiException catch (e) {
      // The server responded definitively (validation error, deadline passed,
      // duplicate, etc.) — nothing to gain by queuing this for a retry.
      _showSnack(e.message, isError: true);
    } catch (e) {
      // Network-level failure (no connectivity): queue for later sync.
      await OfflineQueue.enqueue(QueuedAttendance(
        studentId: student.id,
        classId: widget.classSession.id,
        status: status,
        lat: 0,
        lng: 0,
        createdAt: DateTime.now(),
      ));
      setState(() => _marked[student.id] = _MarkedRecord(attendanceId: -1, status: status));
      _showSnack('No connection — queued ${student.name} for sync.');
    } finally {
      if (mounted) setState(() => _busyStudentId = null);
    }
  }

  Future<void> _viewPhoto(_MarkedRecord record) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Attendance Photo'),
        content: SizedBox(
          width: 280,
          height: 280,
          child: FutureBuilder<Uint8List>(
            future: ApiClient.instance.getBytes('/attendance/selfie/${record.attendanceId}').then((b) => Uint8List.fromList(b)),
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

  Color _feeColor(String? status) {
    switch (status) {
      case 'PAID':
        return AppColors.success;
      case 'OVERDUE':
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'PRESENT':
        return AppColors.success;
      case 'ABSENT':
        return AppColors.danger;
      case 'NOT_CONFIRM':
        return Colors.indigo;
      default:
        return AppColors.warning;
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

  String _approvalLabel(String status) => status == 'PENDING' ? 'Awaiting Admin' : status;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Mark Attendance — Class #${widget.classSession.id}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Text(
                    'Manual entry — no location or photo needed. Once submitted, a mark cannot be changed; only admin can correct it.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ),
                Expanded(
                  child: _roster.isEmpty
                      ? const Center(child: Text('No students enrolled in this activity.'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _roster.length,
                          itemBuilder: (context, i) {
                            final student = _roster[i];
                            final busy = _busyStudentId == student.id;
                            final record = _marked[student.id];
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ListTile(
                                      title: Text(student.name),
                                      subtitle: Row(
                                        children: [
                                          Chip(
                                            label: Text(student.feeStatus ?? 'UNPAID', style: const TextStyle(fontSize: 10, color: Colors.white)),
                                            backgroundColor: _feeColor(student.feeStatus),
                                            visualDensity: VisualDensity.compact,
                                          ),
                                        ],
                                      ),
                                      trailing: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                                    ),
                                    if (!busy)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                        child: record != null
                                            ? Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                crossAxisAlignment: WrapCrossAlignment.center,
                                                children: [
                                                  Chip(
                                                    label: Text(_statusLabels[record.status] ?? record.status, style: const TextStyle(fontSize: 11, color: Colors.white)),
                                                    backgroundColor: _statusColor(record.status),
                                                    visualDensity: VisualDensity.compact,
                                                  ),
                                                  if (record.attendanceId >= 0)
                                                    Chip(
                                                      label: Text(_approvalLabel(record.approvalStatus), style: const TextStyle(fontSize: 11, color: Colors.white)),
                                                      backgroundColor: _approvalColor(record.approvalStatus),
                                                      visualDensity: VisualDensity.compact,
                                                    ),
                                                  if (record.hasSelfie)
                                                    OutlinedButton(
                                                      onPressed: () => _viewPhoto(record),
                                                      child: const Text('View Photo'),
                                                    ),
                                                  const Text('Locked', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                                ],
                                              )
                                            : Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                children: _statusLabels.entries
                                                    .map((e) => e.key == 'PRESENT'
                                                        ? ElevatedButton(
                                                            onPressed: () => _markStudent(student, e.key),
                                                            child: Text(e.value),
                                                          )
                                                        : OutlinedButton(
                                                            onPressed: () => _markStudent(student, e.key),
                                                            child: Text(e.value),
                                                          ))
                                                    .toList(),
                                              ),
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
