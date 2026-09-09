import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/models.dart';
import 'activity_report_screen.dart';
import 'activity_sessions_screen.dart';

class AdminActivitiesTab extends StatefulWidget {
  const AdminActivitiesTab({super.key});

  @override
  State<AdminActivitiesTab> createState() => _AdminActivitiesTabState();
}

class _AdminActivitiesTabState extends State<AdminActivitiesTab> {
  List<Activity> _activities = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/activities') as List;
      _activities = data.map((e) => Activity.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({Activity? activity}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ActivityForm(activity: activity),
    );
    if (saved == true) _load();
  }

  Future<void> _remove(Activity a) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove activity?'),
        content: Text('Remove ${a.name}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.delete('/activities/${a.id}');
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin-activities-fab',
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add Activity'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _activities.isEmpty
                  ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No activities yet.')))])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                      itemCount: _activities.length,
                      itemBuilder: (context, i) {
                        final a = _activities[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: const CircleAvatar(backgroundColor: AppColors.brandLight, child: Icon(Icons.event, color: AppColors.brandOrange)),
                            title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Capacity: ${a.capacity} · Monthly fee: ₹${a.monthlyFee}'),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'manage') {
                                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ManageActivityScreen(activity: a)));
                                }
                                if (v == 'report') {
                                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ActivityReportScreen(activityId: a.id, activityName: a.name)));
                                }
                                if (v == 'sessions') {
                                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ActivitySessionsScreen(activity: a)));
                                }
                                if (v == 'edit') _openForm(activity: a);
                                if (v == 'delete') _remove(a);
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'manage', child: Text('Manage (Classes/Roster)')),
                                const PopupMenuItem(value: 'report', child: Text('Report')),
                                const PopupMenuItem(value: 'sessions', child: Text('Sessions')),
                                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                const PopupMenuItem(value: 'delete', child: Text('Delete')),
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

class _ActivityForm extends StatefulWidget {
  final Activity? activity;
  const _ActivityForm({this.activity});

  @override
  State<_ActivityForm> createState() => _ActivityFormState();
}

