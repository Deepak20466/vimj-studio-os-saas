import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/auth_storage.dart';
import '../../core/models.dart';

class CoachReceiptsTab extends StatefulWidget {
  const CoachReceiptsTab({super.key});

  @override
  State<CoachReceiptsTab> createState() => _CoachReceiptsTabState();
}

class _CoachReceiptsTabState extends State<CoachReceiptsTab> {
  List<FeeReceiptRecord> _receipts = [];
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
        ApiClient.instance.get('/receipts/my'),
        session != null ? ApiClient.instance.get('/coaches/${session.userId}/activities') : Future.value([]),
      ]);
      _receipts = (results[0] as List).map((e) => FeeReceiptRecord.fromJson(e as Map<String, dynamic>)).toList();
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
      builder: (_) => _ReceiptForm(students: _students),
    );
    if (saved == true) _load();
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
      appBar: AppBar(title: const Text('Fee Receipts')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'coach-receipts-fab',
        onPressed: _students.isEmpty ? null : _openForm,
        icon: const Icon(Icons.add),
        label: const Text('Record Payment'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _receipts.isEmpty
                  ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No fee receipts submitted yet.')))])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                      itemCount: _receipts.length,
                      itemBuilder: (context, i) {
                        final r = _receipts[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text('${r.studentName ?? "Student #${r.studentId}"} — ₹${r.amount}'),
                            subtitle: Text('${r.month}/${r.year} · ${r.paymentMode}${r.decisionNote != null ? "\n${r.decisionNote}" : ""}'),
                            isThreeLine: r.decisionNote != null,
                            trailing: Chip(label: Text(r.status, style: const TextStyle(fontSize: 11, color: Colors.white)), backgroundColor: _statusColor(r.status)),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _ReceiptForm extends StatefulWidget {
  final List<RosterStudent> students;
  const _ReceiptForm({required this.students});

  @override
  State<_ReceiptForm> createState() => _ReceiptFormState();
}

class _ReceiptFormState extends State<_ReceiptForm> {
  late int? _studentId = widget.students.isNotEmpty ? widget.students.first.id : null;
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _paymentMode = 'CASH';
  bool _saving = false;
  final _now = DateTime.now();

  Future<void> _submit() async {
    if (_studentId == null || _amountCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Student and amount are required')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiClient.instance.post('/receipts', body: {
        'student_id': _studentId,
        'amount': _amountCtrl.text.trim(),
        'month': _now.month,
        'year': _now.year,
        'payment_mode': _paymentMode,
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
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
    _amountCtrl.dispose();
    _noteCtrl.dispose();
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
            Text('New Fee Receipt', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _studentId,
              decoration: const InputDecoration(labelText: 'Student'),
              items: widget.students.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
              onChanged: (v) => setState(() => _studentId = v),
            ),
            const SizedBox(height: 12),
            TextField(controller: _amountCtrl, decoration: const InputDecoration(labelText: 'Amount (₹)'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _paymentMode,
              decoration: const InputDecoration(labelText: 'Payment Mode'),
              items: const [
                DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                DropdownMenuItem(value: 'CARD', child: Text('Card')),
                DropdownMenuItem(value: 'OTHER', child: Text('Other')),
              ],
              onChanged: (v) => setState(() => _paymentMode = v!),
            ),
            const SizedBox(height: 12),
            TextField(controller: _noteCtrl, decoration: const InputDecoration(labelText: 'Note (optional)'), maxLines: 2),
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
