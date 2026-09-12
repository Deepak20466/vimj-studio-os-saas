import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';

class AdminDashboardTab extends StatefulWidget {
  const AdminDashboardTab({super.key});

  @override
  State<AdminDashboardTab> createState() => _AdminDashboardTabState();
}

class _AdminDashboardTabState extends State<AdminDashboardTab> {
  bool _loading = true;
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _feeGraph;
  List<dynamic> _missing = [];
  List<dynamic> _activityBreakdown = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/dashboard/summary'),
        ApiClient.instance.get('/dashboard/fee-status'),
        ApiClient.instance.get('/attendance/daily-missing'),
        ApiClient.instance.get('/dashboard/activity-attendance'),
      ]);
      _summary = results[0] as Map<String, dynamic>;
      _feeGraph = results[1] as Map<String, dynamic>;
      _missing = results[2] as List<dynamic>;
      _activityBreakdown = (results[3] as Map<String, dynamic>)['points'] as List<dynamic>? ?? [];
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _statCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.4)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.brandOrange)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final s = _summary ?? {};
    final fees = _feeGraph ?? {'paid': 0, 'unpaid': 0, 'overdue': 0};
    final paid = (fees['paid'] as num?)?.toDouble() ?? 0;
    final unpaid = (fees['unpaid'] as num?)?.toDouble() ?? 0;
    final overdue = (fees['overdue'] as num?)?.toDouble() ?? 0;
    final total = paid + unpaid + overdue;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: [
              _statCard('Students', '${s['total_students'] ?? 0}'),
              _statCard('Coaches', '${s['total_coaches'] ?? 0}'),
              _statCard('Classes this month', '${s['total_classes_this_month'] ?? 0}'),
              _statCard('Monthly revenue', '₹${s['monthly_revenue'] ?? 0}'),
              _statCard('Unpaid/overdue fees', '${s['unpaid_fees_count'] ?? 0}'),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Fee Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                if (total == 0)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('No fee data yet.')))
                else
                  SizedBox(
                    height: 180,
                    child: PieChart(
                      PieChartData(
                        sections: [
                          if (paid > 0) PieChartSectionData(value: paid, color: AppColors.success, title: 'Paid\n${paid.toInt()}', radius: 70, titleStyle: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                          if (unpaid > 0) PieChartSectionData(value: unpaid, color: AppColors.warning, title: 'Unpaid\n${unpaid.toInt()}', radius: 70, titleStyle: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                          if (overdue > 0) PieChartSectionData(value: overdue, color: AppColors.danger, title: 'Overdue\n${overdue.toInt()}', radius: 70, titleStyle: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                        sectionsSpace: 2,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Activity Attendance %', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                if (_activityBreakdown.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('No activity data for this period.')))
                else
                  SizedBox(
                    height: 180,
                    child: BarChart(
                      BarChartData(
                        barGroups: [
                          for (int i = 0; i < _activityBreakdown.length; i++)
                            BarChartGroupData(x: i, barRods: [
                              BarChartRodData(toY: (_activityBreakdown[i]['avg_attendance_pct'] as num).toDouble(), color: AppColors.brandOrange, width: 18, borderRadius: BorderRadius.circular(4)),
                            ]),
                        ],
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final idx = value.toInt();
                                if (idx < 0 || idx >= _activityBreakdown.length) return const SizedBox.shrink();
                                final name = _activityBreakdown[idx]['activity_name'] as String;
                                return Padding(padding: const EdgeInsets.only(top: 4), child: Text(name.length > 8 ? '${name.substring(0, 8)}…' : name, style: const TextStyle(fontSize: 9)));
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, getTitlesWidget: (v, m) => Text('${v.toInt()}%', style: const TextStyle(fontSize: 9)))),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        gridData: const FlGridData(drawVerticalLine: false),
                        borderData: FlBorderData(show: false),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Coaches Missing Attendance Today', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                if (_missing.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('All coaches have marked attendance for ended classes today.'))
                else
                  ..._missing.map((m) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(m['coach_name'] ?? '-'),
                        subtitle: Text('${m['activity_name'] ?? '-'} · ${m['date'] ?? ''} · ends ${m['end_time'] ?? ''}'),
                        leading: const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
