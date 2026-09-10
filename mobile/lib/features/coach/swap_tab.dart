import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/auth_storage.dart';
import '../../core/models.dart';
import '../shared/notification_bell_action.dart';

class SwapTab extends StatefulWidget {
  const SwapTab({super.key});

  @override
  State<SwapTab> createState() => _SwapTabState();
}

class _SwapTabState extends State<SwapTab> {
  List<SwapRequest> _swaps = [];
  bool _loading = true;
  int? _myId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final session = await AuthStorage.load();
      _myId = session?.userId;
      final data = await ApiClient.instance.get('/swap/my') as List;
      _swaps = data.map((e) => SwapRequest.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'APPROVED':
        return Colors.green;
      case 'REJECTED':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Future<void> _openRequestSheet() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _NewSwapForm(),
    );
    if (result == true) _load();
  }

  bool _needsMyResponse(SwapRequest s) => s.initiatedBy == 'ADMIN' && s.status == 'PENDING' && s.coveringCoachId == _myId;

  Future<void> _accept(SwapRequest s) async {
    try {
      await ApiClient.instance.put('/swap/${s.id}/respond', body: {'accept': true});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Swap accepted — you now cover this class')));
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _decline(SwapRequest s) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Decline swap'),
        content: TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reason (optional)'), maxLines: 2),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Decline')),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (confirmed != true) return;
    try {
      await ApiClient.instance.put('/swap/${s.id}/respond', body: {'accept': false, 'decline_reason': reason.isEmpty ? null : reason});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Swap declined')));
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Class Swaps'), actions: const [NotificationBellAction(), SizedBox(width: 4)]),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'coach-swap-fab',
        onPressed: _openRequestSheet,
        icon: const Icon(Icons.swap_horiz),
        label: const Text('Request Swap'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _swaps.isEmpty
                  ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No swap requests yet.')))])
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _swaps.length,
                      itemBuilder: (context, i) {
                        final s = _swaps[i];
                        final isCovering = s.coveringCoachId == _myId;
                        final needsResponse = _needsMyResponse(s);
                        return Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                leading: Icon(isCovering ? Icons.call_received : Icons.call_made),
                                title: Text('Class #${s.classId} on ${s.date}'),
                                subtitle: Text(isCovering ? 'You are covering this class' : 'You requested coverage'),
                                trailing: Chip(
                                  label: Text(s.status, style: const TextStyle(color: Colors.white, fontSize: 11)),
                                  backgroundColor: _statusColor(s.status),
                                ),
                              ),
                              if (needsResponse)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                                  child: Row(
                                    children: [
                                      ElevatedButton(onPressed: () => _accept(s), child: const Text('Accept')),
                                      const SizedBox(width: 8),
                                      OutlinedButton(onPressed: () => _decline(s), child: const Text('Decline')),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _CoachOption {
  final int id;
  final String name;
  _CoachOption(this.id, this.name);
}

class _NewSwapForm extends StatefulWidget {
  const _NewSwapForm();

  @override
  State<_NewSwapForm> createState() => _NewSwapFormState();
}

class _NewSwapFormState extends State<_NewSwapForm> {
  List<_CoachOption> _coaches = [];
  List<ClassSession> _myClasses = [];
  int? _selectedCoachId;
  int? _selectedClassId;
  bool _loadingOptions = true;
  bool _submitting = false;
  String? _error;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final coachData = await ApiClient.instance.get('/coaches/directory') as List;
      // No class_date filter: pulls every class ever assigned to this coach, past and
      // future — filtered/sorted below to just the upcoming ones. A single hardcoded
      // "today" filter here previously meant a coach could only ever swap today's
      // classes, no matter what date they later picked for the swap itself.
      final classData = await ApiClient.instance.get('/activities/classes/my') as List;
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final upcoming = classData
          .map((e) => ClassSession.fromJson(e as Map<String, dynamic>))
          .where((c) => c.date.compareTo(today) >= 0)
          .toList()
        ..sort((a, b) {
          final byDate = a.date.compareTo(b.date);
          return byDate != 0 ? byDate : a.startTime.compareTo(b.startTime);
        });
      _coaches = coachData.map((e) => _CoachOption(e['id'] as int, e['name'] as String)).toList();
      _myClasses = upcoming.take(60).toList();
    } on ApiException catch (e) {
      _loadError = e.message;
    } finally {
      if (mounted) setState(() => _loadingOptions = false);
    }
  }

  ClassSession? get _selectedClass => _selectedClassId == null ? null : _myClasses.firstWhere((c) => c.id == _selectedClassId);

  Future<void> _submit() async {
    if (_selectedCoachId == null || _selectedClassId == null) {
      setState(() => _error = 'Select a class and a covering coach');
      return;
    }
    final cls = _selectedClass;
    if (cls == null) {
      setState(() => _error = 'Select a class and a covering coach');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ApiClient.instance.post('/swap/request', body: {
        'covering_coach_id': _selectedCoachId,
        'class_id': _selectedClassId,
        'date': cls.date,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _classLabel(ClassSession c) {
    final date = DateFormat('MMM d').format(DateTime.parse(c.date));
    return '$date · ${c.startTime} - ${c.endTime}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: _loadingOptions
          ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Request Class Swap', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                if (_loadError != null) ...[
                  Text(_loadError!, style: const TextStyle(color: AppColors.danger)),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: 'Your class'),
                  value: _selectedClassId,
                  items: _myClasses.map((c) => DropdownMenuItem(value: c.id, child: Text(_classLabel(c)))).toList(),
                  onChanged: _myClasses.isEmpty ? null : (v) => setState(() => _selectedClassId = v),
                ),
                if (_myClasses.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      "You have no upcoming classes to swap. Once your admin assigns you a schedule, they'll show up here.",
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: 'Covering coach'),
                  value: _selectedCoachId,
                  items: _coaches.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                  onChanged: _coaches.isEmpty ? null : (v) => setState(() => _selectedCoachId = v),
                ),
                if (_coaches.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'No other active coaches are available to cover for you yet.',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.danger)),
                ],
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _submitting || _myClasses.isEmpty || _coaches.isEmpty ? null : _submit,
                  child: _submitting
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Submit Request'),
                ),
              ],
            ),
    );
  }
}
