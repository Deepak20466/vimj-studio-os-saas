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

  RosterStudent({required this.id, required this.name, required this.email});

  factory RosterStudent.fromJson(Map<String, dynamic> json) => RosterStudent(
        id: json['id'] as int,
        name: json['name'] as String,
        email: json['email'] as String,
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

class AttendanceGraphPoint {
  final String label;
  final double value;

  AttendanceGraphPoint({required this.label, required this.value});

  factory AttendanceGraphPoint.fromJson(Map<String, dynamic> json) => AttendanceGraphPoint(
        label: json['label'] as String,
        value: (json['value'] as num).toDouble(),
      );
}
