import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/auth_storage.dart';
import '../../core/export_helper.dart';
import '../../core/models.dart';
import '../shared/notification_bell_action.dart';

class CoachReceiptsTab extends StatefulWidget {
  const CoachReceiptsTab({super.key});

  @override
  State<CoachReceiptsTab> createState() => _CoachReceiptsTabState();
}

class _CoachReceiptsTabState extends State<CoachReceiptsTab> {
  List<FeeReceiptRecord> _receipts = [];
  List<RosterStudent> _students = [];
  bool _loading = true;
  int? _downloadingId;
  int? _downloadingCsvId;

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

  void _handleRecordPaymentTap() {
    if (_students.isEmpty) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('No students yet'),
          content: const Text("You don't have any students yet — add one under My Students before recording a payment."),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
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
      builder: (_) => _ReceiptForm(students: _students),
    );
    if (saved == true) _load();
  }

  Future<void> _downloadPdf(FeeReceiptRecord r) async {
    setState(() => _downloadingId = r.id);
    try {
      final bytes = await ApiClient.instance.getBytes('/receipts/${r.id}/pdf');
      await shareExportedFile(bytes, 'receipt_${r.id}.pdf');
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _downloadingId = null);
    }
  }

  Future<void> _downloadCsv(FeeReceiptRecord r) async {
    setState(() => _downloadingCsvId = r.id);
    try {
      final bytes = await ApiClient.instance.getBytes('/receipts/${r.id}/pdf', query: {'fmt': 'csv'});
      await shareExportedFile(bytes, 'receipt_${r.id}.csv');
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _downloadingCsvId = null);
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
      appBar: AppBar(title: const Text('Fee Receipts'), actions: const [NotificationBellAction(), SizedBox(width: 4)]),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'coach-receipts-fab',
        onPressed: _handleRecordPaymentTap,
        icon: const Icon(Icons.add),
        label: const Text('Record Payment'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _students.isEmpty
                  ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text("You don't have any students yet — add one under My Students before recording a payment.")))])
                  : _receipts.isEmpty
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
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (r.status == 'APPROVED') ...[
                                  _downloadingId == r.id
                                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                      : IconButton(icon: const Icon(Icons.picture_as_pdf_outlined), tooltip: 'Receipt (PDF)', onPressed: () => _downloadPdf(r)),
                                  _downloadingCsvId == r.id
                                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                      : IconButton(icon: const Icon(Icons.table_chart_outlined), tooltip: 'Receipt (CSV)', onPressed: () => _downloadCsv(r)),
                                ],
                                Chip(label: Text(r.status, style: const TextStyle(fontSize: 11, color: Colors.white)), backgroundColor: _statusColor(r.status)),
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
  String? _error;
  final _now = DateTime.now();
  late final _monthCtrl = TextEditingController(text: _now.month.toString());
  late final _yearCtrl = TextEditingController(text: _now.year.toString());

  Future<void> _submit() async {
    if (_studentId == null || _amountCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Student and amount are required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.post('/receipts', body: {
        'student_id': _studentId,
        'amount': _amountCtrl.text.trim(),
        'month': int.tryParse(_monthCtrl.text.trim()) ?? _now.month,
        'year': int.tryParse(_yearCtrl.text.trim()) ?? _now.year,
        'payment_mode': _paymentMode,
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
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
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _monthCtrl.dispose();
    _yearCtrl.dispose();
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
            TextField(controller: _amountCtrl, decoration: const InputDecoration(labelText: 'Amount (₹)'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _paymentMode,
              decoration: const InputDecoration(labelText: 'Payment Mode'),
              items: const [
                DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                DropdownMenuItem(value: 'CARD', child: Text('Card')),
                DropdownMenuItem(value: 'BANK_TRANSFER', child: Text('Bank Transfer')),
              ],
              onChanged: (v) => setState(() => _paymentMode = v!),
            ),
            const SizedBox(height: 12),
            TextField(controller: _noteCtrl, decoration: const InputDecoration(labelText: 'Note (optional)'), maxLines: 2),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
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
