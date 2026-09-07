import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';

const _monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

class AdminReportsTab extends StatefulWidget {
  const AdminReportsTab({super.key});

  @override
  State<AdminReportsTab> createState() => _AdminReportsTabState();
}

class _AdminReportsTabState extends State<AdminReportsTab> {
  bool _loading = true;
  Map<String, dynamic>? _analysis;
  List<dynamic> _hundredPct = [];
  late int _month = DateTime.now().month;
  late int _year = DateTime.now().year;
  late final _yearCtrl = TextEditingController(text: _year.toString());

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _yearCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/reports/monthly-analysis', query: {'month': _month, 'year': _year}),
        ApiClient.instance.get('/reports/100-percent-coaches/$_month', query: {'year': _year}),
      ]);
      _analysis = results[0] as Map<String, dynamic>;
      _hundredPct = results[1] as List;
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _statCard(String label, String value, {String? delta, bool? deltaGood}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.4)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.brandOrange)),
          if (delta != null)
            Text(delta, style: TextStyle(fontSize: 11, color: (deltaGood ?? true) ? AppColors.success : AppColors.danger)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = _analysis;
    final breakdown = (a?['activity_breakdown'] as List?) ?? [];
    final revenueDelta = a != null ? (a['monthly_revenue'] as num) - (a['prev_month_revenue'] as num) : 0;
    final attendanceDelta = a != null ? (a['attendance_rate'] as num) - (a['prev_month_attendance_rate'] as num) : 0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _month,
                  decoration: const InputDecoration(labelText: 'Month'),
                  items: List.generate(12, (i) => i + 1).map((m) => DropdownMenuItem(value: m, child: Text(_monthNames[m]))).toList(),
                  onChanged: (v) {
                    setState(() => _month = v ?? _month);
                    _load();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Year'),
                  keyboardType: TextInputType.number,
                  controller: _yearCtrl,
                  onSubmitted: (v) {
                    _year = int.tryParse(v) ?? _year;
                    _load();
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading || a == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    children: [
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.5,
                        children: [
                          _statCard('Students', '${a['total_students']}'),
                          _statCard('Coaches', '${a['total_coaches']}'),
                          _statCard('Classes', '${a['total_classes']}'),
                          _statCard(
                            'Attendance Rate',
                            '${a['attendance_rate']}%',
                            delta: '${attendanceDelta >= 0 ? '▲' : '▼'} ${attendanceDelta.abs().toStringAsFixed(1)}pp',
                            deltaGood: attendanceDelta >= 0,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _statCard(
                        'Monthly Revenue',
                        '₹${a['monthly_revenue']}',
                        delta: '${revenueDelta >= 0 ? '▲' : '▼'} ₹${revenueDelta.abs()}',
                        deltaGood: revenueDelta >= 0,
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Activity Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 12),
                            if (breakdown.isEmpty)
                              const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('No activity data for this period.'))
                            else ...[
                              SizedBox(
                                height: 180,
                                child: BarChart(
                                  BarChartData(
                                    barGroups: [
                                      for (int i = 0; i < breakdown.length; i++)
                                        BarChartGroupData(x: i, barRods: [
                                          BarChartRodData(toY: (breakdown[i]['avg_attendance_pct'] as num).toDouble(), color: AppColors.brandOrange, width: 18, borderRadius: BorderRadius.circular(4)),
                                        ]),
                                    ],
                                    titlesData: FlTitlesData(
                                      bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          getTitlesWidget: (value, meta) {
                                            final idx = value.toInt();
                                            if (idx < 0 || idx >= breakdown.length) return const SizedBox.shrink();
                                            final name = breakdown[idx]['activity_name'] as String;
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
                              const SizedBox(height: 12),
                              ...breakdown.map((row) => Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(row['activity_name'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        Text(
                                          '${row['student_count']} students · ${row['total_classes']} classes · ${row['avg_attendance_pct']}% attendance',
                                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                        ),
                                        Text(
                                          'Revenue ₹${row['revenue']} · Collected ₹${row['revenue_collected']}',
                                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                        ),
                                      ],
                                    ),
                                  )),
                            ],
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
                            const Text('Coaches with 100% Student Attendance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 8),
                            if (_hundredPct.isEmpty)
                              const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No coach hit 100% attendance this period.'))
                            else
                              ..._hundredPct.map((c) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.emoji_events, color: AppColors.success),
                                    title: Text(c['coach_name'] as String),
                                    trailing: Text('${c['attendance_pct']}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  )),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
