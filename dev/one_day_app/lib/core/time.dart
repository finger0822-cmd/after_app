import 'package:timezone/timezone.dart' as tz;

class TimeUtils {
  static DateTime now() {
    return DateTime.now();
  }

  static DateTime today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime toDateOnly(DateTime dateTime) {
    return DateTime(dateTime.year, dateTime.month, dateTime.day);
  }

  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static DateTime addDays(DateTime date, int days) {
    return date.add(Duration(days: days));
  }

  static tz.TZDateTime toTZDateTime(DateTime dateTime, tz.Location location) {
    return tz.TZDateTime.from(dateTime, location);
  }
}

