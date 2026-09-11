import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/auth_storage.dart';
import '../../core/models.dart';
import '../shared/notification_bell_action.dart';

const _feeReminderMessage = "Hi this is VIMJ Studio and it is an reminder for fee payment is pending for the sos "
    "month and kindly pay as before the deadline of 5th of every month as cash or upi number - 6361174605  to "
    "Mahesh Sir.  Thank you";

class CoachStudentsTab extends StatefulWidget {
  const CoachStudentsTab({super.key});

  @override
  State<CoachStudentsTab> createState() => _CoachStudentsTabState();
}

class _CoachStudentsTabState extends State<CoachStudentsTab> {
  List<CoachActivityLink> _activities = [];
  final Map<int, List<RosterStudent>> _rosterByActivity = {};
  final Map<int, Uint8List?> _photos = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final session = await AuthStorage.load();
      if (session == null) return;
      final data = await ApiClient.instance.get('/coaches/${session.userId}/activities') as List;
      _activities = data.map((e) => CoachActivityLink.fromJson(e as Map<String, dynamic>)).toList();
      final rosters = await Future.wait(_activities.map((a) => ApiClient.instance.get('/activities/${a.activityId}/roster')));
      _rosterByActivity.clear();
      for (var i = 0; i < _activities.length; i++) {
        final list = (rosters[i] as List).map((e) => RosterStudent.fromJson(e as Map<String, dynamic>)).toList();
        _rosterByActivity[_activities[i].activityId] = list;
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    final studentIds = _rosterByActivity.values.expand((list) => list.map((s) => s.id)).toSet();
    await Future.wait(studentIds.map((id) => _loadPhoto(id)));
  }

  Future<void> _loadPhoto(int studentId) async {
    try {
      final bytes = await ApiClient.instance.getBytes('/students/$studentId/photo');
      if (mounted) setState(() => _photos[studentId] = Uint8List.fromList(bytes));
    } on ApiException {
      if (mounted) setState(() => _photos[studentId] = null);
    }
  }

  void _handleAddStudentTap() {
    if (_activities.isEmpty) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('No activity assigned'),
          content: const Text(
            "You're not assigned to any activity yet, so there's nowhere to add a student under. "
            'Ask your admin to assign you to an activity first.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
      return;
    }
    _openForm();
  }

