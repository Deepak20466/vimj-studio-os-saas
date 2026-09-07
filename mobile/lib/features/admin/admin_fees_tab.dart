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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/fees/unpaid') as List;
      _fees = data.map((e) => AdminFeeRecord.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
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
              child: _fees.isEmpty
                  ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No outstanding fees. Everyone is paid up.')))])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                      itemCount: _fees.length,
                      itemBuilder: (context, i) {
                        final f = _fees[i];
                        return Card(
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
                        );
                      },
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
  late int _month = _now.month;
  late int _year = _now.year;
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
        'month': _month,
        'year': _year,
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
                    controller: TextEditingController(text: _month.toString()),
                    onChanged: (v) => _month = int.tryParse(v) ?? _month,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(labelText: 'Year'),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(text: _year.toString()),
                    onChanged: (v) => _year = int.tryParse(v) ?? _year,
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
