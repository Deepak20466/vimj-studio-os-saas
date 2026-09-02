import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api_client.dart';
import '../../core/auth_storage.dart';
import '../../core/models.dart';

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
      builder: (_) => const _NewSwapForm(),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Class Swaps')),
      floatingActionButton: FloatingActionButton.extended(
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
                        return Card(
                          child: ListTile(
                            leading: Icon(isCovering ? Icons.call_received : Icons.call_made),
                            title: Text('Class #${s.classId} on ${s.date}'),
                            subtitle: Text(isCovering ? 'You are covering this class' : 'You requested coverage'),
                            trailing: Chip(
                              label: Text(s.status, style: const TextStyle(color: Colors.white, fontSize: 11)),
                              backgroundColor: _statusColor(s.status),
                            ),
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
  DateTime? _date;
  bool _loadingOptions = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final coachData = await ApiClient.instance.get('/coaches/directory') as List;
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final classData = await ApiClient.instance.get('/activities/classes/my', query: {'class_date': today}) as List;
      _coaches = coachData.map((e) => _CoachOption(e['id'] as int, e['name'] as String)).toList();
      _myClasses = classData.map((e) => ClassSession.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loadingOptions = false);
    }
  }

  Future<void> _submit() async {
    if (_selectedCoachId == null || _selectedClassId == null || _date == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a class, covering coach, and date')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await ApiClient.instance.post('/swap/request', body: {
        'covering_coach_id': _selectedCoachId,
        'class_id': _selectedClassId,
        'date': DateFormat('yyyy-MM-dd').format(_date!),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: 'Your class today'),
                  value: _selectedClassId,
                  items: _myClasses
                      .map((c) => DropdownMenuItem(value: c.id, child: Text('${c.startTime} - ${c.endTime}')))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedClassId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: 'Covering coach'),
                  value: _selectedCoachId,
                  items: _coaches.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                  onChanged: (v) => setState(() => _selectedCoachId = v),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 30)),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                  child: Text(_date == null ? 'Select date' : DateFormat('MMM d, yyyy').format(_date!)),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting ? const CircularProgressIndicator(color: Colors.white) : const Text('Submit Request'),
                ),
              ],
            ),
    );
  }
}
