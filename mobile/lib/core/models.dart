class ChatThreadSummary {
  final int coachId;
  final String coachName;
  final int unreadCount;
  final String? lastMessage;
  final String? lastMessageAt;

  ChatThreadSummary({
    required this.coachId,
    required this.coachName,
    required this.unreadCount,
    this.lastMessage,
    this.lastMessageAt,
  });

  factory ChatThreadSummary.fromJson(Map<String, dynamic> json) => ChatThreadSummary(
        coachId: json['coach_id'] as int,
        coachName: json['coach_name'] as String,
        unreadCount: json['unread_count'] as int? ?? 0,
        lastMessage: json['last_message'] as String?,
        lastMessageAt: json['last_message_at'] as String?,
      );
}

class ChatMessage {
  final int id;
  final int senderId;
  final String senderName;
  final String message;
  final String createdAt;

  ChatMessage({required this.id, required this.senderId, required this.senderName, required this.message, required this.createdAt});

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as int,
        senderId: json['sender_id'] as int,
        senderName: json['sender_name'] as String,
        message: json['message'] as String,
        createdAt: json['created_at'] as String,
      );
}

class ClassSession {
  final int id;
  final int activityId;
  final int coachId;
  final String date;
  final String startTime;
  final String endTime;

  ClassSession({
    required this.id,
    required this.activityId,
    required this.coachId,
    required this.date,
    required this.startTime,
    required this.endTime,
  });

  factory ClassSession.fromJson(Map<String, dynamic> json) => ClassSession(
        id: json['id'] as int,
        activityId: json['activity_id'] as int,
        coachId: json['coach_id'] as int,
        date: json['date'] as String,
        startTime: json['start_time'] as String,
        endTime: json['end_time'] as String,
      );
}

class RosterStudent {
  final int id;
  final String name;
  final String email;
  final int? enrollmentId;
  final String? feeStatus;

  RosterStudent({required this.id, required this.name, required this.email, this.enrollmentId, this.feeStatus});

  factory RosterStudent.fromJson(Map<String, dynamic> json) => RosterStudent(
        id: json['id'] as int,
        name: json['name'] as String,
        email: json['email'] as String,
        enrollmentId: json['enrollment_id'] as int?,
        feeStatus: json['fee_status'] as String?,
      );
}

class LeaveRequest {
  final int id;
  final String startDate;
  final String endDate;
  final String reason;
  final String status;
  final String? decisionNote;

  LeaveRequest({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.status,
    this.decisionNote,
  });

  factory LeaveRequest.fromJson(Map<String, dynamic> json) => LeaveRequest(
        id: json['id'] as int,
        startDate: json['start_date'] as String,
        endDate: json['end_date'] as String,
        reason: json['reason'] as String,
        status: json['status'] as String,
        decisionNote: json['decision_note'] as String?,
      );
}

class SwapRequest {
  final int id;
  final int originalCoachId;
  final int coveringCoachId;
  final int classId;
  final String date;
  final String status;

  SwapRequest({
    required this.id,
    required this.originalCoachId,
    required this.coveringCoachId,
    required this.classId,
    required this.date,
    required this.status,
  });

  factory SwapRequest.fromJson(Map<String, dynamic> json) => SwapRequest(
        id: json['id'] as int,
        originalCoachId: json['original_coach_id'] as int,
        coveringCoachId: json['covering_coach_id'] as int,
        classId: json['class_id'] as int,
        date: json['date'] as String,
        status: json['status'] as String,
      );
}

class SalaryRecord {
  final int id;
  final int month;
  final int year;
  final String amount;
  final String? acknowledgedDate;

  SalaryRecord({
    required this.id,
    required this.month,
    required this.year,
    required this.amount,
    this.acknowledgedDate,
  });

  factory SalaryRecord.fromJson(Map<String, dynamic> json) => SalaryRecord(
        id: json['id'] as int,
        month: json['month'] as int,
        year: json['year'] as int,
        amount: json['amount'].toString(),
        acknowledgedDate: json['acknowledged_date'] as String?,
      );
}

