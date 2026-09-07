import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/models.dart';

class AdminComplianceTab extends StatefulWidget {
  const AdminComplianceTab({super.key});

  @override
  State<AdminComplianceTab> createState() => _AdminComplianceTabState();
}

class _AdminComplianceTabState extends State<AdminComplianceTab> {
  ComplianceSummary? _summary;
  List<PendingLateSubmission> _pending = [];
  bool _loading = true;
  int? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month - 1, now.day);
      final results = await Future.wait([
        ApiClient.instance.get('/compliance/summary', query: {
          'start_date': start.toIso8601String().substring(0, 10),
          'end_date': now.toIso8601String().substring(0, 10),
        }),
        ApiClient.instance.get('/compliance/pending'),
      ]);
      _summary = ComplianceSummary.fromJson(results[0] as Map<String, dynamic>);
      _pending = (results[1] as List).map((e) => PendingLateSubmission.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(PendingLateSubmission p, bool approve) async {
    setState(() => _busyId = p.id);
    try {
      await ApiClient.instance.put('/compliance/late/${p.id}/${approve ? 'approve' : 'reject'}');
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Color _stateColor(String state) {
    switch (state) {
      case 'SUBMITTED':
      case 'LATE_APPROVED':
        return AppColors.success;
      case 'PENDING':
        return AppColors.warning;
      case 'DELAYED':
        return AppColors.danger;
      case 'NOT_CONDUCTED':
      case 'LATE_REJECTED':
        return AppColors.textMuted;
      default:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_pending.isNotEmpty) ...[
                  Text('Pending Late-Attendance Approvals', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ..._pending.map(
                    (p) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text('${p.coachName} · ${p.activityName}'),
                        subtitle: Text('${p.classDate}${p.lateReason != null ? "\nReason: ${p.lateReason}" : ""}'),
                        isThreeLine: p.lateReason != null,
                        trailing: _busyId == p.id
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(icon: const Icon(Icons.check_circle, color: AppColors.success), onPressed: () => _decide(p, true)),
                                  IconButton(icon: const Icon(Icons.cancel, color: AppColors.danger), onPressed: () => _decide(p, false)),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Text('Compliance Overview (last 30 days)', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_summary != null)
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 2.4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: [
                      _statCard('Submitted', _summary!.submitted, AppColors.success),
                      _statCard('Pending', _summary!.pending, AppColors.warning),
                      _statCard('Delayed', _summary!.delayed, AppColors.danger),
                      _statCard('Not Conducted', _summary!.notConducted, AppColors.textMuted),
                    ],
                  ),
                const SizedBox(height: 12),
                if (_summary != null)
                  ..._summary!.rows.map(
                    (r) => Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        title: Text('${r.activityName} · ${r.coachName}'),
                        subtitle: Text('${r.classDate} · ends ${r.endTime}${r.skipReason != null ? "\n${r.skipReason}" : ""}'),
                        trailing: Chip(
                          label: Text(r.state, style: const TextStyle(fontSize: 11, color: Colors.white)),
                          backgroundColor: _stateColor(r.state),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
  }

  Widget _statCard(String label, int value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            Text('$value', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}
