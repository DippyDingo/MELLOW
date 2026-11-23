/// Locale-independent, dependency-free date helpers.
///
/// Formats are intentionally simple (day/month names in Russian, since the
/// product ships Russian-first) and are covered by unit tests.
abstract final class MellowDates {
  static const List<String> _monthsRu = <String>[
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];

  static const List<String> _weekdaysRu = <String>[
    'понедельник',
    'вторник',
    'среда',
    'четверг',
    'пятница',
    'суббота',
    'воскресенье',
  ];

  /// `14:05` — used inside bubbles and list rows for today's messages.
  static String time(DateTime value) {
    final local = value.toLocal();
    return '${_two(local.hour)}:${_two(local.minute)}';
  }

  /// Compact label for the conversation list: time today, `вчера`, `12 ноя`,
  /// or `12.11.24` for previous years.
  static String relativeShort(DateTime value, {DateTime? now}) {
    final local = value.toLocal();
    final reference = (now ?? DateTime.now()).toLocal();
    final dayDifference = _dayStart(reference).difference(_dayStart(local)).inDays;

    if (dayDifference <= 0) return time(local);
    if (dayDifference == 1) return 'вчера';
    if (local.year == reference.year) {
      return '${local.day} ${_monthsRu[local.month - 1]}';
    }
    return '${_two(local.day)}.${_two(local.month)}.${_two(local.year % 100)}';
  }

  /// Day separator inside a thread: `Сегодня`, `Вчера`, `12 ноября 2025`.
  static String daySeparator(DateTime value, {DateTime? now}) {
    final local = value.toLocal();
    final reference = (now ?? DateTime.now()).toLocal();
    final dayDifference = _dayStart(reference).difference(_dayStart(local)).inDays;

    if (dayDifference == 0) return 'Сегодня';
    if (dayDifference == 1) return 'Вчера';
    if (local.year == reference.year) {
      return '${local.day} ${_monthsRu[local.month - 1]}';
    }
    return '${local.day} ${_monthsRu[local.month - 1]} ${local.year}';
  }

  /// Weekday name, capitalised: `Понедельник`.
  static String weekday(DateTime value) {
    final name = _weekdaysRu[value.toLocal().weekday - 1];
    return name[0].toUpperCase() + name.substring(1);
  }

  /// True when both timestamps fall on the same calendar day.
  static bool isSameDay(DateTime a, DateTime b) {
    final left = a.toLocal();
    final right = b.toLocal();
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  static DateTime _dayStart(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _two(int value) => value.toString().padLeft(2, '0');
}
