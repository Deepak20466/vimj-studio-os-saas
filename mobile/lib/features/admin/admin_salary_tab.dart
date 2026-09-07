import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/models.dart';

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
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: const CircleAvatar(backgroundColor: AppColors.brandLight, child: Icon(Icons.account_balance_wallet, color: AppColors.brandOrange)),
                            title: Text(r.coachName ?? 'Coach #${r.coachId}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('${r.month}/${r.year} · ₹${r.amount}'),
                            trailing: r.acknowledgedDate != null
                                ? const Chip(label: Text('Acknowledged', style: TextStyle(color: Colors.white, fontSize: 11)), backgroundColor: AppColors.success, visualDensity: VisualDensity.compact)
                                : const Chip(label: Text('Pending', style: TextStyle(color: Colors.white, fontSize: 11)), backgroundColor: AppColors.warning, visualDensity: VisualDensity.compact),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _SalaryForm extends StatefulWidget {
  const _SalaryForm();

  @override
  State<_SalaryForm> createState() => _SalaryFormState();
}

class _SalaryFormState extends State<_SalaryForm> {
  List<Coach> _coaches = [];
  int? _coachId;
  final _now = DateTime.now();
  late final _monthCtrl = TextEditingController(text: _now.month.toString());
  late final _yearCtrl = TextEditingController(text: _now.year.toString());
  final _amountCtrl = TextEditingController();
  bool _loadingCoaches = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCoaches();
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
      await ApiClient.instance.post('/salary', body: {
        'coach_id': _coachId,
        'month': int.tryParse(_monthCtrl.text.trim()) ?? _now.month,
        'year': int.tryParse(_yearCtrl.text.trim()) ?? _now.year,
        'amount': _amountCtrl.text.trim(),
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
            Text('Add Salary', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _loadingCoaches
                ? const Center(child: CircularProgressIndicator())
                : DropdownButtonFormField<int>(
                    value: _coachId,
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
              child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}
