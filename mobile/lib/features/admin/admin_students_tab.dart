import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/models.dart';

const _feeReminderMessage = "Hi, this is VIMJ Academy.\n\n"
    "This is a reminder that your fees are due by the 5th of this month.\n"
    "Kindly pay as soon as possible via Cash or UPI Payment to 6361174605.\n\n"
    "Thank you!";

class AdminStudentsTab extends StatefulWidget {
  const AdminStudentsTab({super.key});

  @override
  State<AdminStudentsTab> createState() => _AdminStudentsTabState();
}

class _AdminStudentsTabState extends State<AdminStudentsTab> {
  List<Student> _students = [];
  bool _loading = true;
  String _search = '';
  int? _activityId;
  List<dynamic> _activities = [];
  Map<int, String> _feeStatusByStudent = {};

  List<Student> get _visibleStudents {
    final query = _search.trim().toLowerCase();
    String? activityName;
    if (_activityId != null) {
      for (final activity in _activities) {
        if (activity['id'] == _activityId) {
          activityName = activity['name'].toString();
          break;
        }
      }
    }
    return _students
        .where((s) =>
            (query.isEmpty ||
                '${s.name} ${s.email} ${s.phone ?? ''} ${s.phoneSecondary ?? ''} ${s.activities.join(' ')}'
                    .toLowerCase()
                    .contains(query)) &&
            (activityName == null || s.activities.contains(activityName)))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadFeeStatus();
    ApiClient.instance.get("/activities").then((data) {
      if (mounted) setState(() => _activities = data as List);
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/students') as List;
      _students =
          data.map((e) => Student.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadFeeStatus() async {
    try {
      final now = DateTime.now();
      final data = await ApiClient.instance
          .get('/fees', query: {'month': now.month, 'year': now.year}) as List;
      if (!mounted) return;
      setState(() {
        _feeStatusByStudent = {
          for (final f in data) (f['student_id'] as int): f['status'] as String
        };
      });
    } on ApiException catch (_) {
      // Non-critical — the fee tag just won't show if this fails.
    }
  }

  Future<void> _openForm({Student? student}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _StudentForm(student: student),
    );
    if (saved == true) _load();
  }

  Future<void> _toggleActive(Student s) async {
    try {
      await ApiClient.instance
          .put('/students/${s.id}', body: {'is_active': !s.isActive});
      _load();
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _remove(Student s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove student?'),
        content: Text('Remove ${s.name}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.delete('/students/${s.id}');
      _load();
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _copyFeeReminder(Student s) async {
    await Clipboard.setData(const ClipboardData(text: _feeReminderMessage));
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fee reminder copied for ${s.name}')));
  }

  Future<void> _openProfile(Student s) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _StudentProfileSheet(student: s),
    );
  }

  Widget _feeChip(Student s) {
    final status = _feeStatusByStudent[s.id];
    Color color;
    String label;
    if (status == null) {
      color = AppColors.textMuted;
      label = 'No Record';
    } else {
      label = status;
      color = status == 'PAID'
          ? AppColors.success
          : (status == 'OVERDUE' ? AppColors.danger : AppColors.warning);
    }
    return Chip(
      label: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.bold)),
      backgroundColor: color.withOpacity(0.12),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleStudents = _visibleStudents;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin-students-fab',
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add Student'),
      ),
      body: Column(
        children: [
          DropdownButton<int>(
              value: _activityId,
              hint: const Text("All activities"),
              items: [
                const DropdownMenuItem<int>(
                    value: null, child: Text("All activities")),
                ..._activities.map((a) => DropdownMenuItem<int>(
                    value: a["id"] as int, child: Text(a["name"].toString())))
              ],
              onChanged: (v) => setState(() => _activityId = v)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                  hintText: 'Search by name or email...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: (_search.isEmpty && _activityId == null)
                      ? null
                      : IconButton(
                          onPressed: () => setState(() {
                                _search = '';
                                _activityId = null;
                              }),
                          icon: const Icon(Icons.clear),
                          tooltip: 'Clear filters')),
              onChanged: (v) {
                setState(() => _search = v);
              },
            ),
          ),
          Expanded(
            child: _loading && _students.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () => Future.wait([_load(), _loadFeeStatus()]),
                    child: visibleStudents.isEmpty
                        ? ListView(children: [
                            Padding(
                                padding: const EdgeInsets.all(32),
                                child: Center(
                                    child: Text(_students.isEmpty &&
                                            _search.isEmpty &&
                                            _activityId == null
                                        ? 'No students found.'
                                        : 'No results found.')))
                          ])
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                            itemCount: visibleStudents.length,
                            itemBuilder: (context, i) {
                              final s = visibleStudents[i];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: ListTile(
                                  title: Row(
                                    children: [
                                      Flexible(
                                          child: Text(s.name,
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold))),
                                      const SizedBox(width: 8),
                                      _feeChip(s),
                                    ],
                                  ),
                                  subtitle: Text(
                                      '${s.email.endsWith("@no-login.internal") ? "-" : s.email}\n${s.phone ?? "-"}\nActivity: ${s.activities.join(", ")}'),
                                  isThreeLine: true,
                                  leading: CircleAvatar(
                                    backgroundColor: s.isActive
                                        ? AppColors.success.withOpacity(0.15)
                                        : AppColors.danger.withOpacity(0.15),
                                    child: Icon(Icons.person,
                                        color: s.isActive
                                            ? AppColors.success
                                            : AppColors.danger),
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (v) {
                                      if (v == 'profile') _openProfile(s);
                                      if (v == 'edit') _openForm(student: s);
                                      if (v == 'toggle') _toggleActive(s);
                                      if (v == 'copy') _copyFeeReminder(s);
                                      if (v == 'delete') _remove(s);
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(
                                          value: 'profile',
                                          child: Text('Profile')),
                                      const PopupMenuItem(
                                          value: 'edit', child: Text('Edit')),
                                      PopupMenuItem(
                                          value: 'toggle',
                                          child: Text(s.isActive
                                              ? 'Deactivate'
                                              : 'Activate')),
                                      const PopupMenuItem(
                                          value: 'copy',
                                          child: Text('Copy Fee Reminder')),
                                      const PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete')),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StudentProfileSheet extends StatefulWidget {
  final Student student;
  const _StudentProfileSheet({required this.student});

  @override
  State<_StudentProfileSheet> createState() => _StudentProfileSheetState();
}

class _StudentProfileSheetState extends State<_StudentProfileSheet> {
  Uint8List? _photoBytes;
  bool _loadingPhoto = true;
  bool _uploading = false;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  Future<void> _loadPhoto() async {
    setState(() => _loadingPhoto = true);
    try {
      final bytes = await ApiClient.instance
          .getBytes('/students/${widget.student.id}/photo');
      _photoBytes = Uint8List.fromList(bytes);
    } on ApiException {
      _photoBytes = null;
    } finally {
      if (mounted) setState(() => _loadingPhoto = false);
    }
  }

  Future<void> _uploadPhoto() async {
    XFile? photo;
    try {
      photo = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 70,
          preferredCameraDevice: CameraDevice.front);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not open camera — check camera permission')));
      return;
    }
    if (photo == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await photo.readAsBytes();
      await ApiClient.instance.post('/students/${widget.student.id}/photo',
          body: {'photo_base64': base64Encode(bytes)});
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Photo saved')));
      await _loadPhoto();
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.student;
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
            Text('Student Profile',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Center(
              child: _loadingPhoto
                  ? const SizedBox(
                      height: 140,
                      width: 140,
                      child: Center(child: CircularProgressIndicator()))
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _photoBytes != null
                          ? Image.memory(_photoBytes!,
                              width: 140, height: 140, fit: BoxFit.cover)
                          : Container(
                              width: 140,
                              height: 140,
                              color: AppColors.brandLight,
                              alignment: Alignment.center,
                              child: const Text('No photo',
                                  style: TextStyle(color: AppColors.textMuted)),
                            ),
                    ),
            ),
            const SizedBox(height: 12),
            Center(
              child: OutlinedButton.icon(
                onPressed: _uploading ? null : _uploadPhoto,
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.camera_alt_outlined),
                label: const Text('Upload Photo'),
              ),
            ),
            const SizedBox(height: 20),
            _row('Student ID', '#${s.id}'),
            _row('Name', s.name),
            _row('Phone', s.phone ?? '-'),
            _row('Emergency Contact', s.phoneSecondary ?? '-'),
            _row('Email',
                s.email.endsWith('@no-login.internal') ? '-' : s.email),
            _row('Status', s.isActive ? 'Active' : 'Inactive'),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold))
        ]),
      );
}

class _StudentForm extends StatefulWidget {
  final Student? student;
  const _StudentForm({this.student});

  @override
  State<_StudentForm> createState() => _StudentFormState();
}

class _StudentFormState extends State<_StudentForm> {
  late final _nameCtrl =
      TextEditingController(text: widget.student?.name ?? '');
  late final _emailCtrl =
      TextEditingController(text: widget.student?.email ?? '');
  late final _phoneCtrl =
      TextEditingController(text: widget.student?.phone ?? '');
  late final _phoneSecondaryCtrl =
      TextEditingController(text: widget.student?.phoneSecondary ?? '');
  final _passwordCtrl = TextEditingController();
  final _additionalDetailsCtrl = TextEditingController();
  bool _saving = false;

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Name is required')));
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.student != null) {
        final body = <String, dynamic>{
          'name': _nameCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'phone_secondary': _phoneSecondaryCtrl.text.trim(),
        };
        if (_passwordCtrl.text.isNotEmpty)
          body['password'] = _passwordCtrl.text;
        await ApiClient.instance
            .put('/students/${widget.student!.id}', body: body);
      } else {
        final body = <String, dynamic>{
          'name': _nameCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'phone_secondary': _phoneSecondaryCtrl.text.trim(),
        };
        if (_emailCtrl.text.trim().isNotEmpty)
          body['email'] = _emailCtrl.text.trim();
        if (_passwordCtrl.text.isNotEmpty)
          body['password'] = _passwordCtrl.text;
        if (_additionalDetailsCtrl.text.trim().isNotEmpty)
          body['additional_details'] = _additionalDetailsCtrl.text.trim();
        await ApiClient.instance.post('/students', body: body);
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
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _phoneSecondaryCtrl.dispose();
    _passwordCtrl.dispose();
    _additionalDetailsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.student != null;
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
            Text(editing ? 'Edit Student' : 'Add Student',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              enabled: !editing,
              decoration: InputDecoration(
                  labelText: 'Email',
                  helperText: editing ? 'Email cannot be changed here' : null),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            TextField(
                controller: _phoneSecondaryCtrl,
                decoration:
                    const InputDecoration(labelText: 'Emergency Contact'),
                keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: InputDecoration(
                  labelText: editing
                      ? 'New Password (optional)'
                      : 'Password (optional)'),
            ),
            if (!editing) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _additionalDetailsCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Additional Details (optional)'),
              ),
            ],
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