class _ActivityFormState extends State<_ActivityForm> {
  late final _nameCtrl = TextEditingController(text: widget.activity?.name ?? '');
  late final _capacityCtrl = TextEditingController(text: widget.activity?.capacity.toString() ?? '20');
  late final _feeCtrl = TextEditingController(text: widget.activity?.monthlyFee ?? '0');
  bool _saving = false;

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name is required')));
      return;
    }
    setState(() => _saving = true);
    try {
      final body = {
        'name': _nameCtrl.text.trim(),
        'capacity': int.tryParse(_capacityCtrl.text.trim()) ?? 20,
        'monthly_fee': _feeCtrl.text.trim(),
      };
      if (widget.activity != null) {
        await ApiClient.instance.put('/activities/${widget.activity!.id}', body: body);
      } else {
        await ApiClient.instance.post('/activities', body: body);
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
    _nameCtrl.dispose();
    _capacityCtrl.dispose();
    _feeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.activity != null;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(editing ? 'Edit Activity' : 'Add Activity', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TextField(controller: _capacityCtrl, decoration: const InputDecoration(labelText: 'Capacity'), keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            TextField(controller: _feeCtrl, decoration: const InputDecoration(labelText: 'Monthly Fee (₹)'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
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

class _ManageActivityScreen extends StatefulWidget {
  final Activity activity;
  const _ManageActivityScreen({required this.activity});

  @override
  State<_ManageActivityScreen> createState() => _ManageActivityScreenState();
}

class _ManageActivityScreenState extends State<_ManageActivityScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);
  List<ClassSession> _classes = [];
  List<RosterStudent> _roster = [];
  List<Coach> _coaches = [];
  List<Student> _allStudents = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/activities/${widget.activity.id}/classes'),
        ApiClient.instance.get('/activities/${widget.activity.id}/roster'),
        ApiClient.instance.get('/coaches'),
        ApiClient.instance.get('/students'),
      ]);
      _classes = (results[0] as List).map((e) => ClassSession.fromJson(e as Map<String, dynamic>)).toList();
      _roster = (results[1] as List).map((e) => RosterStudent.fromJson(e as Map<String, dynamic>)).toList();
      _coaches = (results[2] as List).map((e) => Coach.fromJson(e as Map<String, dynamic>)).toList();
      _allStudents = (results[3] as List).map((e) => Student.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scheduleClass() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ScheduleClassForm(activityId: widget.activity.id, coaches: _coaches),
    );
    if (saved == true) _load();
  }

  Future<void> _editClass(ClassSession c) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ScheduleClassForm(activityId: widget.activity.id, coaches: _coaches, editing: c),
    );
    if (saved == true) _load();
  }

  Future<void> _removeClass(ClassSession c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove class?'),
        content: Text('Remove the class on ${c.date}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.delete('/activities/classes/${c.id}');
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _enrollStudent() async {
    final enrolled = _roster.map((r) => r.id).toSet();
    final available = _allStudents.where((s) => !enrolled.contains(s.id)).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All students are already enrolled.')));
      return;
    }
    final selected = await showDialog<int>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Enroll Student'),
        children: available
            .map((s) => SimpleDialogOption(onPressed: () => Navigator.pop(context, s.id), child: Text(s.name)))
            .toList(),
      ),
    );
    if (selected == null) return;
    try {
      await ApiClient.instance.post('/activities/enroll', body: {'student_id': selected, 'activity_id': widget.activity.id});
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _unenroll(RosterStudent s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove from activity?'),
        content: Text('Remove ${s.name} from ${widget.activity.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.delete('/activities/enroll/${s.enrollmentId}');
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String _coachName(int id) => _coaches.firstWhere((c) => c.id == id, orElse: () => Coach(id: id, name: '#$id', email: '', isActive: true)).name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.activity.name),
        bottom: TabBar(controller: _tabController, tabs: const [Tab(text: 'Classes'), Tab(text: 'Roster')]),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) => FloatingActionButton.extended(
          heroTag: 'manage-activity-fab',
          onPressed: _tabController.index == 0 ? _scheduleClass : _enrollStudent,
          icon: const Icon(Icons.add),
          label: Text(_tabController.index == 0 ? 'Schedule Class' : 'Enroll Student'),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                RefreshIndicator(
                  onRefresh: _load,
                  child: _classes.isEmpty
                      ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No classes scheduled yet.')))])
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                          itemCount: _classes.length,
                          itemBuilder: (context, i) {
                            final c = _classes[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(c.date),
                                subtitle: Text('${c.startTime} - ${c.endTime} · Coach: ${_coachName(c.coachId)}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _editClass(c)),
                                    IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.danger), onPressed: () => _removeClass(c)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                RefreshIndicator(
                  onRefresh: _load,
                  child: _roster.isEmpty
                      ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No students enrolled yet.')))])
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                          itemCount: _roster.length,
                          itemBuilder: (context, i) {
                            final s = _roster[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(s.name),
                                subtitle: Text(s.email.endsWith('@no-login.internal') ? '-' : s.email),
                                trailing: IconButton(icon: const Icon(Icons.person_remove_outlined, color: AppColors.danger), onPressed: () => _unenroll(s)),
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

class _ScheduleClassForm extends StatefulWidget {
  final int activityId;
  final List<Coach> coaches;
  final ClassSession? editing;
  const _ScheduleClassForm({required this.activityId, required this.coaches, this.editing});

  @override
  State<_ScheduleClassForm> createState() => _ScheduleClassFormState();
}

class _ScheduleClassFormState extends State<_ScheduleClassForm> {
  int? _coachId;
  DateTime _date = DateTime.now();
  TimeOfDay _startTime = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 8, minute: 0);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _coachId = e.coachId;
      _date = DateTime.parse(e.date);
      final st = e.startTime.split(':');
      final et = e.endTime.split(':');
      _startTime = TimeOfDay(hour: int.parse(st[0]), minute: int.parse(st[1]));
      _endTime = TimeOfDay(hour: int.parse(et[0]), minute: int.parse(et[1]));
    }
  }

  String _fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Future<void> _submit() async {
    if (_coachId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a coach')));
      return;
    }
    setState(() => _saving = true);
    try {
      final body = {
        'coach_id': _coachId,
        'date': _date.toIso8601String().substring(0, 10),
        'start_time': _fmtTime(_startTime),
        'end_time': _fmtTime(_endTime),
      };
      if (widget.editing != null) {
        await ApiClient.instance.put('/activities/classes/${widget.editing!.id}', body: body);
      } else {
        await ApiClient.instance.post('/activities/classes', body: {...body, 'activity_id': widget.activityId});
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
            Text(widget.editing != null ? 'Edit Class' : 'Schedule Class', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _coachId,
              decoration: const InputDecoration(labelText: 'Coach'),
              items: widget.coaches.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
              onChanged: (v) => setState(() => _coachId = v),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text(_date.toIso8601String().substring(0, 10)),
              onTap: () async {
                final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (picked != null) setState(() => _date = picked);
              },
            ),
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
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(widget.editing != null ? 'Save' : 'Create'),
            ),
          ],
        ),
      ),
    );
  }
}
