import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/api_client.dart';
import '../../core/api_config.dart';
import '../../core/geofence.dart';
import '../../core/location_service.dart';
import '../../core/models.dart';
import '../../core/offline_queue.dart';

class MarkAttendanceScreen extends StatefulWidget {
  final ClassSession classSession;
  const MarkAttendanceScreen({super.key, required this.classSession});

  @override
  State<MarkAttendanceScreen> createState() => _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends State<MarkAttendanceScreen> {
  List<RosterStudent> _roster = [];
  final Set<int> _marked = {};
  bool _loading = true;
  int? _busyStudentId;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadRoster();
  }

  Future<void> _loadRoster() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/activities/${widget.classSession.activityId}/roster') as List;
      _roster = data.map((e) => RosterStudent.fromJson(e as Map<String, dynamic>)).toList();
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
      final within = Geofence.isWithin(
        lat,
        lng,
        FacilityConfig.lat,
        FacilityConfig.lng,
        radiusMeters: FacilityConfig.radiusMeters,
      );
      if (!within) {
        _showSnack('You are outside the facility geofence. The server will reject this.', isError: true);
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
      };

      try {
        await ApiClient.instance.post('/attendance/mark-student', body: body);
        _showSnack('${student.name}: $status recorded');
      } on ApiException catch (e) {
        // The server responded definitively (validation error, deadline passed,
        // duplicate, etc.) — nothing to gain by queuing this for a retry.
        _showSnack(e.message, isError: true);
        return;
      }
      setState(() => _marked.add(student.id));
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
        setState(() => _marked.add(student.id));
        _showSnack('No connection — queued ${student.name} for sync.');
      }
    } finally {
      if (mounted) setState(() => _busyStudentId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Mark Attendance — Class #${widget.classSession.id}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _roster.isEmpty
              ? const Center(child: Text('No students enrolled in this activity.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _roster.length,
                  itemBuilder: (context, i) {
                    final student = _roster[i];
                    final busy = _busyStudentId == student.id;
                    final done = _marked.contains(student.id);
                    return Card(
                      child: ListTile(
                        title: Text(student.name),
                        subtitle: Text(student.email),
                        trailing: busy
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : done
                                ? const Icon(Icons.check_circle, color: Colors.green)
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _statusButton(student, 'PRESENT', Icons.check, Colors.green),
                                      _statusButton(student, 'ABSENT', Icons.close, Colors.red),
                                      _statusButton(student, 'LEAVE', Icons.beach_access, Colors.orange),
                                    ],
                                  ),
                      ),
                    );
                  },
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
