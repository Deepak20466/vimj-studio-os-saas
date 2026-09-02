import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/auth_storage.dart';
import '../../core/models.dart';

class StudentFeesTab extends StatefulWidget {
  const StudentFeesTab({super.key});

  @override
  State<StudentFeesTab> createState() => _StudentFeesTabState();
}

class _StudentFeesTabState extends State<StudentFeesTab> {
  List<FeeRecord> _fees = [];
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
      final studentId = session?.userId;
      if (studentId == null) return;
      final data = await ApiClient.instance.get('/students/$studentId/fees') as List;
      _fees = data.map((e) => FeeRecord.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'PAID':
        return Colors.green;
      case 'OVERDUE':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final outstanding = _fees.where((f) => f.status != 'PAID').fold<double>(0, (sum, f) => sum + (double.tryParse(f.amount) ?? 0));

    return Scaffold(
      appBar: AppBar(title: const Text('My Fees')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: outstanding > 0 ? Colors.red.shade50 : Colors.green.shade50,
                    child: ListTile(
                      leading: Icon(outstanding > 0 ? Icons.warning_amber : Icons.check_circle, color: outstanding > 0 ? Colors.red : Colors.green),
                      title: const Text('Outstanding Balance'),
                      trailing: Text('₹${outstanding.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleMedium),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Payment History', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_fees.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('No fee records yet.')))
                  else
                    ..._fees.map(
                      (f) => Card(
                        child: ListTile(
                          title: Text('${f.month}/${f.year} — ₹${f.amount}'),
                          subtitle: Text('Due ${f.dueDate}${f.paidDate != null ? ' · Paid ${f.paidDate}' : ''}'),
                          trailing: Chip(
                            label: Text(f.status, style: const TextStyle(color: Colors.white, fontSize: 11)),
                            backgroundColor: _statusColor(f.status),
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
