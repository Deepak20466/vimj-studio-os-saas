import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/api_client.dart';
import '../../core/auth_storage.dart';
import '../../core/models.dart';

class StudentAttendanceTab extends StatefulWidget {
  const StudentAttendanceTab({super.key});

  @override
  State<StudentAttendanceTab> createState() => _StudentAttendanceTabState();
}

class _StudentAttendanceTabState extends State<StudentAttendanceTab> {
  List<StudentAttendanceRecord> _records = [];
  List<AttendanceGraphPoint> _graph = [];
  bool _loading = true;
  String _filter = 'ALL';

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

      final recordsData = await ApiClient.instance.get('/students/$studentId/attendance') as List;
      _records = recordsData.map((e) => StudentAttendanceRecord.fromJson(e as Map<String, dynamic>)).toList();

      final graphData = await ApiClient.instance.get('/reports/attendance-graph/$studentId') as Map<String, dynamic>;
      final points = graphData['points'] as List;
      _graph = points.map((e) => AttendanceGraphPoint.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'PRESENT':
        return Colors.green;
      case 'ABSENT':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filter == 'ALL' ? _records : _records.where((r) => r.status == _filter).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('My Attendance')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_graph.isNotEmpty) ...[
                    Text('Attendance % by month', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 200,
                      child: LineChart(
                        LineChartData(
                          minY: 0,
                          maxY: 100,
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  final i = value.toInt();
                                  if (i < 0 || i >= _graph.length) return const SizedBox.shrink();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(_graph[i].label, style: const TextStyle(fontSize: 9)),
                                  );
                                },
                              ),
                            ),
                            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          gridData: const FlGridData(show: true),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: [
                                for (var i = 0; i < _graph.length; i++) FlSpot(i.toDouble(), _graph[i].value),
                              ],
                              isCurved: true,
                              color: const Color(0xFF0000FF),
                              barWidth: 3,
                              dotData: const FlDotData(show: true),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Row(
                    children: [
                      Text('History', style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      DropdownButton<String>(
                        value: _filter,
                        items: const [
                          DropdownMenuItem(value: 'ALL', child: Text('All')),
                          DropdownMenuItem(value: 'PRESENT', child: Text('Present')),
                          DropdownMenuItem(value: 'ABSENT', child: Text('Absent')),
                          DropdownMenuItem(value: 'LEAVE', child: Text('Leave')),
                        ],
                        onChanged: (v) => setState(() => _filter = v ?? 'ALL'),
                      ),
                    ],
                  ),
                  if (filtered.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('No records found.')))
                  else
                    ...filtered.map(
                      (r) => Card(
                        child: ListTile(
                          title: Text(r.timestamp.split('T').first),
                          subtitle: Text('Class #${r.classId}'),
                          trailing: Chip(
                            label: Text(r.status, style: const TextStyle(color: Colors.white, fontSize: 11)),
                            backgroundColor: _statusColor(r.status),
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
