import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/auth_storage.dart';
import '../../core/models.dart';

class CoachFeeRemindersTab extends StatefulWidget {
  const CoachFeeRemindersTab({super.key});

  @override
  State<CoachFeeRemindersTab> createState() => _CoachFeeRemindersTabState();
}

class _CoachFeeRemindersTabState extends State<CoachFeeRemindersTab> {
  List<FeeReminderDraftRecord> _drafts = [];
  List<RosterStudent> _students = [];
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
      final results = await Future.wait([
        ApiClient.instance.get('/fee-reminders/my'),
        session != null ? ApiClient.instance.get('/coaches/${session.userId}/activities') : Future.value([]),
      ]);
      _drafts = (results[0] as List).map((e) => FeeReminderDraftRecord.fromJson(e as Map<String, dynamic>)).toList();
      final activities = (results[1] as List).map((e) => CoachActivityLink.fromJson(e as Map<String, dynamic>)).toList();
      final rosters = await Future.wait(activities.map((a) => ApiClient.instance.get('/activities/${a.activityId}/roster')));
      final seen = <int>{};
      _students = [];
      for (final r in rosters) {
        for (final e in (r as List)) {
          final s = RosterStudent.fromJson(e as Map<String, dynamic>);
          if (seen.add(s.id)) _students.add(s);
        }
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReminderForm(students: _students),
    );
    if (saved == true) _load();
  }

  void _copy(String message) {
    Clipboard.setData(ClipboardData(text: message));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'APPROVED':
        return AppColors.success;
      case 'REJECTED':
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fee Reminders')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'coach-reminders-fab',
        onPressed: _students.isEmpty ? null : _openForm,
        icon: const Icon(Icons.add),
        label: const Text('New Reminder'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _drafts.isEmpty
                  ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No fee reminders drafted yet.')))])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                      itemCount: _drafts.length,
                      itemBuilder: (context, i) {
                        final d = _drafts[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text('${d.studentName ?? "Student #${d.studentId}"} · ${d.month}/${d.year}', style: const TextStyle(fontWeight: FontWeight.bold))),
                                    Chip(label: Text(d.status, style: const TextStyle(fontSize: 11, color: Colors.white)), backgroundColor: _statusColor(d.status)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(d.message),
                                if (d.decisionNote != null) Text('Note: ${d.decisionNote}', style: const TextStyle(color: AppColors.textMuted)),
                                if (d.status == 'APPROVED')
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(onPressed: () => _copy(d.message), icon: const Icon(Icons.copy, size: 16), label: const Text('Copy')),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _ReminderForm extends StatefulWidget {
  final List<RosterStudent> students;
  const _ReminderForm({required this.students});

  @override
  State<_ReminderForm> createState() => _ReminderFormState();
}

class _ReminderFormState extends State<_ReminderForm> {
  late int? _studentId = widget.students.isNotEmpty ? widget.students.first.id : null;
  final _messageCtrl = TextEditingController();
  bool _saving = false;
  final _now = DateTime.now();

  Future<void> _submit() async {
    if (_studentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a student')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiClient.instance.post('/fee-reminders', body: {
        'student_id': _studentId,
        'month': _now.month,
        'year': _now.year,
        if (_messageCtrl.text.trim().isNotEmpty) 'message': _messageCtrl.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
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
            Text('Draft Fee Reminder', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _studentId,
              decoration: const InputDecoration(labelText: 'Student'),
              items: widget.students.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
              onChanged: (v) => setState(() => _studentId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _messageCtrl,
              decoration: const InputDecoration(labelText: 'Message (optional — auto-filled from fee record if left blank)'),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Submit for Approval'),
            ),
          ],
        ),
      ),
    );
  }
}
