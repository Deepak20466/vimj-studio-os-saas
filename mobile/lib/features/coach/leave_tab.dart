import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/auth_storage.dart';
import '../../core/models.dart';
import '../shared/notification_bell_action.dart';

class LeaveTab extends StatefulWidget {
  const LeaveTab({super.key});

  @override
  State<LeaveTab> createState() => _LeaveTabState();
}

class _LeaveTabState extends State<LeaveTab> {
  List<LeaveRequest> _leaves = [];
  Map<String, dynamic>? _balance;
  bool _loading = true;
  int? _busyId;

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
        ApiClient.instance.get('/leave/my'),
        session != null ? ApiClient.instance.get('/leave/balance/${session.userId}', query: {'year': DateTime.now().year}) : Future.value(null),
      ]);
      _leaves = (results[0] as List).map((e) => LeaveRequest.fromJson(e as Map<String, dynamic>)).toList();
      _balance = results[1] as Map<String, dynamic>?;
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

  Future<void> _openEdit(LeaveRequest l) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _NewLeaveForm(editing: l),
    );
    if (result == true) _load();
  }

  Future<void> _cancel(LeaveRequest l) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel leave request?'),
        content: const Text('Cancel this leave request?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes, Cancel', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busyId = l.id);
    try {
      await ApiClient.instance.delete('/leave/${l.id}');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Leave request cancelled')));
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busyId = null);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leave Requests'), actions: const [NotificationBellAction(), SizedBox(width: 4)]),
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
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (_balance != null) ...[
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 1.4,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      children: [
                        _statCard('Entitlement', '${_balance!['entitlement_days']}'),
                        _statCard('Used', '${_balance!['used_days']}'),
                        _statCard('Remaining', '${_balance!['remaining_days']}'),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_leaves.isEmpty)
                    const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No leave requests yet.')))
                  else
                    ..._leaves.map((l) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(child: Text('${l.startDate} to ${l.endDate}', style: const TextStyle(fontWeight: FontWeight.bold))),
                                    Chip(
                                      label: Text(l.status, style: const TextStyle(color: Colors.white, fontSize: 11)),
                                      backgroundColor: _statusColor(l.status),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(l.reason),
                                if (l.decisionNote != null && l.decisionNote!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(l.decisionNote!, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                                ],
                                if (l.status == 'PENDING') ...[
                                  const SizedBox(height: 8),
                                  _busyId == l.id
                                      ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                                      : Row(
                                          children: [
                                            Expanded(child: OutlinedButton(onPressed: () => _openEdit(l), child: const Text('Edit'))),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: OutlinedButton(
                                                onPressed: () => _cancel(l),
                                                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                                                child: const Text('Cancel'),
                                              ),
                                            ),
                                          ],
                                        ),
                                ],
                              ],
                            ),
                          ),
                        )),
                ],
              ),
            ),
    );
  }

  Widget _statCard(String label, String value) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.brandOrange)),
          ],
        ),
      );
}

class _NewLeaveForm extends StatefulWidget {
  final LeaveRequest? editing;
  const _NewLeaveForm({this.editing});

  @override
  State<_NewLeaveForm> createState() => _NewLeaveFormState();
}

class _NewLeaveFormState extends State<_NewLeaveForm> {
  DateTime? _start;
  DateTime? _end;
  late final _reasonCtrl = TextEditingController(text: widget.editing?.reason ?? '');
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.editing != null) {
      _start = DateTime.tryParse(widget.editing!.startDate);
      _end = DateTime.tryParse(widget.editing!.endDate);
    }
  }

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
      final body = {
        'start_date': DateFormat('yyyy-MM-dd').format(_start!),
        'end_date': DateFormat('yyyy-MM-dd').format(_end!),
        'reason': _reasonCtrl.text.trim(),
      };
      if (widget.editing != null) {
        await ApiClient.instance.put('/leave/${widget.editing!.id}', body: body);
      } else {
        await ApiClient.instance.post('/leave/request', body: body);
      }
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
          Text(widget.editing != null ? 'Edit Leave Request' : 'Request Leave', style: Theme.of(context).textTheme.titleLarge),
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
            child: _submitting
                ? const CircularProgressIndicator(color: Colors.white)
                : Text(widget.editing != null ? 'Save' : 'Submit Request'),
          ),
        ],
      ),
    );
  }
}
