import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// ログレベル（v2）
/// traceが最も詳細、infoが最も簡潔
enum LogLevel {
  trace, // 詳細トレースログ（Heartbeat等、最も詳細）
  debug, // デバッグ用ログ
  info, // 通常の情報ログ（デフォルト、最も簡潔）
}

/// クラッシュログをファイルに書き込むユーティリティ
class CrashLogger {
  static File? _logFile;
  static bool _initialized = false;
  static Timer? _heartbeatTimer;
  static Timer? _serviceDiagnosticsTimer;

  // v2: ログレベル管理（初期値はinfo）
  static LogLevel _currentLevel = LogLevel.info;

  /// プロセスIDを取得
  static int get processId => pid;

  /// ログファイルの出力先をLocalAppDataに変更するか（WindowsでOneDrive同期を避けるため）
  static const bool useLocalAppData = true;

  /// ログファイルを初期化（WindowsのLocalAppData配下に作成）
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      Directory dir;
      if (Platform.isWindows && useLocalAppData) {
        // Windows: LocalAppData配下を使用（OneDrive同期を避ける）
        final localAppData = Platform.environment['LOCALAPPDATA'];
        if (localAppData != null) {
          dir = Directory('$localAppData/after_app');
        } else {
          // フォールバック: Documents配下
          dir = await getApplicationDocumentsDirectory();
        }
      } else {
        // その他のプラットフォーム: Documents配下
        dir = await getApplicationDocumentsDirectory();
      }

