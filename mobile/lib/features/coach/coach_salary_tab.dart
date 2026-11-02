import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/auth_storage.dart';
import '../../core/export_helper.dart';
import '../../core/models.dart';

class CoachSalaryTab extends StatefulWidget {
  const CoachSalaryTab({super.key});

  @override
  State<CoachSalaryTab> createState() => _CoachSalaryTabState();
}

class _CoachSalaryTabState extends State<CoachSalaryTab> {
  bool _loading = true;
  int? _busySalaryId;
  String? _error;
  String? _exporting;
  List<SalaryRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final session = await AuthStorage.load();
      final coachId = session?.userId;
      if (coachId == null) throw ApiException(401, 'Please sign in again.');
      final data = await ApiClient.instance
          .get('/salary/coach/${coachId.toString()}') as List;
      _records = data
          .map((item) => SalaryRecord.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _error = e is ApiException
          ? e.message
          : 'Could not load salary history. Please try again.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _export(String format) async {
    setState(() => _exporting = format);
    try {
      final bytes = await ApiClient.instance
          .getBytes('/salary/export', query: {'fmt': format});
      final filename =
          format == 'csv' ? 'my_salary_records.csv' : 'my_salary_records.pdf';
      await shareExportedFile(bytes, filename);
    } catch (e) {
      if (mounted) {
        final message = e is ApiException
            ? e.message
            : 'Salary export failed. Please try again.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _exporting = null);
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
    } catch (e) {
      if (mounted) {
        final message = e is ApiException
            ? e.message
            : 'Could not acknowledge salary. Please try again.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
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
      appBar: AppBar(
        title: const Text('Salary'),
        actions: [
          IconButton(
            tooltip: 'Download salary PDF',
            onPressed: _loading || _records.isEmpty || _exporting != null
                ? null
                : () => _export('pdf'),
            icon: _exporting == 'pdf'
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
          ),
          IconButton(
            tooltip: 'Download salary CSV',
            onPressed: _loading || _records.isEmpty || _exporting != null
                ? null
                : () => _export('csv'),
            icon: _exporting == 'csv'
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.table_view_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                children: [
                  if (_error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: ListTile(
                        leading: const Icon(Icons.cloud_off_outlined),
                        title: Text(_error!),
                        trailing: IconButton(
                          tooltip: 'Retry',
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                        ),
                      ),
                    ),
                  if (_error == null && _records.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('No salary records yet.')),
                    ),
                  for (final record in _records)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: AppColors.brandLight,
                          child: Icon(Icons.account_balance_wallet,
                              color: AppColors.brandOrange),
                        ),
                        title: Text(
                          DateFormat('MMMM yyyy')
                              .format(DateTime(record.year, record.month)),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Rs ${record.amount}\nNotified: ${_date(record.notifiedAt)}'
                            '${record.acknowledgedDate == null ? '' : '\nAcknowledged: ${_date(record.acknowledgedDate)}'}',
                          ),
                        ),
                        isThreeLine: true,
                        trailing: record.acknowledgedDate != null
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
                    ),
                ],
              ),
            ),
    );
  }
}