class FeeRecord {
  final int id;
  final int month;
  final int year;
  final String amount;
  final String status;
  final String dueDate;
  final String? paidDate;

  FeeRecord({
    required this.id,
    required this.month,
    required this.year,
    required this.amount,
    required this.status,
    required this.dueDate,
    this.paidDate,
  });

  factory FeeRecord.fromJson(Map<String, dynamic> json) => FeeRecord(
        id: json['id'] as int,
        month: json['month'] as int,
        year: json['year'] as int,
        amount: json['amount'].toString(),
        status: json['status'] as String,
        dueDate: json['due_date'] as String,
        paidDate: json['paid_date'] as String?,
      );
}

class StudentAttendanceRecord {
  final int id;
  final int classId;
  final String status;
  final String timestamp;

  StudentAttendanceRecord({
    required this.id,
    required this.classId,
    required this.status,
    required this.timestamp,
  });

  factory StudentAttendanceRecord.fromJson(Map<String, dynamic> json) => StudentAttendanceRecord(
        id: json['id'] as int,
        classId: json['class_id'] as int,
        status: json['status'] as String,
        timestamp: json['timestamp'] as String,
      );
}

class Student {
  final int id;
  final String name;
  final String email;
  final String? phone;
  final String? phoneSecondary;
  final bool isActive;

  Student({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.phoneSecondary,
    required this.isActive,
  });

  factory Student.fromJson(Map<String, dynamic> json) => Student(
        id: json['id'] as int,
        name: json['name'] as String,
        email: json['email'] as String,
        phone: json['phone'] as String?,
        phoneSecondary: json['phone_secondary'] as String?,
        isActive: json['is_active'] as bool? ?? true,
      );
}

class Coach {
  final int id;
  final String name;
  final String email;
  final String? phone;
  final bool isActive;

  Coach({required this.id, required this.name, required this.email, this.phone, required this.isActive});

  factory Coach.fromJson(Map<String, dynamic> json) => Coach(
        id: json['id'] as int,
        name: json['name'] as String,
        email: json['email'] as String,
        phone: json['phone'] as String?,
        isActive: json['is_active'] as bool? ?? true,
      );
}

class Activity {
  final int id;
  final String name;
  final int capacity;
  final String monthlyFee;

  Activity({required this.id, required this.name, required this.capacity, required this.monthlyFee});

  factory Activity.fromJson(Map<String, dynamic> json) => Activity(
        id: json['id'] as int,
        name: json['name'] as String,
        capacity: json['capacity'] as int,
        monthlyFee: json['monthly_fee'].toString(),
      );
}

class DailyMissingRow {
  final int coachId;
  final int classId;
  final String coachName;
  final String activityName;
  final String date;
  final String endTime;

  DailyMissingRow({
    required this.coachId,
    required this.classId,
    required this.coachName,
    required this.activityName,
    required this.date,
    required this.endTime,
  });

  factory DailyMissingRow.fromJson(Map<String, dynamic> json) => DailyMissingRow(
        coachId: json['coach_id'] as int,
        classId: json['class_id'] as int,
        coachName: json['coach_name'] as String? ?? '-',
        activityName: json['activity_name'] as String? ?? '-',
        date: json['date'] as String,
        endTime: json['end_time'] as String,
      );
}

class AdminAttendanceRecord {
  final int id;
  final int studentId;
  final String studentName;
  final int classId;
  final int activityId;
  final String activityName;
  final int? coachId;
  final String? coachName;
  final String status;
  final String classDate;
  final String timestamp;
  final bool markedManually;

  AdminAttendanceRecord({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.classId,
    required this.activityId,
    required this.activityName,
    this.coachId,
    this.coachName,
    required this.status,
    required this.classDate,
    required this.timestamp,
    required this.markedManually,
  });

