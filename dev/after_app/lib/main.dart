import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/notification.dart';
import 'core/crash_logger.dart';
import 'core/debug_flags.dart';
import 'core/app_lifecycle_observer.dart';
import 'data/db.dart';
import 'data/message_model.dart' as model;
import 'data/message_repo.dart';
import 'app.dart';

// v2: Traceログを有効にするか（デフォルトはfalse、明示的にtrueにした時のみtraceログが出る）
const bool kEnableTraceLogs = false;

void main() async {
  // クラッシュロガーを最初に初期化
  await CrashLogger.initialize();
  await CrashLogger.log('[main] START', level: 'INFO');
  
  // グローバル例外捕捉の設定（アプリ終了検知用）
  FlutterError.onError = (FlutterErrorDetails details) {
    final errorMsg = details.exceptionAsString();
    final stack = details.stack?.toString() ?? 'No stack trace';
    
    // 標準出力に出力
    debugPrint('[main] === FlutterError ===');
    debugPrint('[main] Time: ${DateTime.now().toIso8601String()}');
    debugPrint('[main] Exception: $errorMsg');
    debugPrint('[main] Stack: $stack');
    debugPrint('[main] Library: ${details.library}');
    debugPrint('[main] Context: ${details.context}');
    debugPrint('[main] ===================');
    
    // ファイルにも書き込む
    CrashLogger.logException(
      details.exception,
      details.stack!,
      context: 'FlutterError: ${details.library}',
    );
    
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    // 標準出力に出力
    debugPrint('[main] === PlatformDispatcher Error ===');
    debugPrint('[main] Time: ${DateTime.now().toIso8601String()}');
    debugPrint('[main] Error: $error');
    debugPrint('[main] Stack: $stack');
    debugPrint('[main] Error Type: ${error.runtimeType}');
    debugPrint('[main] ================================');
    
    // ファイルにも書き込む
    CrashLogger.logException(error, stack, context: 'PlatformDispatcher');
    
    return true; // エラーを処理したことを示す
  };

  await runZonedGuarded(
    () async {
      await CrashLogger.log('[main] runZonedGuarded START', level: 'INFO');
      
      WidgetsFlutterBinding.ensureInitialized();
      await CrashLogger.log('[main] WidgetsFlutterBinding initialized', level: 'INFO');
      
      // ライフサイクルオブザーバーを初期化
      AppLifecycleObserver.initialize();
      await CrashLogger.log('[main] AppLifecycleObserver initialized', level: 'INFO');

      // LocaleDataExceptionの根治：日付フォーマットデータを初期化
      try {
        await initializeDateFormatting('ja_JP', null);
        await CrashLogger.log('[main] date format initialized', level: 'INFO');
      } catch (e, stack) {
        await CrashLogger.logException(e, stack, context: 'date format init');
      }

      await CrashLogger.log('[main] Debug flags: ${DebugFlags.status}', level: 'INFO');
      
      // Database初期化（フラグで無効化可能）
      if (!DebugFlags.disableDatabase && !DebugFlags.disableAllPlugins) {
        await CrashLogger.log('[main] Initializing Database...', level: 'INFO');
        try {
          await Database.instance;
          await CrashLogger.log('[main] Database initialized', level: 'INFO');
        } catch (e, stack) {
          await CrashLogger.logException(e, stack, context: 'Database initialization');
        }
      } else {
        await CrashLogger.log('[main] Database initialization SKIPPED (debug flag)', level: 'INFO');
      }
      
      // NotificationService初期化（フラグで無効化可能）
      if (!DebugFlags.disableNotificationService && !DebugFlags.disableAllPlugins) {
        await CrashLogger.log('[main] Initializing NotificationService...', level: 'INFO');
        try {
          await NotificationService.initialize();
          final hasPermission = await NotificationService.requestPermissions();
          await CrashLogger.log('[main] NotificationService initialized, permission: $hasPermission', level: 'INFO');

          // 通知スケジュール処理（フラグで無効化可能）
          if (hasPermission && !DebugFlags.disableNotificationScheduling) {
            try {
              final repo = MessageRepo();
              await repo.openMessagesDueToday();

              final sealedMessages = await repo.getSealedMessages();
              final messagesByDate = <DateTime, List<model.Message>>{};
              for (final msg in sealedMessages) {
                final date = msg.openOn;
                messagesByDate.putIfAbsent(date, () => []).add(msg);
              }

              for (final entry in messagesByDate.entries) {
                await NotificationService.cancelNotificationForDate(entry.key);
                await NotificationService.scheduleNotificationsForDate(
                  entry.key,
                  entry.value,
                );
              }
              await CrashLogger.log('[main] Notification scheduling completed', level: 'INFO');
            } catch (e, stack) {
              await CrashLogger.logException(e, stack, context: 'Notification scheduling');
            }
          } else {
            await CrashLogger.log('[main] Notification scheduling SKIPPED (flag or no permission)', level: 'INFO');
          }
        } catch (e, stack) {
          await CrashLogger.logException(e, stack, context: 'NotificationService initialization');
        }
      } else {
        await CrashLogger.log('[main] NotificationService initialization SKIPPED (debug flag)', level: 'INFO');
      }

      // VM Service情報を取得してログに記録
      try {
        final serviceInfo = await developer.Service.getInfo();
        if (serviceInfo.serverUri != null) {
          final vmServiceUrl = 'ws://localhost:${serviceInfo.serverUri!.port}${serviceInfo.serverUri!.path}ws';
          final vmServiceHttpUrl = 'http://localhost:${serviceInfo.serverUri!.port}${serviceInfo.serverUri!.path}';
          await CrashLogger.log(
            '[main] VM Service URL: $vmServiceHttpUrl\n'
            '[main] VM Service WebSocket: $vmServiceUrl\n'
            '[main] Process ID: ${CrashLogger.processId}\n'
            '[main] To reconnect: flutter attach --debug-url=$vmServiceUrl',
            level: 'INFO',
          );
        } else {
          await CrashLogger.log('[main] VM Service not available (release mode?)', level: 'WARNING');
        }
      } catch (e, stack) {
        await CrashLogger.logException(e, stack, context: 'VM Service info retrieval');
      }
      
      await CrashLogger.log('[main] Starting app...', level: 'INFO');
      runApp(const ProviderScope(child: App()));
      await CrashLogger.log('[main] App started', level: 'INFO');
      
      // v2: デバッグビルドでは常にdebugレベル、Traceログが有効な場合はtraceレベルに設定
      assert(() {
        if (!kDebugMode) {
          return true;
        }
        if (kEnableTraceLogs) {
          // LogLevelはcrash_logger.dartで定義されている
          // import 'core/crash_logger.dart'で既にインポート済み
          CrashLogger.setLogLevel(LogLevel.trace);
        } else {
          // Traceログが無効でも、NowSheetのテストのためにdebugレベルを設定
          CrashLogger.setLogLevel(LogLevel.debug);
        }
        return true;
      }());
      
      // Start debug timers (debugビルド限定、冪等性保証)
      assert(() {
        if (!kDebugMode) {
          return true;
        }
        
        // Heartbeat開始（既に起動済みなら何もしない）
        CrashLogger.startHeartbeat();
        
        // Service diagnostics開始（既に起動済みなら何もしない）
        CrashLogger.startServiceDiagnostics();
        
        return true;
      }());
      
      if (kDebugMode) {
        await CrashLogger.logInfo('[main] Debug timers started (heartbeat + service diagnostics)', level: 'INFO');
      }
    },
    (error, stack) {
      // runZonedGuardedのエラーハンドラ
      debugPrint('[main] === runZonedGuarded Error ===');
      debugPrint('[main] Error: $error');
      debugPrint('[main] Stack: $stack');
      debugPrint('[main] ==============================');
      
      CrashLogger.logException(error, stack, context: 'runZonedGuarded');
    },
  );
}
