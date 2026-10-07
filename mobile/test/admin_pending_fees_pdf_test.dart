import 'package:flutter_test/flutter_test.dart';
import 'package:vimj_attendance/features/admin/admin_pending_fees_pdf.dart';

void main() {
  final month = DateTime(2026, 10);
  final feeRecords = <Map<String, dynamic>>[
    {
      'student_id': 1,
      'student_name': 'Asha Rao',
      'month': 10,
      'year': 2026,
      'balance_amount': '25.50',
      'status': 'OVERDUE',
    },
    {
      'student_id': 2,
      'student_name': 'Ravi Das',
      'month': 10,
      'year': 2026,
      'balance_amount': '50.00',
      'status': 'UNPAID',
    },
    {
      'student_id': 3,
      'student_name': 'Paid Student',
      'month': 10,
      'year': 2026,
      'balance_amount': '15.00',
      'status': 'PAID',
    },
    {
      'student_id': 4,
      'student_name': 'Other Month',
      'month': 9,
      'year': 2026,
      'balance_amount': '100.00',
      'status': 'UNPAID',
    },
  ];
  final students = <Map<String, dynamic>>[
    {
      'id': 1,
      'name': 'Asha Rao',
      'activities': [
        {'name': 'Yoga'},
        {'name': 'Dance'},
      ],
    },
    {
      'id': 2,
      'name': 'Ravi Das',
      'activities': [
        {'name': 'Dance'},
      ],
    },
  ];

  test('counts selected-month students and includes their activities', () {
    final report = AdminPendingFeesPdf.prepareData(
      month: month,
      feeRecords: feeRecords,
      students: students,
    );

    expect(report.studentCount, 2);
    expect(report.totalBalance, 75.5);
    expect(report.rows.map((row) => row.studentName), ['Asha Rao', 'Ravi Das']);
    expect(report.rows.first.activities, 'Yoga, Dance');
    expect(report.rows.last.activities, 'Dance');
  });

  test('creates a readable PDF document for the report data', () async {
    final report = AdminPendingFeesPdf.prepareData(
      month: month,
      feeRecords: feeRecords,
      students: students,
    );

    final bytes =
        await AdminPendingFeesPdf.buildPdf(month: month, report: report);

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