  factory AdminAttendanceRecord.fromJson(Map<String, dynamic> json) => AdminAttendanceRecord(
        id: json['id'] as int,
        studentId: json['student_id'] as int,
        studentName: json['student_name'] as String,
        classId: json['class_id'] as int,
        activityId: json['activity_id'] as int,
        activityName: json['activity_name'] as String,
        coachId: json['coach_id'] as int?,
        coachName: json['coach_name'] as String?,
        status: json['status'] as String,
        classDate: json['class_date'] as String,
        timestamp: json['timestamp'] as String,
        markedManually: json['marked_manually'] as bool? ?? false,
      );
}

class AdminLeaveRequest {
  final int id;
  final int coachId;
  final String? coachName;
  final String startDate;
  final String endDate;
  final String reason;
  final String status;

  AdminLeaveRequest({
    required this.id,
    required this.coachId,
    this.coachName,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.status,
  });

  factory AdminLeaveRequest.fromJson(Map<String, dynamic> json) => AdminLeaveRequest(
        id: json['id'] as int,
        coachId: json['coach_id'] as int,
        coachName: json['coach_name'] as String?,
        startDate: json['start_date'] as String,
        endDate: json['end_date'] as String,
        reason: json['reason'] as String,
        status: json['status'] as String,
      );
}

class AdminFeeRecord {
  final int id;
  final int studentId;
  final String? studentName;
  final int month;
  final int year;
  final String amount;
  final String balanceAmount;
  final String status;
  final String dueDate;

  AdminFeeRecord({
    required this.id,
    required this.studentId,
    this.studentName,
    required this.month,
    required this.year,
    required this.amount,
    required this.balanceAmount,
    required this.status,
    required this.dueDate,
  });

  factory AdminFeeRecord.fromJson(Map<String, dynamic> json) => AdminFeeRecord(
        id: json['id'] as int,
        studentId: json['student_id'] as int,
        studentName: json['student_name'] as String?,
        month: json['month'] as int,
        year: json['year'] as int,
        amount: json['amount'].toString(),
        balanceAmount: (json['balance_amount'] ?? json['amount']).toString(),
        status: json['status'] as String,
        dueDate: json['due_date'] as String,
      );
}

class AdminSalaryRecord {
  final int id;
  final int coachId;
  final String? coachName;
  final int month;
  final int year;
  final String amount;
  final String? acknowledgedDate;

  AdminSalaryRecord({
    required this.id,
    required this.coachId,
    this.coachName,
    required this.month,
    required this.year,
    required this.amount,
    this.acknowledgedDate,
  });

  factory AdminSalaryRecord.fromJson(Map<String, dynamic> json) => AdminSalaryRecord(
        id: json['id'] as int,
        coachId: json['coach_id'] as int,
        coachName: json['coach_name'] as String?,
        month: json['month'] as int,
        year: json['year'] as int,
        amount: json['amount'].toString(),
        acknowledgedDate: json['acknowledged_date'] as String?,
      );
}

class Batch {
  final int id;
  final int activityId;
  final int? coachId;
  final String location;
  final String sessionPeriod;
  final String startTime;
  final String endTime;
  final List<String> daysOfWeek;
  final List<int> activeMonths;
  final bool isActive;

  Batch({
    required this.id,
    required this.activityId,
    this.coachId,
    required this.location,
    required this.sessionPeriod,
    required this.startTime,
    required this.endTime,
    required this.daysOfWeek,
    required this.activeMonths,
    required this.isActive,
  });

  factory Batch.fromJson(Map<String, dynamic> json) => Batch(
        id: json['id'] as int,
        activityId: json['activity_id'] as int,
        coachId: json['coach_id'] as int?,
        location: json['location'] as String,
        sessionPeriod: json['session_period'] as String,
        startTime: json['start_time'] as String,
        endTime: json['end_time'] as String,
        daysOfWeek: (json['days_of_week'] as List).map((e) => e as String).toList(),
        activeMonths: (json['active_months'] as List).map((e) => e as int).toList(),
        isActive: json['is_active'] as bool? ?? true,
      );
}

