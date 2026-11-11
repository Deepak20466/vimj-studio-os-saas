import 'package:flutter_test/flutter_test.dart';
import 'package:vimj_attendance/core/models.dart';

Batch _batch({
  List<String> days = const ['WED'],
  List<int> months = const [11],
  bool active = true,
}) =>
    Batch(
      id: 1,
      activityId: 1,
      coachId: 7,
      location: 'Studio',
      sessionPeriod: 'EVENING',
      startTime: '18:00:00',
      endTime: '19:00:00',
      daysOfWeek: days,
      activeMonths: months,
      isActive: active,
    );

void main() {
  group('assigned coach schedules', () {
    test('matches the assigned weekday and active month', () {
      expect(_batch().isScheduledOn(DateTime(2026, 11, 11)), isTrue);
    });

    test('excludes other weekdays, inactive months, and inactive batches', () {
      expect(_batch().isScheduledOn(DateTime(2026, 11, 12)), isFalse);
      expect(_batch().isScheduledOn(DateTime(2026, 12, 9)), isFalse);
      expect(
        _batch(active: false).isScheduledOn(DateTime(2026, 11, 11)),
        isFalse,
      );
    });
  });
}
