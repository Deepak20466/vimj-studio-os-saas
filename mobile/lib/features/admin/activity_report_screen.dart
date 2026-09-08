import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';

String _formatTiming(String startTime) {
  final parts = startTime.split(':');
  int h = int.tryParse(parts[0]) ?? 0;
  final m = parts.length > 1 ? parts[1] : '00';
  final suffix = h >= 12 ? 'PM' : 'AM';
  h = h % 12;
  if (h == 0) h = 12;
  return '$h:$m $suffix';
}

class ActivityReportScreen extends StatefulWidget {
  final int activityId;
  final String activityName;
  const ActivityReportScreen({super.key, required this.activityId, required this.activityName});

  @override
  State<ActivityReportScreen> createState() => _ActivityReportScreenState();
}

class _ActivityReportScreenState extends State<ActivityReportScreen> {
  Map<String, dynamic>? _report;
  bool _loading = true;
  bool _showTimings = false;
  String? _selectedTiming;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/reports/activity/${widget.activityId}') as Map<String, dynamic>;
      _report = data;
      _selectedTiming = null;
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _statCard(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.brandOrange)),
            ],
          ),
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))]),
      );

  Widget _batchCard(Map<String, dynamic> batch) {
    final students = (batch['students'] as List).cast<Map<String, dynamic>>();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${batch['location']} · ${batch['start_time']}-${batch['end_time']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Coach: ${batch['coach_name']} · Days: ${(batch['days_of_week'] as List).join(", ")}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                _statCard('Students', '${batch['student_count']}'),
                _statCard('Attendance', '${batch['attendance_pct']}%'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _statCard('Paid/Unpaid', '${batch['fee_paid_count']}/${batch['fee_unpaid_count']}'),
                _statCard('Revenue', '₹${batch['fee_revenue']}'),
              ],
            ),
            if (students.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...students.map((s) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(s['name'] as String, style: const TextStyle(fontSize: 12))),
                        Chip(
                          label: Text(s['fee_status'] as String, style: const TextStyle(fontSize: 10, color: Colors.white)),
                          backgroundColor: s['fee_status'] == 'PAID' ? AppColors.success : (s['fee_status'] == 'OVERDUE' ? AppColors.danger : AppColors.warning),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return Scaffold(
      appBar: AppBar(title: Text('Report: ${widget.activityName}')),
      body: _loading || r == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      _statCard('Students', '${r['student_count']}'),
                      _statCard('Attendance %', '${r['attendance_pct']}%'),
                      _statCard('Revenue', '₹${r['revenue_collected']}'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          _row('Total Classes', '${r['total_classes']}'),
                          _row('Total Present', '${r['total_present']}'),
                          _row('Total Absent', '${r['total_absent']}'),
                          _row('Fees Paid / Unpaid', '${r['fee_paid_count']} / ${r['fee_unpaid_count']}'),
                        ],
                      ),
                    ),
                  ),
                  if ((r['attendance_graph'] as List).isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Attendance Trend', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 180,
                      child: LineChart(
                        LineChartData(
                          gridData: const FlGridData(drawVerticalLine: false),
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  final points = (r['attendance_graph'] as List);
                                  final idx = value.toInt();
                                  if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
                                  return Padding(padding: const EdgeInsets.only(top: 4), child: Text(points[idx]['label'] as String, style: const TextStyle(fontSize: 9)));
                                },
                              ),
                            ),
                            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, getTitlesWidget: (v, m) => Text('${v.toInt()}%', style: const TextStyle(fontSize: 9)))),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: [
                                for (int i = 0; i < (r['attendance_graph'] as List).length; i++)
                                  FlSpot(i.toDouble(), ((r['attendance_graph'] as List)[i]['value'] as num).toDouble()),
                              ],
                              isCurved: true,
                              color: AppColors.brandOrange,
                              barWidth: 2,
                              dotData: const FlDotData(show: true),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => setState(() => _showTimings = !_showTimings),
                    child: Text(_showTimings ? 'Hide Timings' : 'Timings'),
                  ),
                  if (_showTimings) ...[
                    const SizedBox(height: 12),
                    Builder(builder: (context) {
                      final sessionBreakdown = (r['session_breakdown'] as List?) ?? [];
                      final allBatches = sessionBreakdown.expand((g) => (g['batches'] as List)).cast<Map<String, dynamic>>().toList();
                      final timings = <String>{for (final b in allBatches) b['start_time'] as String}.toList()..sort();
                      if (timings.isEmpty) {
                        return const Text('No batches/timings scheduled for this activity yet.', style: TextStyle(color: AppColors.textMuted));
                      }
                      final active = timings.contains(_selectedTiming) ? _selectedTiming! : timings.first;
                      final batches = allBatches.where((b) => b['start_time'] == active).toList();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            children: timings
                                .map((t) => ChoiceChip(
                                      label: Text(_formatTiming(t)),
                                      selected: t == active,
                                      onSelected: (_) => setState(() => _selectedTiming = t),
                                    ))
                                .toList(),
                          ),
                          const SizedBox(height: 12),
                          ...batches.map(_batchCard),
                        ],
                      );
                    }),
                  ],
                  const SizedBox(height: 16),
                  const Text('Coach Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  if ((r['coach_breakdown'] as List).isEmpty)
                    const Text('No classes recorded for this activity yet.', style: TextStyle(color: AppColors.textMuted))
                  else
                    ...(r['coach_breakdown'] as List).map((c) => Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            title: Text(c['coach_name'] as String),
                            subtitle: Text('${c['total_classes']} classes'),
                            trailing: Text('${c['avg_attendance_pct']}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        )),
                ],
              ),
            ),
    );
  }
}