class RecentSwap {
  final int id;
  final String date;
  final String activityName;
  final String originalCoachName;
  final String coveringCoachName;
  final String status;
  final String? reason;

  RecentSwap({
    required this.id,
    required this.date,
    required this.activityName,
    required this.originalCoachName,
    required this.coveringCoachName,
    required this.status,
    this.reason,
  });

  factory RecentSwap.fromJson(Map<String, dynamic> json) => RecentSwap(
        id: json['id'] as int,
        date: json['date'] as String,
        activityName: json['activity_name'] as String,
        originalCoachName: json['original_coach_name'] as String,
        coveringCoachName: json['covering_coach_name'] as String,
        status: json['status'] as String,
        reason: json['reason'] as String?,
      );
}

class ComplianceRow {
  final int classId;
  final String activityName;
  final int coachId;
  final String coachName;
  final String classDate;
  final String endTime;
  final String state;
  final String? skipReason;
  final String? lateReason;

  ComplianceRow({
    required this.classId,
    required this.activityName,
    required this.coachId,
    required this.coachName,
    required this.classDate,
    required this.endTime,
    required this.state,
    this.skipReason,
    this.lateReason,
  });

  factory ComplianceRow.fromJson(Map<String, dynamic> json) => ComplianceRow(
        classId: json['class_id'] as int,
        activityName: json['activity_name'] as String,
        coachId: json['coach_id'] as int,
        coachName: json['coach_name'] as String,
        classDate: json['class_date'] as String,
        endTime: json['end_time'] as String,
        state: json['state'] as String,
        skipReason: json['skip_reason'] as String?,
        lateReason: json['late_reason'] as String?,
      );
}

class ComplianceSummary {
  final int submitted;
  final int pending;
  final int delayed;
  final int notConducted;
  final int lateApproved;
  final int lateRejected;
  final List<ComplianceRow> rows;

  ComplianceSummary({
    required this.submitted,
    required this.pending,
    required this.delayed,
    required this.notConducted,
    required this.lateApproved,
    required this.lateRejected,
    required this.rows,
  });

