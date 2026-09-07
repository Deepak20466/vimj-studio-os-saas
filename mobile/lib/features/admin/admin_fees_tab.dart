import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/models.dart';

class AdminFeesTab extends StatefulWidget {
  const AdminFeesTab({super.key});

  @override
  State<AdminFeesTab> createState() => _AdminFeesTabState();
}

class _AdminFeesTabState extends State<AdminFeesTab> {
  bool _loading = true;
  List<AdminFeeRecord> _fees = [];
  List<FeeReceiptRecord> _pendingReceipts = [];
  List<FeeReminderDraftRecord> _pendingReminders = [];
  int? _busyReceiptId;
  int? _busyReminderId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/fees/unpaid'),
        ApiClient.instance.get('/receipts/pending'),
        ApiClient.instance.get('/fee-reminders/pending'),
      ]);
      _fees = (results[0] as List).map((e) => AdminFeeRecord.fromJson(e as Map<String, dynamic>)).toList();
      _pendingReceipts = (results[1] as List).map((e) => FeeReceiptRecord.fromJson(e as Map<String, dynamic>)).toList();
      _pendingReminders = (results[2] as List).map((e) => FeeReminderDraftRecord.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decideReceipt(FeeReceiptRecord r, bool approve) async {
    setState(() => _busyReceiptId = r.id);
    try {
      await ApiClient.instance.put('/receipts/${r.id}/${approve ? 'approve' : 'reject'}', body: {});
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busyReceiptId = null);
    }
  }

  Future<void> _decideReminder(FeeReminderDraftRecord d, bool approve) async {
    setState(() => _busyReminderId = d.id);
    try {
      await ApiClient.instance.put('/fee-reminders/${d.id}/${approve ? 'approve' : 'reject'}', body: {});
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busyReminderId = null);
    }
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
                          title: Text('${r.studentName ?? "Student #${r.studentId}"} — ₹${r.amount}'),
                          subtitle: Text('${r.month}/${r.year} · ${r.paymentMode}'),
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
                              Text('${d.studentName ?? "Student #${d.studentId}"} · ${d.month}/${d.year}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(d.message),
                              const SizedBox(height: 8),
                              _busyReminderId == d.id
                                  ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                                  : Row(
                                      children: [
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
                  Text('Unpaid / Overdue Fees', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_fees.isEmpty)
                    const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No outstanding fees. Everyone is paid up.')))
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
                                  Text(f.studentName ?? 'Student #${f.studentId}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Chip(
                                    label: Text(f.status, style: const TextStyle(color: Colors.white, fontSize: 11)),
                                    backgroundColor: _statusColor(f.status),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('${f.month}/${f.year} · ₹${f.amount} · due ${f.dueDate}', style: const TextStyle(color: AppColors.textMuted)),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(onPressed: () => _remind(f), child: const Text('Remind')),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton(onPressed: () => _markPaid(f), child: const Text('Mark Paid')),
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
                    value: _studentId,
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
