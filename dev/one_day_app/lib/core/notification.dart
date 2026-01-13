import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import '../data/message_model.dart' as model;
import 'format.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static final Set<String> _loggedKeys = <String>{};

  /// 同一キーのログを1回だけ出力する
  static void _logOnce(String key, String message) {
    if (_loggedKeys.add(key)) {
      debugPrint(message);
    }
  }

  /// デスクトッププラットフォームかどうかを判定
  static bool get _isDesktopPlatform {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  static Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _initialized = true;
  }

  static void _onNotificationTapped(NotificationResponse response) {
    // アプリを開くだけ（特に処理なし）
  }

  static Future<bool> requestPermissions() async {
    final android = await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    final ios = await _notifications
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
    return android ?? ios ?? false;
  }

  static Future<void> scheduleNotificationForMessage(model.Message message) async {
    if (message.openedAt != null) return;

    // デスクトッププラットフォームでは通知スケジュールをスキップ
    if (_isDesktopPlatform) {
      _logOnce(
        'notificationsScheduleSkippedDesktop',
        '[NotificationService] デスクトッププラットフォームでは通知スケジュールをスキップします',
      );
      return;
    }

    final openOn = message.openOn;
    final notificationTime = tz.TZDateTime(
      tz.local,
      openOn.year,
      openOn.month,
      openOn.day,
      9,
      0,
    );

    if (notificationTime.isBefore(tz.TZDateTime.now(tz.local))) {
      return;
    }

    final notificationId = message.id.toInt();
    final title = '記録があります';
    final body = '${FormatUtils.formatDateForNotification(openOn)}のあなたからの記録があります。';

    const androidDetails = AndroidNotificationDetails(
      'after_channel',
      'After',
              channelDescription: '記録が届いた通知',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.zonedSchedule(
      notificationId,
      title,
      body,
      notificationTime,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancelNotificationForMessage(model.Message message) async {
    if (!_initialized) return;
    final notificationId = message.id.toInt();
    await _notifications.cancel(notificationId);
  }

  static Future<void> scheduleNotificationsForDate(DateTime date, List<model.Message> messages) async {
    if (messages.isEmpty) return;

    // デスクトッププラットフォームでは通知スケジュールをスキップ
    if (_isDesktopPlatform) {
      _logOnce(
        'notificationsScheduleSkippedDesktop',
        '[NotificationService] デスクトッププラットフォームでは通知スケジュールをスキップします',
      );
      return;
    }

    final notificationTime = tz.TZDateTime(
      tz.local,
      date.year,
      date.month,
      date.day,
      9,
      0,
    );

    if (notificationTime.isBefore(tz.TZDateTime.now(tz.local))) {
      return;
    }

    final notificationId = date.hashCode % 2147483647;
    final title = '記録があります';
    final dateStr = FormatUtils.formatDateForNotification(date);
    final body = messages.length == 1
        ? '$dateStrのあなたからの記録があります。'
        : '$dateStrのあなたからの記録が${messages.length}件あります。';

    const androidDetails = AndroidNotificationDetails(
      'after_channel',
      'After',
              channelDescription: '記録が届いた通知',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.zonedSchedule(
      notificationId,
      title,
      body,
      notificationTime,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancelNotificationForDate(DateTime date) async {
    if (!_initialized) return;
    final notificationId = date.hashCode % 2147483647;
    await _notifications.cancel(notificationId);
  }
}

