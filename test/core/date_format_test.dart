import 'package:flutter_test/flutter_test.dart';
import 'package:mellow/core/utils/date_format.dart';

void main() {
  final now = DateTime(2026, 11, 23, 15, 30);

  group('time', () {
    test('pads hours and minutes', () {
      expect(MellowDates.time(DateTime(2026, 11, 23, 9, 5)), '09:05');
      expect(MellowDates.time(DateTime(2026, 11, 23, 21, 45)), '21:45');
    });
  });

  group('relativeShort', () {
    test('today shows the time', () {
      expect(
        MellowDates.relativeShort(DateTime(2026, 11, 23, 8, 0), now: now),
        '08:00',
      );
    });

    test('yesterday is spelled out', () {
      expect(
        MellowDates.relativeShort(DateTime(2026, 11, 22, 23, 59), now: now),
        'вчера',
      );
    });

    test('same year shows day and month', () {
      expect(
        MellowDates.relativeShort(DateTime(2026, 11, 12, 10, 0), now: now),
        '12 ноября',
      );
    });

    test('previous years show a numeric date', () {
      expect(
        MellowDates.relativeShort(DateTime(2025, 3, 4, 10, 0), now: now),
        '04.03.25',
      );
    });

    test('future timestamps within today show the time', () {
      expect(
        MellowDates.relativeShort(DateTime(2026, 11, 23, 23, 55), now: now),
        '23:55',
      );
    });
  });

  group('daySeparator', () {
    test('today and yesterday', () {
      expect(MellowDates.daySeparator(DateTime(2026, 11, 23, 1), now: now), 'Сегодня');
      expect(MellowDates.daySeparator(DateTime(2026, 11, 22, 1), now: now), 'Вчера');
    });

    test('older dates include the year when needed', () {
      expect(MellowDates.daySeparator(DateTime(2026, 5, 1), now: now), '1 мая');
      expect(
        MellowDates.daySeparator(DateTime(2025, 5, 1), now: now),
        '1 мая 2025',
      );
    });
  });

  test('isSameDay ignores time of day', () {
    expect(
      MellowDates.isSameDay(DateTime(2026, 11, 23, 0, 1), DateTime(2026, 11, 23, 23, 59)),
      isTrue,
    );
    expect(
      MellowDates.isSameDay(DateTime(2026, 11, 23, 23, 59), DateTime(2026, 11, 24, 0, 1)),
      isFalse,
    );
  });

  test('weekday is capitalised', () {
    expect(MellowDates.weekday(DateTime(2026, 11, 23)), 'Понедельник');
  });
}
