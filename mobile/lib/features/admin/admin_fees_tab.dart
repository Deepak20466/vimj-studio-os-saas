import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/export_helper.dart';
import '../../core/models.dart';

class AdminFeesTab extends StatefulWidget {
  const AdminFeesTab({super.key});

  @override
  State<AdminFeesTab> createState() => _AdminFeesTabState();
}

class _AdminFeesTabState extends State<AdminFeesTab> {
  bool _loading = true;
  bool _unpaidOnly = true;
  List<AdminFeeRecord> _fees = [];
  List<FeeReceiptRecord> _pendingReceipts = [];
  List<FeeReceiptRecord> _approvedReceipts = [];
  List<FeeReminderDraftRecord> _pendingReminders = [];
  Map<int, String> _studentNames = {};
  int? _busyReceiptId;
  int? _busyReminderId;
  int? _downloadingReceiptId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiClient.instance.get(_unpaidOnly ? '/fees/unpaid' : '/fees'),
        ApiClient.instance.get('/receipts/pending'),
        ApiClient.instance.get('/receipts'),
        ApiClient.instance.get('/fee-reminders/pending'),
        ApiClient.instance.get('/students'),
      ]);
      _fees = (results[0] as List).map((e) => AdminFeeRecord.fromJson(e as Map<String, dynamic>)).toList();
      _pendingReceipts = (results[1] as List).map((e) => FeeReceiptRecord.fromJson(e as Map<String, dynamic>)).toList();
      _approvedReceipts = (results[2] as List)
          .map((e) => FeeReceiptRecord.fromJson(e as Map<String, dynamic>))
          .where((r) => r.status == 'APPROVED')
          .toList();
      _pendingReminders = (results[3] as List).map((e) => FeeReminderDraftRecord.fromJson(e as Map<String, dynamic>)).toList();
      _studentNames = {for (final s in (results[4] as List)) (s['id'] as int): s['name'] as String};
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _feeStudentName(AdminFeeRecord f) => f.studentName ?? _studentNames[f.studentId] ?? 'Student #${f.studentId}';
  String _receiptStudentName(FeeReceiptRecord r) => r.studentName ?? _studentNames[r.studentId] ?? 'Student #${r.studentId}';

  Future<String?> _promptReason(String title) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Reason (optional)'), maxLines: 2),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Confirm')),
        ],
      ),
    ).then((value) {
      ctrl.dispose();
      return value;
    });
  }

  Future<void> _decideReceipt(FeeReceiptRecord r, bool approve) async {
    String note = '';
    if (!approve) {
      final result = await _promptReason('Reject receipt');
      if (result == null) return;
      note = result;
    }
    setState(() => _busyReceiptId = r.id);
    try {
      await ApiClient.instance.put('/receipts/${r.id}/${approve ? 'approve' : 'reject'}', body: {'decision_note': note});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(approve ? 'Receipt approved — fee marked paid' : 'Receipt rejected')));
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busyReceiptId = null);
    }
  }

  Future<void> _downloadReceiptPdf(int receiptId) async {
    if (_downloadingReceiptId == receiptId) return; // already in flight — ignore a double tap
    setState(() => _downloadingReceiptId = receiptId);
    try {
      final bytes = await ApiClient.instance.getBytes('/receipts/$receiptId/pdf');
      await shareExportedFile(bytes, 'receipt_$receiptId.pdf');
    } on ApiException catch (e) {
      if (mounted) {
        // A 404 means this receipt no longer exists (deleted/changed elsewhere) —
        // refresh so the stale row disappears instead of repeatedly 404ing.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        if (e.statusCode == 404) _load();
      }
    } finally {
      if (mounted) setState(() => _downloadingReceiptId = null);
    }
  }

  Future<void> _downloadFeeReceiptPdf(AdminFeeRecord f) async {
    if (_downloadingReceiptId == f.id) return; // already in flight — ignore a double tap
    setState(() => _downloadingReceiptId = f.id);
    try {
      final bytes = await ApiClient.instance.getBytes('/fees/${f.id}/receipt');
      await shareExportedFile(bytes, 'receipt_${f.id}.pdf');
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        if (e.statusCode == 404) _load();
      }
    } finally {
      if (mounted) setState(() => _downloadingReceiptId = null);
    }
  }

  Future<void> _decideReminder(FeeReminderDraftRecord d, bool approve) async {
    String note = '';
    if (!approve) {
      final result = await _promptReason('Reject reminder');
      if (result == null) return;
      note = result;
    }
    setState(() => _busyReminderId = d.id);
    try {
      await ApiClient.instance.put('/fee-reminders/${d.id}/${approve ? 'approve' : 'reject'}', body: {'decision_note': note});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(approve ? 'Reminder approved and sent' : 'Reminder rejected')));
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busyReminderId = null);
    }
  }

  Future<void> _copyMessage(String message) async {
    await Clipboard.setData(ClipboardData(text: message));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message copied — paste it into WhatsApp')));
  }

  Future<void> _markPaid(AdminFeeRecord f) async {
    try {
      await ApiClient.instance.post('/fees/mark-paid', body: {'fee_id': f.id});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked as paid')));
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _remind(AdminFeeRecord f) async {
    try {
      await ApiClient.instance.post('/fees/${f.id}/remind');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reminder sent')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openCreate() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _FeeForm(),
    );
    if (saved == true) _load();
  }

  Future<void> _openEdit(AdminFeeRecord f) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FeeEditForm(fee: f, studentName: _feeStudentName(f)),
    );
    if (saved == true) _load();
  }

  Future<void> _remove(AdminFeeRecord f) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete fee record?'),
        content: Text('Delete the ${f.month}/${f.year} fee record for ${_feeStudentName(f)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.delete('/fees/${f.id}');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fee record deleted')));
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'PAID':
        return AppColors.success;
      case 'OVERDUE':
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin-fees-fab',
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('Add Fee'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                children: [
                  if (_pendingReceipts.isNotEmpty) ...[
                    Text('Pending Fee Receipts (from Coaches)', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ..._pendingReceipts.map(
                      (r) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text('${_receiptStudentName(r)} — ₹${r.amount}'),
                          subtitle: Text('${r.month}/${r.year} · ${r.paymentMode}${r.decisionNote != null && r.decisionNote!.isNotEmpty ? "\n${r.decisionNote}" : ""}'),
                          isThreeLine: r.decisionNote != null && r.decisionNote!.isNotEmpty,
                          trailing: _busyReceiptId == r.id
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(icon: const Icon(Icons.check_circle, color: AppColors.success), onPressed: () => _decideReceipt(r, true)),
                                    IconButton(icon: const Icon(Icons.cancel, color: AppColors.danger), onPressed: () => _decideReceipt(r, false)),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_approvedReceipts.isNotEmpty) ...[
                    Text('Approved Fee Receipts', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ..._approvedReceipts.map(
                      (r) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text('${_receiptStudentName(r)} — ₹${r.amount}'),
                          subtitle: Text('${r.month}/${r.year}'),
                          trailing: _downloadingReceiptId == r.id
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : IconButton(icon: const Icon(Icons.picture_as_pdf_outlined), tooltip: 'Receipt (PDF)', onPressed: () => _downloadReceiptPdf(r.id)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_pendingReminders.isNotEmpty) ...[
                    Text('Pending Fee Reminder Drafts (from Coaches)', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ..._pendingReminders.map(
                      (d) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${d.studentName ?? _studentNames[d.studentId] ?? "Student #${d.studentId}"} · ${d.month}/${d.year}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(d.message),
                              const SizedBox(height: 8),
                              _busyReminderId == d.id
                                  ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                                  : Row(
                                      children: [
                                        OutlinedButton(onPressed: () => _copyMessage(d.message), child: const Text('Copy')),
                                        const SizedBox(width: 10),
                                        Expanded(child: OutlinedButton(onPressed: () => _decideReminder(d, false), child: const Text('Reject'))),
                                        const SizedBox(width: 10),
                                        Expanded(child: ElevatedButton(onPressed: () => _decideReminder(d, true), child: const Text('Approve & Send'))),
                                      ],
                                    ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_unpaidOnly ? 'Unpaid / Overdue Fees' : 'All Fee Records', style: Theme.of(context).textTheme.titleMedium),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Unpaid only', style: TextStyle(fontSize: 12)),
                          Switch(
                            value: _unpaidOnly,
                            onChanged: (v) {
                              setState(() => _unpaidOnly = v);
                              _load();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_fees.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(child: Text(_unpaidOnly ? 'No outstanding fees. Everyone is paid up.' : 'No fee records yet.')),
                    )
                  else
                    ..._fees.map(
                      (f) => Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(child: Text(_feeStudentName(f), style: const TextStyle(fontWeight: FontWeight.bold))),
                                  Chip(
                                    label: Text(f.status, style: const TextStyle(color: Colors.white, fontSize: 11)),
                                    backgroundColor: _statusColor(f.status),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('${f.month}/${f.year} · ₹${f.amount} · balance ₹${f.balanceAmount} · due ${f.dueDate}', style: const TextStyle(color: AppColors.textMuted)),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  if (f.status != 'PAID') ...[
                                    Expanded(child: OutlinedButton(onPressed: () => _remind(f), child: const Text('Remind'))),
                                    const SizedBox(width: 10),
                                    Expanded(child: ElevatedButton(onPressed: () => _markPaid(f), child: const Text('Mark Paid'))),
                                  ] else
                                    Expanded(
                                      child: _downloadingReceiptId == f.id
                                          ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                                          : OutlinedButton(onPressed: () => _downloadFeeReceiptPdf(f), child: const Text('Receipt (PDF)')),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(child: TextButton(onPressed: () => _openEdit(f), child: const Text('Edit'))),
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () => _remove(f),
                                      style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                                      child: const Text('Delete'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _FeeForm extends StatefulWidget {
  const _FeeForm();

  @override
  State<_FeeForm> createState() => _FeeFormState();
}

class _FeeFormState extends State<_FeeForm> {
  List<Student> _students = [];
  int? _studentId;
  final _now = DateTime.now();
  late final _monthCtrl = TextEditingController(text: _now.month.toString());
  late final _yearCtrl = TextEditingController(text: _now.year.toString());
  final _amountCtrl = TextEditingController();
  final _dueDateCtrl = TextEditingController();
  bool _loadingStudents = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    try {
      final data = await ApiClient.instance.get('/students') as List;
      _students = data.map((e) => Student.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loadingStudents = false);
    }
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _dueDateCtrl.text = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
  }

  Future<void> _submit() async {
    if (_studentId == null || _amountCtrl.text.trim().isEmpty || _dueDateCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill in all fields')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiClient.instance.post('/fees', body: {
        'student_id': _studentId,
        'month': int.tryParse(_monthCtrl.text.trim()) ?? _now.month,
        'year': int.tryParse(_yearCtrl.text.trim()) ?? _now.year,
        'amount': _amountCtrl.text.trim(),
        'due_date': _dueDateCtrl.text.trim(),
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
    _monthCtrl.dispose();
    _yearCtrl.dispose();
    _amountCtrl.dispose();
    _dueDateCtrl.dispose();
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
            Text('Add Fee', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _loadingStudents
                ? const Center(child: CircularProgressIndicator())
                : DropdownButtonFormField<int>(
                    initialValue: _studentId,
                    decoration: const InputDecoration(labelText: 'Student'),
                    items: _students.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                    onChanged: (v) => setState(() => _studentId = v),
                  ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(labelText: 'Month'),
                    keyboardType: TextInputType.number,
                    controller: _monthCtrl,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(labelText: 'Year'),
                    keyboardType: TextInputType.number,
                    controller: _yearCtrl,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(controller: _amountCtrl, decoration: const InputDecoration(labelText: 'Amount (₹)'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 12),
            TextField(
              controller: _dueDateCtrl,
              readOnly: true,
              decoration: const InputDecoration(labelText: 'Due Date', suffixIcon: Icon(Icons.calendar_today)),
              onTap: _pickDueDate,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeeEditForm extends StatefulWidget {
  final AdminFeeRecord fee;
  final String studentName;
  const _FeeEditForm({required this.fee, required this.studentName});

  @override
  State<_FeeEditForm> createState() => _FeeEditFormState();
}

class _FeeEditFormState extends State<_FeeEditForm> {
  late final _amountCtrl = TextEditingController(text: widget.fee.amount);
  late final _balanceCtrl = TextEditingController(text: widget.fee.balanceAmount);
  late final _dueDateCtrl = TextEditingController(text: widget.fee.dueDate);
  late String _status = widget.fee.status;
  bool _saving = false;

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(context: context, initialDate: DateTime.tryParse(_dueDateCtrl.text) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (picked == null) return;
    setState(() => _dueDateCtrl.text = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      await ApiClient.instance.put('/fees/${widget.fee.id}', body: {
        'amount': _amountCtrl.text.trim(),
        'balance_amount': _balanceCtrl.text.trim(),
        'due_date': _dueDateCtrl.text.trim(),
        'status': _status,
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
    _balanceCtrl.dispose();
    _dueDateCtrl.dispose();
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
            Text('Edit Fee — ${widget.studentName}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(controller: _amountCtrl, decoration: const InputDecoration(labelText: 'Amount (₹)'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(controller: _balanceCtrl, decoration: const InputDecoration(labelText: 'Balance Amount (₹)'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                ),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: () => setState(() => _balanceCtrl.text = _amountCtrl.text), child: const Text('Generate')),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Outstanding amount still owed. "Generate" resets it to the full fee amount. Setting it to 0 marks the fee as paid.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dueDateCtrl,
              readOnly: true,
              decoration: const InputDecoration(labelText: 'Due Date', suffixIcon: Icon(Icons.calendar_today)),
              onTap: _pickDueDate,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'UNPAID', child: Text('Unpaid')),
                DropdownMenuItem(value: 'OVERDUE', child: Text('Overdue')),
                DropdownMenuItem(value: 'PAID', child: Text('Paid')),
              ],
              onChanged: (v) => setState(() => _status = v!),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
