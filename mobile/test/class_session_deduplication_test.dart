import 'package:flutter_test/flutter_test.dart';
import 'package:vimj_attendance/core/models.dart';

ClassSession _session({
  required int id,
  int activityId = 3,
  int coachId = 7,
  String date = '2026-11-03',
  String startTime = '08:00:00',
  String endTime = '09:00:00',
}) => ClassSession(
  id: id,
  activityId: activityId,
  coachId: coachId,
  date: date,
  startTime: startTime,
  endTime: endTime,
);

void main() {
  test('collapses repeated rows for the same scheduled slot', () {
    final sessions = ClassSession.uniqueScheduleSlots([
      _session(id: 12),
      _session(id: 8, startTime: '08:00'),
      _session(id: 10),
    ]);

    expect(sessions, hasLength(1));
    expect(sessions.single.id, 8);
  });

  test('keeps sessions with different schedule slots separate', () {
    final sessions = ClassSession.uniqueScheduleSlots([
      _session(id: 1),
      _session(id: 2, date: '2026-11-04'),
      _session(id: 3, activityId: 4),
      _session(id: 4, startTime: '09:00:00', endTime: '10:00:00'),
      _session(id: 5, coachId: 9),
    ]);

    expect(sessions.map((session) => session.id), [1, 2, 3, 4, 5]);
  });
}
