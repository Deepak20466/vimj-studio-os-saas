import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/api_client.dart';
import '../../core/export_helper.dart';

class AdminPendingFeesPdf {
  static Future<void> exportForMonth(DateTime month) async {
    final results = await Future.wait([
      ApiClient.instance.get('/fees', query: {
        'month': month.month,
        'year': month.year,
      }),
      ApiClient.instance.get('/students'),
    ]);

    final report = prepareData(
      month: month,
      feeRecords: (results[0] as List).cast<Map<String, dynamic>>(),
      students: (results[1] as List).cast<Map<String, dynamic>>(),
    );
    final pdfBytes = await buildPdf(month: month, report: report);
    await shareExportedFile(
      pdfBytes,
      'fees_pending_${month.year}_${month.month.toString().padLeft(2, '0')}.pdf',
    );
  }

  @visibleForTesting
  static AdminPendingFeesReportData prepareData({
    required DateTime month,
    required List<Map<String, dynamic>> feeRecords,
    required List<Map<String, dynamic>> students,
  }) {
    final studentsById = <int, Map<String, dynamic>>{
      for (final student in students) (student['id'] as num).toInt(): student,
    };
    final rows = <AdminPendingFeeRow>[];
    for (final fee in feeRecords) {
      if ((fee['month'] as num?)?.toInt() != month.month ||
          (fee['year'] as num?)?.toInt() != month.year) {
        continue;
      }
      final balance = double.tryParse(
            (fee['balance_amount'] ?? fee['amount'] ?? 0).toString(),
          ) ??
          0;
      final status = fee['status']?.toString() ?? 'PENDING';
      if (balance <= 0 || status.toUpperCase() == 'PAID') continue;

      final studentId = (fee['student_id'] as num).toInt();
      final student = studentsById[studentId];
      final activityNames = ((student?['activities'] as List?) ?? const [])
          .whereType<Map>()
          .map((activity) => activity['name']?.toString() ?? '')
          .where((name) => name.trim().isNotEmpty)
          .toList();
      rows.add(AdminPendingFeeRow(
        studentId: studentId,
        studentName: fee['student_name']?.toString() ??
            student?['name']?.toString() ??
            'Student #$studentId',
        activities: activityNames.isEmpty
            ? 'No activity assigned'
            : activityNames.join(', '),
        balance: balance,
        status: status,
      ));
    }

    rows.sort((a, b) {
      final nameOrder = a.studentName.toLowerCase().compareTo(
            b.studentName.toLowerCase(),
          );
      return nameOrder != 0 ? nameOrder : a.studentId.compareTo(b.studentId);
    });

    return AdminPendingFeesReportData(
      rows: rows,
      studentCount: rows.map((row) => row.studentId).toSet().length,
      totalBalance: rows.fold<double>(0, (sum, row) => sum + row.balance),
    );
  }

  @visibleForTesting
  static Future<List<int>> buildPdf({
    required DateTime month,
    required AdminPendingFeesReportData report,
  }) async {
    final rows = report.rows;
    final studentCount = report.studentCount;
    final totalBalance = report.totalBalance;
    final money = NumberFormat('#,##0.00');
    final period = DateFormat('MMMM yyyy').format(month);
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Text(
            'Pending Fees Report',
            style: const pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text('Billing month: $period'),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: const pw.BoxDecoration(color: PdfColors.orange100),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Students with pending balance: $studentCount'),
                pw.Text(
                    'Total balance pending: Rs ${money.format(totalBalance)}'),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          if (rows.isEmpty)
            pw.Text('No students have a pending fee balance for this month.')
          else
            pw.TableHelper.fromTextArray(
              headers: const [
                'No.',
                'Student',
                'Activity / Activities',
                'Balance Pending (Rs)',
                'Status',
              ],
              data: [
                for (var index = 0; index < rows.length; index++)
                  [
                    '${index + 1}',
                    rows[index].studentName,
                    rows[index].activities,
                    money.format(rows[index].balance),
                    rows[index].status,
                  ],
              ],
              headerStyle: const pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.deepOrange),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 6,
              ),
              cellAlignments: {
                0: pw.Alignment.center,
                3: pw.Alignment.centerRight,
              },
              columnWidths: {
                0: const pw.FixedColumnWidth(36),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(3),
                3: const pw.FlexColumnWidth(1.5),
                4: const pw.FlexColumnWidth(1.2),
              },
              border: pw.TableBorder.all(
                color: PdfColors.grey400,
                width: 0.5,
              ),
              oddRowDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey100),
            ),
        ],
      ),
    );
    return document.save();
  }
}

class AdminPendingFeesReportData {
  final List<AdminPendingFeeRow> rows;
  final int studentCount;
  final double totalBalance;

  const AdminPendingFeesReportData({
    required this.rows,
    required this.studentCount,
    required this.totalBalance,
  });
}

class AdminPendingFeeRow {
  final int studentId;
  final String studentName;
  final String activities;
  final double balance;
  final String status;

  const AdminPendingFeeRow({
    required this.studentId,
    required this.studentName,
    required this.activities,
    required this.balance,
    required this.status,
  });
}
