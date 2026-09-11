import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../core/api_client.dart';
import '../../core/api_config.dart';
import '../../core/auth_storage.dart';
import '../../core/models.dart';
import 'mark_attendance_screen.dart';
import '../shared/notification_bell_action.dart';

class ClassesTab extends StatefulWidget {
  const ClassesTab({super.key});

  @override
  State<ClassesTab> createState() => _ClassesTabState();
}

class _ClassesTabState extends State<ClassesTab> {
  DateTime _selectedDate = DateTime.now();
  List<ClassSession> _classes = [];
  final Map<int, List<ClassPhoto>> _photosByClass = {};
  String? _authHeader;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final data = await ApiClient.instance.get('/activities/classes/my', query: {'class_date': dateStr}) as List;
      _classes = data.map((e) => ClassSession.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    final session = await AuthStorage.load();
    _authHeader = 'Bearer ${session?.accessToken ?? ''}';
    for (final c in _classes) {
      if (_hasEnded(c)) _loadPhotos(c.id);
    }
  }

  Future<void> _loadPhotos(int classId) async {
    try {
      final data = await ApiClient.instance.get('/compliance/class/$classId/photos') as List;
      final photos = data.map((e) => ClassPhoto.fromJson(e as Map<String, dynamic>)).toList();
      if (mounted) setState(() => _photosByClass[classId] = photos);
    } on ApiException {
      // non-fatal — the "Batch Photo" button still works without a preview
    }
  }

  bool _hasEnded(ClassSession c) {
    final dateParts = c.date.split('-');
    final timeParts = c.endTime.split(':');
    final endDt = DateTime(
      int.parse(dateParts[0]),
      int.parse(dateParts[1]),
      int.parse(dateParts[2]),
      int.parse(timeParts[0]),
      int.parse(timeParts[1]),
    );
    return DateTime.now().isAfter(endDt);
  }

  Future<void> _markNotConducted(ClassSession c) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Class not conducted'),
        content: TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reason'), maxLines: 2),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit')),
        ],
      ),
    );
    if (confirmed != true) {
      reasonCtrl.dispose();
      return;
    }
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (reason.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A reason is required')));
      return;
    }
    try {
      await ApiClient.instance.post('/compliance/class-not-conducted', body: {'class_id': c.id, 'reason': reason});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recorded — admin has been notified')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _uploadBatchPhoto(ClassSession c) async {
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
      if (photo == null) return;
      final bytes = await photo.readAsBytes();
      await ApiClient.instance.post('/compliance/class/${c.id}/photo', body: {'class_id': c.id, 'photo_base64': base64Encode(bytes)});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo uploaded')));
      // Refresh so the just-uploaded photo shows up next to the class immediately.
      await _loadPhotos(c.id);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open camera — check camera permission')));
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Classes'),
        actions: [
          IconButton(icon: const Icon(Icons.calendar_month), onPressed: _pickDate),
          const NotificationBellAction(),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(DateFormat('EEEE, MMM d, yyyy').format(_selectedDate), style: Theme.of(context).textTheme.titleMedium),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _classes.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 32),
                        child: Center(
                          child: Text(
                            'No classes on this date. If your admin has assigned you a schedule, classes will '
                            "show up here automatically — if you don't expect to see anything soon, check with "
                            'your admin that a schedule has been set up for you.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _classes.length,
                        itemBuilder: (context, i) {
                          final c = _classes[i];
                          final ended = _hasEnded(c);
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.fitness_center),
                                    title: Text('${c.startTime} - ${c.endTime}'),
                                    subtitle: Text('Class #${c.id} · Activity #${c.activityId}'),
                                    trailing: ElevatedButton(
                                      onPressed: () => Navigator.of(context).push(
                                        MaterialPageRoute(builder: (_) => MarkAttendanceScreen(classSession: c)),
                                      ),
                                      child: const Text('Mark'),
                                    ),
                                  ),
                                  if (ended)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                                      child: Row(
                                        children: [
                                          TextButton.icon(
                                            onPressed: () => _uploadBatchPhoto(c),
                                            icon: const Icon(Icons.camera_alt_outlined, size: 18),
                                            label: const Text('Batch Photo'),
                                          ),
                                          TextButton.icon(
                                            onPressed: () => _markNotConducted(c),
                                            icon: const Icon(Icons.event_busy_outlined, size: 18),
                                            label: const Text('Not Conducted'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (ended && (_photosByClass[c.id]?.isNotEmpty ?? false))
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                                      child: SizedBox(
                                        height: 64,
                                        child: ListView.separated(
                                          scrollDirection: Axis.horizontal,
                                          itemCount: _photosByClass[c.id]!.length,
                                          separatorBuilder: (_, __) => const SizedBox(width: 6),
                                          itemBuilder: (context, i) => ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.network(
                                              '${ApiConfig.baseUrl}/compliance/class-photo/${_photosByClass[c.id]![i].id}',
                                              headers: {'Authorization': _authHeader ?? ''},
                                              width: 64,
                                              height: 64,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Container(width: 64, height: 64, color: Colors.black12, child: const Icon(Icons.broken_image_outlined)),
                                            ),
                                          ),
                                        ),
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
