import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/auth_storage.dart';
import '../../core/models.dart';
import '../shared/notification_bell_action.dart';

class CoachFeeRemindersTab extends StatefulWidget {
  const CoachFeeRemindersTab({super.key});

  @override
  State<CoachFeeRemindersTab> createState() => _CoachFeeRemindersTabState();
}

class _CoachFeeRemindersTabState extends State<CoachFeeRemindersTab> {
  List<FeeReminderDraftRecord> _drafts = [];
  List<RosterStudent> _students = [];
  bool _loading = true;
  String _search = '';
  String? _statusFilter;
  String? _periodFilter;
  List<FeeReminderDraftRecord> get _visibleDrafts => _drafts
      .where((d) =>
          (_search.isEmpty ||
              '${d.studentName ?? ''} ${d.message} ${d.decisionNote ?? ''} ${d.month}/${d.year} ${d.status}'
                  .toLowerCase()
                  .contains(_search.trim().toLowerCase())) &&
          (_statusFilter == null || d.status == _statusFilter) &&
          (_periodFilter == null || '${d.month}/${d.year}' == _periodFilter))
      .toList();

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
        session != null
            ? ApiClient.instance.get('/coaches/${session.userId}/activities')
            : Future.value([]),
      ]);
      _drafts = (results[0] as List)
          .map(
              (e) => FeeReminderDraftRecord.fromJson(e as Map<String, dynamic>))
          .toList();
      final activities = (results[1] as List)
          .map((e) => CoachActivityLink.fromJson(e as Map<String, dynamic>))
          .toList();
      final rosters = await Future.wait(activities.map(
          (a) => ApiClient.instance.get('/activities/${a.activityId}/roster')));
      final seen = <int>{};
      _students = [];
      for (final r in rosters) {
        for (final e in (r as List)) {
          final s = RosterStudent.fromJson(e as Map<String, dynamic>);
          if (seen.add(s.id)) _students.add(s);
        }
      }
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleNewReminderTap() {
    if (_students.isEmpty) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('No students yet'),
          content: const Text(
              "You don't have any students yet — add one under My Students before drafting a fee reminder."),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'))
          ],
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
      builder: (_) => _ReminderForm(students: _students),
    );
    if (saved == true) _load();
  }

  void _copy(String message) {
    Clipboard.setData(ClipboardData(text: message));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  Future<void> _deleteDraft(FeeReminderDraftRecord draft) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete fee reminder?'),
        content: const Text('This removes the pending reminder draft.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.delete('/fee-reminders/${draft.id}');
      if (!mounted) return;
      setState(() => _drafts.removeWhere((item) => item.id == draft.id));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Fee reminder deleted')));
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    }
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
      appBar: AppBar(
          title: const Text('Fee Reminders'),
          actions: const [NotificationBellAction(), SizedBox(width: 4)]),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'coach-reminders-fab',
        onPressed: _handleNewReminderTap,
        icon: const Icon(Icons.add),
        label: const Text('New Reminder'),
      ),
      body: _loading && _drafts.isEmpty && _students.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _students.isEmpty
                  ? ListView(children: const [
                      Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                              child: Text(
                                  "You don't have any students yet — add one under My Students before drafting a fee reminder.")))
                    ])
                  : _drafts.isEmpty
                      ? ListView(children: const [
                          Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(
                                  child: Text('No fee reminders drafted yet.')))
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                          itemCount: 1 +
                              (_visibleDrafts.isEmpty
                                  ? 1
                                  : _visibleDrafts.length),
                          itemBuilder: (context, i) {
                            if (i == 0)
                              return Column(children: [
                                TextField(
                                    decoration: InputDecoration(
                                        labelText: 'Search reminders',
                                        prefixIcon: const Icon(Icons.search),
                                        suffixIcon: _search.isEmpty
                                            ? null
                                            : IconButton(
                                                onPressed: () => setState(
                                                    () => _search = ''),
                                                icon: const Icon(Icons.clear))),
                                    onChanged: (v) =>
                                        setState(() => _search = v)),
                                Wrap(spacing: 8, children: [
                                  DropdownButton<String?>(
                                      value: _statusFilter,
                                      hint: const Text('All statuses'),
                                      items: const [
                                        DropdownMenuItem<String?>(
                                            value: null,
                                            child: Text('All statuses')),
                                        DropdownMenuItem<String?>(
                                            value: 'PENDING',
                                            child: Text('Pending')),
                                        DropdownMenuItem<String?>(
                                            value: 'APPROVED',
                                            child: Text('Approved')),
                                        DropdownMenuItem<String?>(
                                            value: 'REJECTED',
                                            child: Text('Rejected'))
                                      ],
                                      onChanged: (v) =>
                                          setState(() => _statusFilter = v)),
                                  DropdownButton<String?>(
                                      value: _periodFilter,
                                      hint: const Text('All periods'),
                                      items: [
                                        const DropdownMenuItem<String?>(
                                            value: null,
                                            child: Text('All periods')),
                                        ..._drafts
                                            .map((d) => '${d.month}/${d.year}')
                                            .toSet()
                                            .map((p) =>
                                                DropdownMenuItem<String?>(
                                                    value: p, child: Text(p)))
                                      ],
                                      onChanged: (v) =>
                                          setState(() => _periodFilter = v)),
                                  if (_search.isNotEmpty ||
                                      _statusFilter != null ||
                                      _periodFilter != null)
                                    TextButton(
                                        onPressed: () => setState(() {
                                              _search = '';
                                              _statusFilter = null;
                                              _periodFilter = null;
                                            }),
                                        child: const Text('Clear filters'))
                                ])
                              ]);
                            if (_visibleDrafts.isEmpty)
                              return const Padding(
                                  padding: EdgeInsets.all(32),
                                  child:
                                      Center(child: Text('No results found.')));
                            final d = _visibleDrafts[i - 1];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                            child: Text(
                                                '${d.studentName ?? "Student #${d.studentId}"} · ${d.month}/${d.year}',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold))),
                                        Chip(
                                            label: Text(d.status,
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.white)),
                                            backgroundColor:
                                                _statusColor(d.status)),
                                        if (d.status == 'PENDING')
                                          IconButton(
                                            tooltip: 'Delete reminder',
                                            icon: const Icon(
                                                Icons.delete_outline,
                                                color: AppColors.danger),
                                            onPressed: () => _deleteDraft(d),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(d.message),
                                    if (d.decisionNote != null)
                                      Text('Note: ${d.decisionNote}',
                                          style: const TextStyle(
                                              color: AppColors.textMuted)),
                                    if (d.status == 'APPROVED')
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton.icon(
                                            onPressed: () => _copy(d.message),
                                            icon: const Icon(Icons.copy,
                                                size: 16),
                                            label: const Text('Copy')),
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
  late int? _studentId =
      widget.students.isNotEmpty ? widget.students.first.id : null;
  final _messageCtrl = TextEditingController();
  bool _saving = false;
  String? _error;
  final _now = DateTime.now();
  late final _monthCtrl = TextEditingController(text: _now.month.toString());
  late final _yearCtrl = TextEditingController(text: _now.year.toString());

  Future<void> _submit() async {
    if (_studentId == null) {
      setState(() => _error = 'Select a student');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.post('/fee-reminders', body: {
        'student_id': _studentId,
        'month': int.tryParse(_monthCtrl.text.trim()) ?? _now.month,
        'year': int.tryParse(_yearCtrl.text.trim()) ?? _now.year,
        if (_messageCtrl.text.trim().isNotEmpty)
          'message': _messageCtrl.text.trim(),
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
    _messageCtrl.dispose();
    _monthCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            Text('Draft Fee Reminder',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _studentId,
              decoration: const InputDecoration(labelText: 'Student'),
              items: widget.students
                  .map(
                      (s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                  .toList(),
              onChanged: (v) => setState(() => _studentId = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _monthCtrl,
                    decoration: const InputDecoration(labelText: 'Month'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _yearCtrl,
                    decoration: const InputDecoration(labelText: 'Year'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _messageCtrl,
              decoration: const InputDecoration(
                  labelText:
                      'Message (optional — auto-filled from fee record if left blank)'),
              maxLines: 3,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
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
                  : const Text('Submit for Approval'),
            ),
          ],
        ),
      ),
    );
  }
}
