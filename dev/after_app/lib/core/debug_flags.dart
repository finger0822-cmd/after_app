import 'package:flutter/foundation.dart';

/// Debug環境でプラグイン初期化を段階的に無効化するためのフラグ
class DebugFlags {
  /// Database (Isar) の初期化を無効化
  static const bool disableDatabase = false;
  
  /// NotificationService の初期化を無効化
  static const bool disableNotificationService = false;
  
  /// 通知スケジュール処理を無効化
  static const bool disableNotificationScheduling = false;
  
  /// すべてのプラグイン初期化を無効化（デバッグ用）
  static const bool disableAllPlugins = false;
  
  /// ログ出力用のヘルパー
  static String get status {
    if (disableAllPlugins) {
      return 'ALL_PLUGINS_DISABLED';
    }
    final flags = <String>[];
    if (disableDatabase) flags.add('DB');
    if (disableNotificationService) flags.add('NOTIF_SVC');
    if (disableNotificationScheduling) flags.add('NOTIF_SCHED');
    return flags.isEmpty ? 'ALL_ENABLED' : flags.join(',');
  }
}

