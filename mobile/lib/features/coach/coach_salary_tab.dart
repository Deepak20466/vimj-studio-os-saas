import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/auth_storage.dart';
import '../../core/models.dart';

class CoachSalaryTab extends StatefulWidget {
  const CoachSalaryTab({super.key});

  @override
  State<CoachSalaryTab> createState() => _CoachSalaryTabState();
}

class _CoachSalaryTabState extends State<CoachSalaryTab> {
  bool _loading = true;
  int? _busySalaryId;
  List<SalaryRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final session = await AuthStorage.load();
      final coachId = session?.userId;
      if (coachId == null) throw ApiException(401, 'Please sign in again.');
      final data =
          await ApiClient.instance.get('/salary/coach/' + coachId.toString()) as List;
      _records = data
          .map((item) => SalaryRecord.fromJson(item as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _acknowledge(SalaryRecord record) async {
    setState(() => _busySalaryId = record.id);
    try {
      await ApiClient.instance.post(
        '/salary/acknowledge',
        body: {'salary_id': record.id},
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Salary receipt acknowledged')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busySalaryId = null);
    }
  }

  String _date(String? value) {
    if (value == null) return 'Not recorded';
    final parsed = DateTime.tryParse(value)?.toLocal();
    return parsed == null ? value : DateFormat('MMM d, yyyy').format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Salary')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _records.isEmpty
                  ? ListView(
                      children: const [
                        Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('No salary records yet.')),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _records.length,
                      itemBuilder: (context, index) {
                        final record = _records[index];
                        final acknowledged = record.acknowledgedDate != null;
                        final period = DateFormat('MMMM yyyy')
                            .format(DateTime(record.year, record.month));
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: AppColors.brandLight,
                              child: Icon(Icons.account_balance_wallet,
                                  color: AppColors.brandOrange),
                            ),
                            title: Text(period,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '₹' + record.amount +
                                    '\nNotified: ' + _date(record.notifiedAt) +
                                    (acknowledged
                                        ? '\nAcknowledged: ' +
                                            _date(record.acknowledgedDate)
                                        : ''),
                              ),
                            ),
                            isThreeLine: true,
                            trailing: acknowledged
                                ? const Chip(
                                    label: Text('Acknowledged'),
                                    visualDensity: VisualDensity.compact,
                                  )
                                : TextButton(
                                    onPressed: _busySalaryId == record.id
                                        ? null
                                        : () => _acknowledge(record),
                                    child: _busySalaryId == record.id
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : const Text('Acknowledge'),
                                  ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}