  Future<void> _openForm() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddStudentForm(activities: _activities),
    );
    if (saved == true) _load();
  }

  Future<void> _copyFeeReminder() async {
    await Clipboard.setData(const ClipboardData(text: _feeReminderMessage));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message copied — paste it into WhatsApp/SMS')));
  }

  Future<void> _capturePhoto(RosterStudent s) async {
    XFile? photo;
    try {
      final picker = ImagePicker();
      photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 70, preferredCameraDevice: CameraDevice.front);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open camera — check camera permission')));
      return;
    }
    if (photo == null) return;
    try {
      final bytes = await photo.readAsBytes();
      await ApiClient.instance.post('/students/${s.id}/photo', body: {'photo_base64': base64Encode(bytes)});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo saved')));
      // Refresh just this student's thumbnail so it shows next to their name
      // immediately, without re-fetching the whole roster.
      await _loadPhoto(s.id);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openEdit(RosterStudent s) async {
    final nameCtrl = TextEditingController(text: s.name);
    final phoneCtrl = TextEditingController();
    final phoneSecondaryCtrl = TextEditingController();
    String? error;
    bool saving = false;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Edit Student — ${s.name}', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 12),
                TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Primary Phone'), keyboardType: TextInputType.phone),
                const SizedBox(height: 12),
                TextField(controller: phoneSecondaryCtrl, decoration: const InputDecoration(labelText: 'Emergency Contact'), keyboardType: TextInputType.phone),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: const TextStyle(color: AppColors.danger)),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setLocalState(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            await ApiClient.instance.put('/students/${s.id}', body: {
                              'name': nameCtrl.text.trim(),
                              'phone': phoneCtrl.text.trim(),
                              'phone_secondary': phoneSecondaryCtrl.text.trim(),
                            });
                            if (ctx.mounted) Navigator.of(ctx).pop(true);
                          } on ApiException catch (e) {
                            setLocalState(() {
                              saving = false;
                              error = e.message;
                            });
                          }
                        },
                  child: saving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    nameCtrl.dispose();
    phoneCtrl.dispose();
    phoneSecondaryCtrl.dispose();
    if (saved == true) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Student updated')));
      _load();
    }
  }

  Future<void> _removeStudent(RosterStudent s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove student?'),
        content: Text('Remove ${s.name}? This deletes their attendance and fee history too.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.delete('/students/${s.id}');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Student removed')));
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Students'), actions: const [NotificationBellAction(), SizedBox(width: 4)]),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'coach-students-fab',
        onPressed: _handleAddStudentTap,
        icon: const Icon(Icons.add),
        label: const Text('Add Student'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _activities.isEmpty
                  ? ListView(children: const [
                      Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            "You're not assigned to any activity yet — your admin needs to assign you one "
                            'before students show up here.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    ])
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                      children: _activities.map((a) {
                        final roster = _rosterByActivity[a.activityId] ?? [];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a.activityName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 6),
                                if (roster.isEmpty)
                                  const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No students enrolled yet.', style: TextStyle(color: AppColors.textMuted)))
                                else
                                  ...roster.map((s) => ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: CircleAvatar(
                                          radius: 20,
                                          backgroundImage: _photos[s.id] != null ? MemoryImage(_photos[s.id]!) : null,
                                          child: _photos[s.id] == null ? const Icon(Icons.person_outline) : null,
                                        ),
                                        title: Text(s.name),
                                        subtitle: Text(s.email.endsWith('@no-login.internal') ? '-' : s.email),
                                        trailing: PopupMenuButton<String>(
                                          onSelected: (v) {
                                            if (v == 'copy') _copyFeeReminder();
                                            if (v == 'photo') _capturePhoto(s);
                                            if (v == 'edit') _openEdit(s);
                                            if (v == 'delete') _removeStudent(s);
                                          },
                                          itemBuilder: (_) => [
                                            const PopupMenuItem(value: 'copy', child: Text('Copy Fee Reminder')),
                                            const PopupMenuItem(value: 'photo', child: Text('Capture Photo')),
                                            const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                            const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                          ],
                                        ),
                                      )),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
            ),
    );
  }
}

class _AddStudentForm extends StatefulWidget {
  final List<CoachActivityLink> activities;
  const _AddStudentForm({required this.activities});

  @override
  State<_AddStudentForm> createState() => _AddStudentFormState();
}

class _AddStudentFormState extends State<_AddStudentForm> {
  late int? _activityId = widget.activities.isNotEmpty ? widget.activities.first.activityId : null;
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _phoneSecondaryCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().isEmpty || _phoneSecondaryCtrl.text.trim().isEmpty || _activityId == null) {
      setState(() => _error = 'Name, both phone numbers, and activity are required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.post('/students', body: {
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'phone_secondary': _phoneSecondaryCtrl.text.trim(),
        'activity_id': _activityId,
        if (_emailCtrl.text.trim().isNotEmpty) 'email': _emailCtrl.text.trim(),
        if (_passwordCtrl.text.isNotEmpty) 'password': _passwordCtrl.text,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _phoneSecondaryCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add Student', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _activityId,
              decoration: const InputDecoration(labelText: 'Activity'),
              items: widget.activities.map((a) => DropdownMenuItem(value: a.activityId, child: Text(a.activityName))).toList(),
              onChanged: (v) => setState(() => _activityId = v),
            ),
            const SizedBox(height: 12),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(labelText: "Email (optional — students don't log in)"),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Primary Phone'), keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            TextField(controller: _phoneSecondaryCtrl, decoration: const InputDecoration(labelText: 'Emergency Contact'), keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Password (optional — students don't log in)"),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}
