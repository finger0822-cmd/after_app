import 'package:intl/intl.dart';

class FormatUtils {
  static String formatDate(DateTime date) {
    return DateFormat('yyyy/MM/dd').format(date);
  }

  static String formatDateForNotification(DateTime date) {
    return DateFormat('yyyy年MM月dd日', 'ja_JP').format(date);
  }
}

