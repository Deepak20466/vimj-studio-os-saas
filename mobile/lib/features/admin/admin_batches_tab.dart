import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/models.dart';

const _allDays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const _allMonths = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
const _monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

class AdminBatchesTab extends StatefulWidget {
  const AdminBatchesTab({super.key});

  @override
  State<AdminBatchesTab> createState() => _AdminBatchesTabState();
}

class _AdminBatchesTabState extends State<AdminBatchesTab> {
  List<Batch> _batches = [];
  List<Activity> _activities = [];
  List<Coach> _coaches = [];
  bool _loading = true;

  Map<String, dynamic>? _coverage;
  bool _coverageLoading = true;
  DateTime _coverageDate = DateTime.now();
  int? _removingId;

  @override
  void initState() {
    super.initState();
    _load();
    _loadCoverage();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/batches'),
        ApiClient.instance.get('/activities'),
        ApiClient.instance.get('/coaches'),
      ]);
      _batches = (results[0] as List).map((e) => Batch.fromJson(e as Map<String, dynamic>)).toList();
      _activities = (results[1] as List).map((e) => Activity.fromJson(e as Map<String, dynamic>)).toList();
      _coaches = (results[2] as List).map((e) => Coach.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCoverage() async {
    setState(() => _coverageLoading = true);
    try {
      final data = await ApiClient.instance.get('/batches/coverage', query: {
        'check_date': _coverageDate.toIso8601String().substring(0, 10),
      }) as Map<String, dynamic>;
      _coverage = data;
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _coverageLoading = false);
    }
  }

  Future<void> _pickCoverageDate() async {
    final picked = await showDatePicker(context: context, initialDate: _coverageDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (picked == null) return;
    setState(() => _coverageDate = picked);
    _loadCoverage();
  }

  String _activityName(int id) => _activities.firstWhere((a) => a.id == id, orElse: () => Activity(id: id, name: '#$id', capacity: 0, monthlyFee: '0')).name;
  String _coachName(int? id) {
    if (id == null) return 'Unassigned';
    return _coaches.firstWhere((c) => c.id == id, orElse: () => Coach(id: id, name: '#$id', email: '', isActive: true)).name;
  }

  Future<void> _openForm({Batch? batch}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _BatchForm(batch: batch, activities: _activities, coaches: _coaches),
    );
    if (saved == true) _load();
  }

  Future<void> _generateSessions(Batch b) async {
    final range = await showDialog<List<DateTime>>(
      context: context,
      builder: (_) => const _DateRangeDialog(),
    );
    if (range == null) return;
    try {
      final result = await ApiClient.instance.post('/batches/${b.id}/generate-sessions', body: {
        'start_date': range[0].toIso8601String().substring(0, 10),
        'end_date': range[1].toIso8601String().substring(0, 10),
      }) as Map<String, dynamic>;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['detail'] as String? ?? 'Sessions generated')));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _remove(Batch b) async {
    if (_removingId == b.id) return; // already in flight — ignore a double tap
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete batch?'),
        content: Text('Delete this batch (${_activityName(b.activityId)} @ ${b.location})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _removingId = b.id);
    try {
      await ApiClient.instance.delete('/batches/${b.id}');
      _load();
    } on ApiException catch (e) {
      if (mounted) {
        // A 404 means this batch is already gone (deleted elsewhere, or a
        // duplicate tap raced this same request) — refresh instead of leaving
        // a stale card on screen with a confusing permanent error.
        final message = e.statusCode == 404 ? 'Already deleted — refreshing list' : e.message;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        if (e.statusCode == 404) _load();
      }
    } finally {
      if (mounted) setState(() => _removingId = null);
    }
  }

  Widget _coverageSection() {
    final coverage = _coverage;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Coverage', style: Theme.of(context).textTheme.titleMedium),
                OutlinedButton(onPressed: _pickCoverageDate, child: Text(_coverageDate.toIso8601String().substring(0, 10))),
              ],
            ),
            const SizedBox(height: 8),
            if (_coverageLoading)
              const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
            else if (coverage == null)
              const Text('Failed to load coverage.')
            else ...[
              Text('Batches with no coach assigned', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              if ((coverage['unassigned_batches'] as List).isEmpty)
                const Text('Every active batch has a coach assigned.', style: TextStyle(color: AppColors.textMuted, fontSize: 12))
              else
                ...(coverage['unassigned_batches'] as List).map((b) {
                  final batch = Batch.fromJson(b as Map<String, dynamic>);
                  return Text('• ${_activityName(batch.activityId)} — ${batch.location} (${batch.sessionPeriod}, ${batch.startTime}-${batch.endTime})', style: const TextStyle(fontSize: 12));
                }),
              const SizedBox(height: 12),
              Text('Scheduled today but no session generated yet', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              if ((coverage['batches_not_generated_today'] as List).isEmpty)
                Text('Nothing outstanding for ${_coverageDate.toIso8601String().substring(0, 10)}.', style: const TextStyle(color: AppColors.textMuted, fontSize: 12))
              else
                ...(coverage['batches_not_generated_today'] as List).map((b) {
                  final batch = Batch.fromJson(b as Map<String, dynamic>);
                  return Text('• ${_activityName(batch.activityId)} — ${batch.location} (${_coachName(batch.coachId)}, ${batch.startTime}-${batch.endTime})', style: const TextStyle(fontSize: 12));
                }),
              const SizedBox(height: 12),
              Text('Who takes which activity', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              if ((coverage['activity_coach_map'] as List).isEmpty)
                const Text('No coach-assigned batches yet.', style: TextStyle(color: AppColors.textMuted, fontSize: 12))
              else
                ...(coverage['activity_coach_map'] as List).map((a) {
                  final coaches = (a['coaches'] as List).map((c) => '${c['coach_name']} (${c['batch_count']})').join(', ');
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('${a['activity_name']}: $coaches', style: const TextStyle(fontSize: 12)),
                  );
                }),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Batches')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin-batches-fab',
        onPressed: () {
          if (_activities.isEmpty) {
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('No activities yet'),
                content: const Text('Create an Activity first, then come back here to add a Batch for it.'),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
              ),
            );
            return;
          }
          _openForm();
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Batch'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _load();
                await _loadCoverage();
              },
              child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                      itemCount: 2 + (_batches.isEmpty ? 1 : _batches.length),
                      itemBuilder: (context, i) {
                        if (i == 0) return _coverageSection();
                        if (i == 1) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text('All Batches', style: Theme.of(context).textTheme.titleMedium),
                          );
                        }
                        if (_batches.isEmpty) {
                          return const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No batches yet. Create one to schedule a recurring class.')));
                        }
                        final b = _batches[i - 2];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text('${_activityName(b.activityId)} · ${b.location}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                    _removingId == b.id
                                        ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                                        : PopupMenuButton<String>(
                                            onSelected: (v) {
                                              if (v == 'edit') _openForm(batch: b);
                                              if (v == 'generate') _generateSessions(b);
                                              if (v == 'delete') _remove(b);
                                            },
                                            itemBuilder: (_) => [
                                              const PopupMenuItem(value: 'generate', child: Text('Generate Sessions')),
                                              const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                              const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                            ],
                                          ),
                                  ],
                                ),
                                Text('${b.sessionPeriod} · ${b.startTime} - ${b.endTime}', style: const TextStyle(color: AppColors.textMuted)),
                                Text('Coach: ${_coachName(b.coachId)}', style: const TextStyle(color: AppColors.textMuted)),
                                Text('Days: ${b.daysOfWeek.join(", ")}', style: const TextStyle(color: AppColors.textMuted)),
                                Text(
                                  b.activeMonths.length == 12 ? 'Months: All year' : 'Months: ${b.activeMonths.map((m) => _monthNames[m]).join(", ")}',
                                  style: const TextStyle(color: AppColors.textMuted),
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

class _DateRangeDialog extends StatefulWidget {
  const _DateRangeDialog();

  @override
  State<_DateRangeDialog> createState() => _DateRangeDialogState();
}

class _DateRangeDialogState extends State<_DateRangeDialog> {
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now().add(const Duration(days: 30));

  Future<void> _pick(bool isStart) async {
    final picked = await showDatePicker(context: context, initialDate: isStart ? _start : _end, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (picked == null) return;
    setState(() => isStart ? _start = picked : _end = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Generate Sessions'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: const Text('Start date'), subtitle: Text(_start.toIso8601String().substring(0, 10)), onTap: () => _pick(true)),
          ListTile(title: const Text('End date'), subtitle: Text(_end.toIso8601String().substring(0, 10)), onTap: () => _pick(false)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(context, [_start, _end]), child: const Text('Generate')),
      ],
    );
  }
}

class _BatchForm extends StatefulWidget {
  final Batch? batch;
  final List<Activity> activities;
  final List<Coach> coaches;
  const _BatchForm({this.batch, required this.activities, required this.coaches});

  @override
  State<_BatchForm> createState() => _BatchFormState();
}

class _BatchFormState extends State<_BatchForm> {
  late int? _activityId = widget.batch?.activityId ?? (widget.activities.isNotEmpty ? widget.activities.first.id : null);
  int? _coachId;
  late final _locationCtrl = TextEditingController(text: widget.batch?.location ?? '');
  String _sessionPeriod = 'MORNING';
  TimeOfDay _startTime = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 8, minute: 0);
  late List<String> _days = List.of(widget.batch?.daysOfWeek ?? []);
  late List<int> _months = List.of(widget.batch?.activeMonths ?? _allMonths);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _coachId = widget.batch?.coachId;
    if (widget.batch != null) {
      _sessionPeriod = widget.batch!.sessionPeriod;
      final st = widget.batch!.startTime.split(':');
      final et = widget.batch!.endTime.split(':');
      _startTime = TimeOfDay(hour: int.parse(st[0]), minute: int.parse(st[1]));
      _endTime = TimeOfDay(hour: int.parse(et[0]), minute: int.parse(et[1]));
    }
  }

  String _fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Future<void> _submit() async {
    if (_activityId == null || _locationCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Activity and location are required')));
      return;
    }
    if (_days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one day')));
      return;
    }
    if (_months.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one month')));
      return;
    }
    setState(() => _saving = true);
    try {
      final body = {
        'activity_id': _activityId,
        'coach_id': _coachId,
        'location': _locationCtrl.text.trim(),
        'session_period': _sessionPeriod,
        'start_time': _fmtTime(_startTime),
        'end_time': _fmtTime(_endTime),
        'days_of_week': _days,
        'active_months': _months,
      };
      if (widget.batch != null) {
        await ApiClient.instance.put('/batches/${widget.batch!.id}', body: body);
      } else {
        await ApiClient.instance.post('/batches', body: body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _locationCtrl.dispose();
    super.dispose();
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.brandYellow,
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.batch != null;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(editing ? 'Edit Batch' : 'Add Batch', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _activityId,
              decoration: const InputDecoration(labelText: 'Activity'),
              items: widget.activities.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
              onChanged: (v) => setState(() => _activityId = v),
            ),
            const SizedBox(height: 12),
            TextField(controller: _locationCtrl, decoration: const InputDecoration(labelText: 'Location')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _sessionPeriod,
              decoration: const InputDecoration(labelText: 'Session'),
              items: const [
                DropdownMenuItem(value: 'MORNING', child: Text('Morning')),
                DropdownMenuItem(value: 'AFTERNOON', child: Text('Afternoon')),
                DropdownMenuItem(value: 'EVENING', child: Text('Evening')),
              ],
              onChanged: (v) => setState(() => _sessionPeriod = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _coachId,
              decoration: const InputDecoration(labelText: 'Coach'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Unassigned')),
                ...widget.coaches.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
              ],
              onChanged: (v) => setState(() => _coachId = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Start Time'),
                    subtitle: Text(_startTime.format(context)),
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: _startTime);
                      if (picked != null) setState(() => _startTime = picked);
                    },
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('End Time'),
                    subtitle: Text(_endTime.format(context)),
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: _endTime);
                      if (picked != null) setState(() => _endTime = picked);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Days', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _allDays
                  .map((d) => _chip(d, _days.contains(d), () => setState(() => _days.contains(d) ? _days.remove(d) : _days.add(d))))
                  .toList(),
            ),
            const SizedBox(height: 12),
            Text('Active Months', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _allMonths
                  .map((m) => _chip(_monthNames[m], _months.contains(m), () => setState(() => _months.contains(m) ? _months.remove(m) : _months.add(m))))
                  .toList(),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(editing ? 'Save' : 'Create'),
            ),
          ],
        ),
      ),
    );
  }
}