  factory ComplianceSummary.fromJson(Map<String, dynamic> json) => ComplianceSummary(
        submitted: json['submitted'] as int,
        pending: json['pending'] as int,
        delayed: json['delayed'] as int,
        notConducted: json['not_conducted'] as int,
        lateApproved: json['late_approved'] as int,
        lateRejected: json['late_rejected'] as int,
        rows: (json['rows'] as List).map((e) => ComplianceRow.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class PendingLateSubmission {
  final int id;
  final int classId;
  final String coachName;
  final String activityName;
  final String classDate;
  final String? lateReason;

  PendingLateSubmission({
    required this.id,
    required this.classId,
    required this.coachName,
    required this.activityName,
    required this.classDate,
    this.lateReason,
  });

  factory PendingLateSubmission.fromJson(Map<String, dynamic> json) => PendingLateSubmission(
        id: json['id'] as int,
        classId: json['class_id'] as int,
        coachName: json['coach_name'] as String,
        activityName: json['activity_name'] as String,
        classDate: json['class_date'] as String,
        lateReason: json['late_reason'] as String?,
      );
}

class ClassPhoto {
  final int id;
  final int classId;

  ClassPhoto({required this.id, required this.classId});

  factory ClassPhoto.fromJson(Map<String, dynamic> json) => ClassPhoto(
        id: json['id'] as int,
        classId: json['class_id'] as int,
      );
}

class AcademySettings {
  final int id;
  final String name;
  final String? address;
  final String? phone;
  final String? email;
  final String? description;

  AcademySettings({required this.id, required this.name, this.address, this.phone, this.email, this.description});

  factory AcademySettings.fromJson(Map<String, dynamic> json) => AcademySettings(
        id: json['id'] as int,
        name: json['name'] as String,
        address: json['address'] as String?,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        description: json['description'] as String?,
      );
}

class FeeReceiptRecord {
  final int id;
  final int studentId;
  final String? studentName;
  final String amount;
  final int month;
  final int year;
  final String paymentMode;
  final String status;
  final String? decisionNote;

  FeeReceiptRecord({
    required this.id,
    required this.studentId,
    this.studentName,
    required this.amount,
    required this.month,
    required this.year,
    required this.paymentMode,
    required this.status,
    this.decisionNote,
  });

  factory FeeReceiptRecord.fromJson(Map<String, dynamic> json) => FeeReceiptRecord(
        id: json['id'] as int,
        studentId: json['student_id'] as int,
        studentName: json['student_name'] as String?,
        amount: json['amount'].toString(),
        month: json['month'] as int,
        year: json['year'] as int,
        paymentMode: json['payment_mode'] as String,
        status: json['status'] as String,
        decisionNote: json['decision_note'] as String?,
      );
}

class FeeReminderDraftRecord {
  final int id;
  final int studentId;
  final String? studentName;
  final int month;
  final int year;
  final String message;
  final String status;
  final String? decisionNote;

  FeeReminderDraftRecord({
    required this.id,
    required this.studentId,
    this.studentName,
    required this.month,
    required this.year,
    required this.message,
    required this.status,
    this.decisionNote,
  });

  factory FeeReminderDraftRecord.fromJson(Map<String, dynamic> json) => FeeReminderDraftRecord(
        id: json['id'] as int,
        studentId: json['student_id'] as int,
        studentName: json['student_name'] as String?,
        month: json['month'] as int,
        year: json['year'] as int,
        message: json['message'] as String,
        status: json['status'] as String,
        decisionNote: json['decision_note'] as String?,
      );
}

class CoachActivityLink {
  final int activityId;
  final String activityName;

  CoachActivityLink({required this.activityId, required this.activityName});

  factory CoachActivityLink.fromJson(Map<String, dynamic> json) => CoachActivityLink(
        activityId: json['activity_id'] as int,
        activityName: json['activity_name'] as String,
      );
}

class StudentReport {
  final int totalClasses;
  final int present;
  final int absent;
  final int leave;
  final double attendancePct;
  final int feesPaid;
  final int feesUnpaid;
  final double outstandingBalance;

  StudentReport({
    required this.totalClasses,
    required this.present,
    required this.absent,
    required this.leave,
    required this.attendancePct,
    required this.feesPaid,
    required this.feesUnpaid,
    required this.outstandingBalance,
  });

  factory StudentReport.fromJson(Map<String, dynamic> json) => StudentReport(
        totalClasses: json['total_classes'] as int,
        present: json['present'] as int,
        absent: json['absent'] as int,
        leave: json['leave'] as int,
        attendancePct: (json['attendance_pct'] as num).toDouble(),
        feesPaid: json['fees_paid'] as int,
        feesUnpaid: json['fees_unpaid'] as int,
        outstandingBalance: (json['outstanding_balance'] as num).toDouble(),
      );
}

class CoachReport {
  final int totalClasses;
  final int daysPresent;
  final int daysAbsent;
  final int leavesTaken;
  final double studentAttendancePct;

  CoachReport({
    required this.totalClasses,
    required this.daysPresent,
    required this.daysAbsent,
    required this.leavesTaken,
    required this.studentAttendancePct,
  });

  factory CoachReport.fromJson(Map<String, dynamic> json) => CoachReport(
        totalClasses: json['total_classes'] as int,
        daysPresent: json['days_present'] as int,
        daysAbsent: json['days_absent'] as int,
        leavesTaken: json['leaves_taken'] as int,
        studentAttendancePct: (json['student_attendance_pct'] as num).toDouble(),
      );
}

class AttendanceGraphPoint {
  final String label;
  final double value;

  AttendanceGraphPoint({required this.label, required this.value});

  factory AttendanceGraphPoint.fromJson(Map<String, dynamic> json) => AttendanceGraphPoint(
        label: json['label'] as String,
        value: (json['value'] as num).toDouble(),
      );
}