      final logDir = Directory('${dir.path}/logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      _logFile = File('${logDir.path}/crash_$timestamp.log');

      await _logFile!.writeAsString(
        '=== Crash Log Started ===\n'
        'Time: ${DateTime.now().toIso8601String()}\n'
        'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}\n'
        'Debug Mode: $kDebugMode\n'
        'Process ID: $processId\n'
        'Log Directory: ${logDir.path}\n'
        '================================\n\n',
        mode: FileMode.append,
      );

      _initialized = true;
      debugPrint('[CrashLogger] Initialized: ${_logFile!.path}');
    } catch (e) {
      debugPrint('[CrashLogger] Failed to initialize: $e');
    }
  }

  /// ログレベルを設定（debugビルド限定、releaseでは無視）
  static void setLogLevel(LogLevel level) {
    assert(() {
      if (!kDebugMode) {
        return true;
      }
      _currentLevel = level;
      return true;
    }());
  }

  /// 現在のログレベルを取得
  static LogLevel get currentLevel => _currentLevel;

  /// ログをファイルに書き込む（標準出力にも出力）
  /// v2: 後方互換性のため残すが、logInfo/logDebug/logTraceの使用を推奨
  static Future<void> log(String message, {String? level}) async {
    await logInfo(message, level: level);
  }

  /// Infoレベルのログ（currentLevelがinfo以上（詳細度が低い）の時のみ出力）
  static Future<void> logInfo(String message, {String? level}) async {
    if (_shouldLog(LogLevel.info)) {
      await _writeLog(message, level ?? 'INFO');
    }
  }

  /// Debugレベルのログ（currentLevelがdebug以上（詳細度が低い）の時のみ出力）
  static Future<void> logDebug(String message, {String? level}) async {
    assert(() {
      if (!kDebugMode) {
        return true;
      }
      if (_shouldLog(LogLevel.debug)) {
        _writeLog(message, level ?? 'DEBUG');
      }
      return true;
    }());
  }

  /// Traceレベルのログ（currentLevelがtrace以上（詳細度が低い）の時のみ出力）
  static Future<void> logTrace(String message, {String? level}) async {
    assert(() {
      if (!kDebugMode) {
        return true;
      }
      if (_shouldLog(LogLevel.trace)) {
        _writeLog(message, level ?? 'TRACE');
      }
      return true;
    }());
  }

  /// ログを出力すべきか判定
  /// messageLevelがcurrentLevel以上（詳細度が低い）の時のみ出力
  /// enum順: trace=0（最も詳細）, debug=1, info=2（最も簡潔）
  static bool _shouldLog(LogLevel messageLevel) {
    if (!kDebugMode) {
      return false;
    }
    // 数値比較: trace=0, debug=1, info=2
    // messageLevel.index >= _currentLevel.index なら出力（詳細度が低い=数値が大きい）
    return messageLevel.index >= _currentLevel.index;
  }

  /// 実際にログを書き込む（内部メソッド）
  static Future<void> _writeLog(String message, String level) async {
    final timestamp = DateTime.now().toIso8601String();
    final logLine = '[$timestamp] [$level] $message\n';

    // 標準出力に出力（flutter runで見える）
    debugPrint(logLine.trim());

    // ファイルにも書き込む
    if (_logFile != null) {
      try {
        await _logFile!.writeAsString(logLine, mode: FileMode.append);
      } catch (e) {
        debugPrint('[CrashLogger] Failed to write to file: $e');
      }
    }
  }

  /// 例外をログに記録
  static Future<void> logException(
    Object error,
    StackTrace stack, {
    String? context,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('=== EXCEPTION ===');
    if (context != null) {
      buffer.writeln('Context: $context');
    }
    buffer.writeln('Time: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Error: $error');
    buffer.writeln('Error Type: ${error.runtimeType}');
    buffer.writeln('Stack:');
    buffer.writeln(stack.toString());
    buffer.writeln('================');

    await log(buffer.toString(), level: 'EXCEPTION');
  }

  /// プロセス終了時のログ
  static Future<void> logShutdown({int? exitCode}) async {
    await log(
      '=== PROCESS SHUTDOWN ===\n'
      'Time: ${DateTime.now().toIso8601String()}\n'
      'Exit Code: ${exitCode ?? 'unknown'}\n'
      'Process ID: $processId\n'
      '========================',
      level: 'SHUTDOWN',
    );
  }

  /// ハートビートを開始（debugビルド限定、10秒ごとにプロセス生存確認ログを出力）
  /// 冪等性: 既に起動済みの場合は何もしない
  static void startHeartbeat() {
    assert(() {
      // Releaseビルドでは絶対に動かない
      if (!kDebugMode) {
        return true;
      }

      // 既に起動している場合は何もしない（多重起動防止、ログも出さない）
      if (_heartbeatTimer != null) {
        return true;
      }

      _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
        // v2: Heartbeatログはtraceレベル（通常は出ない）
        logTrace(
          '[HEARTBEAT] pid=$processId timestamp=${DateTime.now().toIso8601String()}',
          level: 'HEARTBEAT',
        );
      });

      // Timer作成後にログを1回出力（debugレベル、多重起動時は出さない）
      logDebug('[CrashLogger] Heartbeat timer started');

      return true;
    }());
  }

  /// ハートビートを停止
  static void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Service diagnostics を開始（debugビルド限定、30秒ごとにVM Service接続状態をチェック）
  /// 冪等性: 既に起動済みの場合は何もしない
  static void startServiceDiagnostics() {
    assert(() {
      // Releaseビルドでは絶対に動かない
      if (!kDebugMode) {
        return true;
      }

      // 既に起動している場合は何もしない（多重起動防止、ログも出さない）
      if (_serviceDiagnosticsTimer != null) {
        return true;
      }

      _serviceDiagnosticsTimer = Timer.periodic(const Duration(seconds: 30), (
        timer,
      ) async {
        try {
          final serviceInfo = await developer.Service.getInfo();
          if (serviceInfo.serverUri != null) {
            final vmServiceUrl =
                'ws://localhost:${serviceInfo.serverUri!.port}${serviceInfo.serverUri!.path}ws';
            final vmServiceHttpUrl =
                'http://localhost:${serviceInfo.serverUri!.port}${serviceInfo.serverUri!.path}';
            // v2: VM Service is alive はdebugレベル（通常は出ない）
            await logDebug(
              '[SERVICE_CHECK] VM Service is alive\n'
              '[SERVICE_CHECK] URL: $vmServiceHttpUrl\n'
              '[SERVICE_CHECK] WebSocket: $vmServiceUrl',
            );
          } else {
            // v2: VM Service not available もdebugレベル（通常は出ない）
            await logDebug('[SERVICE_CHECK] VM Service not available');
          }
        } catch (e, stack) {
          // 例外時のlogExceptionとERRORログは維持（infoレベル）
          await logException(e, stack, context: 'Service connection check');
          await logInfo(
            '[SERVICE_CHECK] Connection lost! Check log file for VM Service URL to reconnect.',
            level: 'ERROR',
          );
        }
      });

      // Timer作成後にログを1回出力（debugレベル、多重起動時は出さない）
      logDebug('[CrashLogger] Service diagnostics timer started');

      return true;
    }());
  }

  /// Service diagnostics を停止
  static void stopServiceDiagnostics() {
    _serviceDiagnosticsTimer?.cancel();
    _serviceDiagnosticsTimer = null;
  }

  /// すべてのタイマーを停止（detached/dispose時に呼び出す）
  static void stopAllTimers() {
    stopHeartbeat();
    stopServiceDiagnostics();
  }
}
