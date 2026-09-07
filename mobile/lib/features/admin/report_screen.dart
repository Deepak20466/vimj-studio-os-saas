import 'package:flutter/material.dart';
import '../../core/api_client.dart';
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
        final data = await ApiClient.instance.get('/reports/coach/${widget.id}') as Map<String, dynamic>;
        _coachReport = CoachReport.fromJson(data);
      } else {
        final data = await ApiClient.instance.get('/reports/student/${widget.id}') as Map<String, dynamic>;
        _studentReport = StudentReport.fromJson(data);
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
