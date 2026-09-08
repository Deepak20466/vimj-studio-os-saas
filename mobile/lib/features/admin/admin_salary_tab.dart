import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/models.dart';

String _formatDate(String isoDate) {
  final parsed = DateTime.tryParse(isoDate);
  return parsed == null ? isoDate : DateFormat('MMM d, yyyy').format(parsed);
}

class AdminSalaryTab extends StatefulWidget {
  const AdminSalaryTab({super.key});

  @override
  State<AdminSalaryTab> createState() => _AdminSalaryTabState();
}

class _AdminSalaryTabState extends State<AdminSalaryTab> {
  bool _loading = true;
  List<AdminSalaryRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/salary') as List;
      _records = data.map((e) => AdminSalaryRecord.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreate() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _SalaryForm(),
    );
    if (saved == true) _load();
  }

  Future<void> _openEdit(AdminSalaryRecord r) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SalaryForm(editing: r),
    );
    if (saved == true) _load();
  }

  Future<void> _remove(AdminSalaryRecord r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete salary record?'),
        content: Text('Delete the ${r.month}/${r.year} salary record for ${r.coachName ?? "Coach #${r.coachId}"}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.delete('/salary/${r.id}');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Salary record deleted')));
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin-salary-fab',
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('Add Salary'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _records.isEmpty
                  ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No salary records yet.')))])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                      itemCount: _records.length,
                      itemBuilder: (context, i) {
                        final r = _records[i];
                        final acknowledged = r.acknowledgedDate != null;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            children: [
                              ListTile(
                                leading: const CircleAvatar(backgroundColor: AppColors.brandLight, child: Icon(Icons.account_balance_wallet, color: AppColors.brandOrange)),
                                title: Text(r.coachName ?? 'Coach #${r.coachId}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('${r.month}/${r.year} · ₹${r.amount}'),
                                    Text(
                                      'Notified: ${r.notifiedAt != null ? _formatDate(r.notifiedAt!) : "-"}',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                                isThreeLine: true,
                                trailing: acknowledged
                                    ? const Chip(label: Text('Acknowledged', style: TextStyle(color: Colors.white, fontSize: 11)), backgroundColor: AppColors.success, visualDensity: VisualDensity.compact)
                                    : const Chip(label: Text('Pending', style: TextStyle(color: Colors.white, fontSize: 11)), backgroundColor: AppColors.warning, visualDensity: VisualDensity.compact),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed: acknowledged ? null : () => _openEdit(r),
                                      child: const Text('Edit'),
                                    ),
                                  ),
                                  Expanded(
                                    child: TextButton(
                                      onPressed: acknowledged ? null : () => _remove(r),
                                      style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                                      child: const Text('Delete'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _SalaryForm extends StatefulWidget {
  final AdminSalaryRecord? editing;
  const _SalaryForm({this.editing});

  @override
  State<_SalaryForm> createState() => _SalaryFormState();
}

class _SalaryFormState extends State<_SalaryForm> {
  List<Coach> _coaches = [];
  int? _coachId;
  final _now = DateTime.now();
  late final _monthCtrl = TextEditingController(text: (widget.editing?.month ?? _now.month).toString());
  late final _yearCtrl = TextEditingController(text: (widget.editing?.year ?? _now.year).toString());
  late final _amountCtrl = TextEditingController(text: widget.editing?.amount ?? '');
  bool _loadingCoaches = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _coachId = widget.editing?.coachId;
    if (widget.editing == null) {
      _loadCoaches();
    } else {
      _loadingCoaches = false;
    }
  }

  Future<void> _loadCoaches() async {
    try {
      final data = await ApiClient.instance.get('/coaches') as List;
      _coaches = data.map((e) => Coach.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loadingCoaches = false);
    }
  }

  Future<void> _submit() async {
    if (_coachId == null || _amountCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill in all fields')));
      return;
    }
    setState(() => _saving = true);
    try {
      final body = {
        'month': int.tryParse(_monthCtrl.text.trim()) ?? _now.month,
        'year': int.tryParse(_yearCtrl.text.trim()) ?? _now.year,
        'amount': _amountCtrl.text.trim(),
      };
      if (widget.editing != null) {
        await ApiClient.instance.put('/salary/${widget.editing!.id}', body: body);
      } else {
        await ApiClient.instance.post('/salary', body: {...body, 'coach_id': _coachId});
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
    _monthCtrl.dispose();
    _yearCtrl.dispose();
    _amountCtrl.dispose();
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
            Text(widget.editing != null ? 'Edit Salary Record' : 'Add Salary', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (widget.editing != null)
              TextField(
                enabled: false,
                controller: TextEditingController(text: widget.editing!.coachName ?? 'Coach #${widget.editing!.coachId}'),
                decoration: const InputDecoration(labelText: 'Coach'),
              )
            else
              _loadingCoaches
                  ? const Center(child: CircularProgressIndicator())
                  : DropdownButtonFormField<int>(
                      initialValue: _coachId,
                      decoration: const InputDecoration(labelText: 'Coach'),
                      items: _coaches.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                      onChanged: (v) => setState(() => _coachId = v),
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
