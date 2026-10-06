import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../core/api_client.dart';
import '../../core/models.dart';
import '../shared/session_photo_gallery.dart';
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
  bool _loading = true;
  final Map<int, bool> _groupPhotoOverride =
      {}; // classId -> has photo, for instant UI feedback after upload
  int? _photoBusyClassId;
  String _search = '';
  String? _photoFilter;
  List<ClassSession> get _visibleClasses => _classes
      .where((c) =>
          (_search.isEmpty ||
              'class ${c.id} activity ${c.activityId} ${c.startTime} ${c.endTime}'
                  .toLowerCase()
                  .contains(_search.trim().toLowerCase())) &&
          (_photoFilter == null ||
              (_photoFilter == 'PHOTO'
                  ? _hasGroupPhoto(c)
                  : !_hasGroupPhoto(c))))
      .toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final data = await ApiClient.instance.get('/activities/classes/my',
          query: {'class_date': dateStr}) as List;
      _classes = data
          .map((e) => ClassSession.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
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

  bool _hasGroupPhoto(ClassSession c) =>
      _groupPhotoOverride[c.id] ?? c.hasGroupPhoto;

  Future<void> _captureGroupPhoto(ClassSession c) async {
    XFile? photo;
    try {
      final picker = ImagePicker();
      photo = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 70,
          preferredCameraDevice: CameraDevice.rear);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not open camera — check camera permission')));
      return;
    }
    if (photo == null) return;

    setState(() => _photoBusyClassId = c.id);
    try {
      final bytes = await photo.readAsBytes();
      await ApiClient.instance.post('/activities/classes/${c.id}/group-photo',
          body: {'photo_base64': base64Encode(bytes)});
      if (mounted) {
        setState(() => _groupPhotoOverride[c.id] = true);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Group photo saved')));
      }
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _photoBusyClassId = null);
    }
  }

  void _viewGroupPhoto(ClassSession c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Group Photo'),
        content: SizedBox(
          width: 320,
          height: 320,
          child: FutureBuilder<Uint8List>(
            future: ApiClient.instance
                .getBytes('/activities/classes/${c.id}/group-photo')
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

  Future<void> _deleteGroupPhoto(ClassSession c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete group photo?'),
        content: const Text('The class and attendance will remain.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _photoBusyClassId = c.id);
    try {
      await ApiClient.instance
          .delete('/activities/classes/${c.id}/group-photo');
      if (mounted) {
        setState(() => _groupPhotoOverride[c.id] = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Group photo deleted')));
      }
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _photoBusyClassId = null);
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

  void _openSessionPhotos() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SessionPhotoGallery()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Classes'),
        actions: [
          IconButton(
              icon: const Icon(Icons.calendar_month), onPressed: _pickDate),
          const NotificationBellAction(),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(DateFormat('EEEE, MMM d, yyyy').format(_selectedDate),
                style: Theme.of(context).textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openSessionPhotos,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('My Session Photos'),
              ),
            ),
          ),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                  decoration: InputDecoration(
                      labelText: 'Search classes',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () => setState(() => _search = ''),
                              icon: const Icon(Icons.clear))),
                  onChanged: (v) => setState(() => _search = v))),
          Wrap(spacing: 8, children: [
            DropdownButton<String?>(
                value: _photoFilter,
                hint: const Text('All classes'),
                items: const [
                  DropdownMenuItem<String?>(
                      value: null, child: Text('All classes')),
                  DropdownMenuItem<String?>(
                      value: 'PHOTO', child: Text('Photo uploaded')),
                  DropdownMenuItem<String?>(
                      value: 'NO_PHOTO', child: Text('No photo'))
                ],
                onChanged: (v) => setState(() => _photoFilter = v)),
            if (_search.isNotEmpty || _photoFilter != null)
              TextButton(
                  onPressed: () => setState(() {
                        _search = '';
                        _photoFilter = null;
                      }),
                  child: const Text('Clear filters'))
          ]),
          Expanded(
            child: _loading && _classes.isEmpty
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
                    : _visibleClasses.isEmpty
                        ? const Center(child: Text('No results found.'))
                        : ListView.builder(
                            itemCount: _visibleClasses.length,
                            itemBuilder: (context, i) {
                              final c = _visibleClasses[i];
                              final ended = _hasEnded(c);
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ListTile(
                                        leading:
                                            const Icon(Icons.fitness_center),
                                        title: Text(
                                            '${c.startTime} - ${c.endTime}'),
                                        subtitle: Text(
                                            'Class #${c.id} · Activity #${c.activityId}'),
                                        trailing: ElevatedButton(
                                          onPressed: () =>
                                              Navigator.of(context).push(
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    MarkAttendanceScreen(
                                                        classSession: c)),
                                          ),
                                          child: const Text('Mark'),
                                        ),
                                      ),
                                      if (ended)
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              16, 0, 16, 8),
                                          child: Wrap(
                                            spacing: 8,
                                            runSpacing: 4,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              const Text('Class ended',
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey)),
                                              if (_photoBusyClassId == c.id)
                                                const SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2))
                                              else if (_hasGroupPhoto(c)) ...[
                                                OutlinedButton.icon(
                                                  onPressed: () =>
                                                      _viewGroupPhoto(c),
                                                  icon: const Icon(Icons.photo,
                                                      size: 16),
                                                  label: const Text(
                                                      'View Group Photo'),
                                                ),
                                                IconButton(
                                                  tooltip: 'Delete group photo',
                                                  onPressed: () =>
                                                      _deleteGroupPhoto(c),
                                                  icon: const Icon(
                                                      Icons.delete_outline,
                                                      color: Colors.red),
                                                ),
                                              ] else
                                                OutlinedButton.icon(
                                                  onPressed: () =>
                                                      _captureGroupPhoto(c),
                                                  icon: const Icon(
                                                      Icons.camera_alt,
                                                      size: 16),
                                                  label:
                                                      const Text('Group Photo'),
                                                ),
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
}
