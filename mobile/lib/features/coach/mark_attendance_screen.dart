import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/api_client.dart';
import '../../core/api_config.dart';
import '../../core/app_theme.dart';
import '../../core/geofence.dart';
import '../../core/location_service.dart';
import '../../core/models.dart';
import '../../core/offline_queue.dart';

const _lateMarkMinutes = 10;

class _MarkedRecord {
  final int attendanceId;
  String status;
  _MarkedRecord({required this.attendanceId, required this.status});
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
  final _picker = ImagePicker();
  final _lateReasonCtrl = TextEditingController();

  bool get _isLikelyLate {
    try {
      final dateParts = widget.classSession.date.split('-');
      final timeParts = widget.classSession.endTime.split(':');
      final endDt = DateTime(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );
      return DateTime.now().isAfter(endDt.add(const Duration(minutes: _lateMarkMinutes)));
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadRoster();
  }

  @override
  void dispose() {
    _lateReasonCtrl.dispose();
    super.dispose();
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
        _marked[m['student_id'] as int] = _MarkedRecord(attendanceId: m['id'] as int, status: m['status'] as String);
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
    double? lat;
    double? lng;
    String? selfieBase64;
    try {
      final position = await LocationService.getCurrentPosition();
      lat = position.latitude;
      lng = position.longitude;
      final distance = Geofence.distanceMeters(lat, lng, FacilityConfig.lat, FacilityConfig.lng);
      if (distance > FacilityConfig.radiusMeters) {
        _showSnack(
          'You are ${distance.toStringAsFixed(0)}m from the facility (limit ${FacilityConfig.radiusMeters.toStringAsFixed(0)}m). The server will reject this.',
          isError: true,
        );
      }

      if (status == 'PRESENT') {
        final photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70, preferredCameraDevice: CameraDevice.front);
        if (photo == null) {
          setState(() => _busyStudentId = null);
          return; // coach cancelled the selfie
        }
        final bytes = await photo.readAsBytes();
        selfieBase64 = base64Encode(bytes);
      }

      final body = {
        'student_id': student.id,
        'class_id': widget.classSession.id,
        'status': status,
        'location_lat': lat,
        'location_lng': lng,
        'selfie_base64': selfieBase64,
        if (_isLikelyLate && _lateReasonCtrl.text.trim().isNotEmpty) 'late_reason': _lateReasonCtrl.text.trim(),
      };

      try {
        final result = await ApiClient.instance.post('/attendance/mark-student', body: body) as Map<String, dynamic>;
        _showSnack('${student.name}: $status recorded');
        setState(() => _marked[student.id] = _MarkedRecord(attendanceId: result['id'] as int, status: status));
      } on ApiException catch (e) {
        // The server responded definitively (validation error, deadline passed,
        // duplicate, etc.) — nothing to gain by queuing this for a retry.
        _showSnack(e.message, isError: true);
        return;
      }
    } catch (e) {
      // Network-level failure (no connectivity): queue for later sync, reusing
      // whatever location/selfie we already captured above.
      if (lat == null || lng == null) {
        _showSnack('Could not mark attendance for ${student.name}. Enable GPS and try again.', isError: true);
      } else {
        await OfflineQueue.enqueue(QueuedAttendance(
          studentId: student.id,
          classId: widget.classSession.id,
          status: status,
          lat: lat,
          lng: lng,
          selfieBase64: selfieBase64,
          createdAt: DateTime.now(),
        ));
        setState(() => _marked[student.id] = _MarkedRecord(attendanceId: -1, status: status));
        _showSnack('No connection — queued ${student.name} for sync.');
      }
    } finally {
      if (mounted) setState(() => _busyStudentId = null);
    }
  }

  Future<void> _editStatus(RosterStudent student, String newStatus) async {
    final record = _marked[student.id];
    if (record == null || record.attendanceId < 0) return;
    setState(() => _busyStudentId = student.id);
    try {
      await ApiClient.instance.put('/attendance/students/${record.attendanceId}', body: {'status': newStatus});
      _showSnack('Updated to ${newStatus.toLowerCase()}');
      setState(() => record.status = newStatus);
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busyStudentId = null);
    }
  }

  Future<void> _deleteAttendance(RosterStudent student) async {
    final record = _marked[student.id];
    if (record == null || record.attendanceId < 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete attendance record?'),
        content: const Text('Delete this attendance record?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busyStudentId = student.id);
    try {
      await ApiClient.instance.delete('/attendance/students/${record.attendanceId}');
      _showSnack('Attendance record deleted');
      setState(() => _marked.remove(student.id));
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busyStudentId = null);
    }
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
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Mark Attendance — Class #${widget.classSession.id}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_isLikelyLate)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _lateReasonCtrl,
                      decoration: const InputDecoration(
                        labelText: 'This class ended over $_lateMarkMinutes min ago — reason for late attendance',
                        hintText: 'e.g. traffic delay, facility access issue...',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
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
                                                crossAxisAlignment: WrapCrossAlignment.center,
                                                children: [
                                                  Chip(
                                                    label: Text(record.status, style: const TextStyle(fontSize: 11, color: Colors.white)),
                                                    backgroundColor: _statusColor(record.status),
                                                    visualDensity: VisualDensity.compact,
                                                  ),
                                                  if (record.attendanceId >= 0) ...[
                                                    DropdownButton<String>(
                                                      value: record.status,
                                                      items: const [
                                                        DropdownMenuItem(value: 'PRESENT', child: Text('Present')),
                                                        DropdownMenuItem(value: 'ABSENT', child: Text('Absent')),
                                                        DropdownMenuItem(value: 'LEAVE', child: Text('Leave')),
                                                      ],
                                                      onChanged: (v) => v == null ? null : _editStatus(student, v),
                                                    ),
                                                    OutlinedButton(
                                                      onPressed: () => _deleteAttendance(student),
                                                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                                                      child: const Text('Delete'),
                                                    ),
                                                  ],
                                                ],
                                              )
                                            : Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  _statusButton(student, 'PRESENT', Icons.check, Colors.green),
                                                  _statusButton(student, 'ABSENT', Icons.close, Colors.red),
                                                  _statusButton(student, 'LEAVE', Icons.beach_access, Colors.orange),
                                                ],
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

  Widget _statusButton(RosterStudent student, String status, IconData icon, Color color) {
    return IconButton(
      icon: Icon(icon, color: color),
      tooltip: status,
      onPressed: () => _markStudent(student, status),
    );
  }
}
