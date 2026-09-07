import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api_client.dart';
import '../../core/models.dart';

class LeaveTab extends StatefulWidget {
  const LeaveTab({super.key});

  @override
  State<LeaveTab> createState() => _LeaveTabState();
}

class _LeaveTabState extends State<LeaveTab> {
  List<LeaveRequest> _leaves = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/leave/my') as List;
      _leaves = data.map((e) => LeaveRequest.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openNewLeaveSheet() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _NewLeaveForm(),
    );
    if (result == true) _load();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leave Requests')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'coach-leave-fab',
        onPressed: _openNewLeaveSheet,
        icon: const Icon(Icons.add),
        label: const Text('Request Leave'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _leaves.isEmpty
                  ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No leave requests yet.')))])
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _leaves.length,
                      itemBuilder: (context, i) {
                        final l = _leaves[i];
                        return Card(
                          child: ListTile(
                            title: Text('${l.startDate} to ${l.endDate}'),
                            subtitle: Text(l.reason),
                            trailing: Chip(
                              label: Text(l.status, style: const TextStyle(color: Colors.white, fontSize: 11)),
                              backgroundColor: _statusColor(l.status),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _NewLeaveForm extends StatefulWidget {
  const _NewLeaveForm();

  @override
  State<_NewLeaveForm> createState() => _NewLeaveFormState();
}

class _NewLeaveFormState extends State<_NewLeaveForm> {
  DateTime? _start;
  DateTime? _end;
  final _reasonCtrl = TextEditingController();
  bool _submitting = false;

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (_start == null || _end == null || _reasonCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill in dates and a reason')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await ApiClient.instance.post('/leave/request', body: {
        'start_date': DateFormat('yyyy-MM-dd').format(_start!),
        'end_date': DateFormat('yyyy-MM-dd').format(_end!),
        'reason': _reasonCtrl.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Request Leave', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => _pickDate(isStart: true),
            child: Text(_start == null ? 'Select start date' : DateFormat('MMM d, yyyy').format(_start!)),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _pickDate(isStart: false),
            child: Text(_end == null ? 'Select end date' : DateFormat('MMM d, yyyy').format(_end!)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reasonCtrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder()),
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
