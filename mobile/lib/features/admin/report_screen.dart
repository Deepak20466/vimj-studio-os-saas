import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/export_helper.dart';
import '../../core/models.dart';

class ReportScreen extends StatefulWidget {
  final bool isCoach;
  final int id;
  final String name;
  const ReportScreen({super.key, required this.isCoach, required this.id, required this.name});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  StudentReport? _studentReport;
  CoachReport? _coachReport;
  List<AttendanceGraphPoint> _attendanceGraph = [];
  List<AdminSalaryRecord> _salaryHistory = [];
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (widget.isCoach) {
        final results = await Future.wait([
          ApiClient.instance.get('/reports/coach/${widget.id}'),
          ApiClient.instance.get('/coaches/${widget.id}/salary'),
        ]);
        _coachReport = CoachReport.fromJson(results[0] as Map<String, dynamic>);
        _salaryHistory = (results[1] as List).map((e) => AdminSalaryRecord.fromJson(e as Map<String, dynamic>)).toList();
      } else {
        final results = await Future.wait([
          ApiClient.instance.get('/reports/student/${widget.id}'),
          ApiClient.instance.get('/reports/attendance-graph/${widget.id}'),
        ]);
        _studentReport = StudentReport.fromJson(results[0] as Map<String, dynamic>);
        _attendanceGraph = ((results[1] as Map<String, dynamic>)['points'] as List).map((e) => AttendanceGraphPoint.fromJson(e as Map<String, dynamic>)).toList();
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _export(String fmt) async {
    setState(() => _exporting = true);
    try {
      final path = widget.isCoach ? '/reports/export/coach/${widget.id}' : '/reports/export/student/${widget.id}';
      final bytes = await ApiClient.instance.getBytes(path, query: {'fmt': fmt});
      final kind = widget.isCoach ? 'coach' : 'student';
      await shareExportedFile(bytes, '${kind}_${widget.id}_report.$fmt');
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.name} — Report')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: widget.isCoach
                          ? [
                              _row('Total Classes', '${_coachReport!.totalClasses}'),
                              _row('Days Present', '${_coachReport!.daysPresent}'),
                              _row('Days Absent', '${_coachReport!.daysAbsent}'),
                              _row('Leaves Taken', '${_coachReport!.leavesTaken}'),
                              _row('Student Attendance %', '${_coachReport!.studentAttendancePct.toStringAsFixed(1)}%'),
                            ]
                          : [
                              _row('Attendance %', '${_studentReport!.attendancePct.toStringAsFixed(1)}%'),
                              _row('Total Classes', '${_studentReport!.totalClasses}'),
                              _row('Present', '${_studentReport!.present}'),
                              _row('Absent', '${_studentReport!.absent}'),
                              _row('Leave', '${_studentReport!.leave}'),
                              _row('Fees Paid / Unpaid', '${_studentReport!.feesPaid} / ${_studentReport!.feesUnpaid}'),
                              _row('Outstanding Balance', '₹${_studentReport!.outstandingBalance.toStringAsFixed(2)}'),
                            ],
                    ),
                  ),
                ),
                if (!widget.isCoach && (_studentReport!.feesPaid + _studentReport!.feesUnpaid) > 0) ...[
                  const SizedBox(height: 20),
                  const Text('Fee Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 160,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        sections: [
                          if (_studentReport!.feesPaid > 0)
                            PieChartSectionData(value: _studentReport!.feesPaid.toDouble(), color: AppColors.success, title: 'Paid\n${_studentReport!.feesPaid}', radius: 60, titleStyle: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                          if (_studentReport!.feesUnpaid > 0)
                            PieChartSectionData(value: _studentReport!.feesUnpaid.toDouble(), color: AppColors.warning, title: 'Unpaid\n${_studentReport!.feesUnpaid}', radius: 60, titleStyle: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
                if (!widget.isCoach && _attendanceGraph.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text('Attendance Trend', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                                final idx = value.toInt();
                                if (idx < 0 || idx >= _attendanceGraph.length) return const SizedBox.shrink();
                                return Padding(padding: const EdgeInsets.only(top: 4), child: Text(_attendanceGraph[idx].label, style: const TextStyle(fontSize: 9)));
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
                            spots: [for (int i = 0; i < _attendanceGraph.length; i++) FlSpot(i.toDouble(), _attendanceGraph[i].value)],
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
                if (widget.isCoach) ...[
                  const SizedBox(height: 20),
                  const Text('Salary History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  if (_salaryHistory.isEmpty)
                    const Text('No salary records yet.', style: TextStyle(color: AppColors.textMuted))
                  else
                    ..._salaryHistory.map((s) => Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            title: Text('${s.month}/${s.year}'),
                            subtitle: Text('₹${s.amount}'),
                            trailing: Chip(
                              label: Text(s.acknowledgedDate != null ? 'Acknowledged' : 'Pending', style: const TextStyle(fontSize: 11, color: Colors.white)),
                              backgroundColor: s.acknowledgedDate != null ? AppColors.success : AppColors.warning,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        )),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _exporting ? null : () => _export('csv'),
                        icon: const Icon(Icons.table_chart_outlined),
                        label: const Text('Export CSV'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _exporting ? null : () => _export('pdf'),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Export PDF'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
