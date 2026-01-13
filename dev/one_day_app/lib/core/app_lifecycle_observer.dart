import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'crash_logger.dart';

/// アプリのライフサイクルイベントを監視してログに記録
class AppLifecycleObserver with WidgetsBindingObserver {
  static AppLifecycleObserver? _instance;
  static RawReceivePort? _exitPort;
  static final Set<String> _loggedKeys = <String>{};
  
  static void initialize() {
    if (_instance == null) {
      _instance = AppLifecycleObserver();
      WidgetsBinding.instance.addObserver(_instance!);
      assert(() {
        if (kDebugMode) {
          CrashLogger.logDebug('[LifecycleObserver] Initialized', level: 'INFO');
        }
        return true;
      }());
      
      // Isolate終了リスナーを追加（可能なら）
      try {
        _exitPort = RawReceivePort((message) {
          assert(() {
            if (kDebugMode) {
              CrashLogger.logDebug(
                '[LifecycleObserver] Isolate exit listener triggered: $message',
                level: 'WARNING',
              );
            }
            return true;
          }());
          // Isolate終了時にも必ずタイマーを停止（Releaseビルドでも確実に実行）
          CrashLogger.stopAllTimers();
        });
        Isolate.current.addOnExitListener(_exitPort!.sendPort, response: 'isolate_exit');
        assert(() {
          if (kDebugMode) {
            CrashLogger.logDebug('[LifecycleObserver] Isolate exit listener added', level: 'INFO');
          }
          return true;
        }());
      } catch (e) {
        assert(() {
          if (kDebugMode) {
            CrashLogger.logDebug('[LifecycleObserver] Failed to add isolate exit listener: $e', level: 'WARNING');
          }
          return true;
        }());
      }
    }
  }
  
  /// 同一キーのログを1回だけ出力する（inactive時のログ連打防止用）
  /// v2: debugレベルのログとして出力
  static void _logOnce(String key, String message) {
    assert(() {
      if (!kDebugMode) {
        return true;
      }
      if (_loggedKeys.add(key)) {
        CrashLogger.logDebug(message, level: 'INFO');
      }
      return true;
    }());
  }
  
  /// タイマーを再開（resumed時に呼び出す）
  /// debugビルド限定、冪等性保証
  static void resumeTimers() {
    assert(() {
      if (!kDebugMode) {
        return true;
      }
      
      // Heartbeatを再開（既に起動していない場合のみ）
      CrashLogger.startHeartbeat();
      
      // Service diagnosticsを再開（既に起動していない場合のみ）
      CrashLogger.startServiceDiagnostics();
      
      return true;
    }());
  }
  
  static void dispose() {
    if (_instance != null) {
      WidgetsBinding.instance.removeObserver(_instance!);
      _instance = null;
      _exitPort?.close();
      _exitPort = null;
      // タイマーを確実に停止（例外なく、Releaseビルドでも確実に実行）
      CrashLogger.stopAllTimers();
      assert(() {
        if (kDebugMode) {
          CrashLogger.logDebug('[LifecycleObserver] Disposed', level: 'INFO');
        }
        return true;
      }());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // v2: state変化時のみdebugログを出力（連打抑制）
    assert(() {
      if (!kDebugMode) {
        return true;
      }
      // state変化は毎回ログ出力（ただしdebugレベル）
      CrashLogger.logDebug(
        '[LifecycleObserver] App lifecycle changed: $state',
        level: 'INFO',
      );
      return true;
    }());
    
    if (state == AppLifecycleState.inactive) {
      // inactive時はタイマーを停止しない（Windowsで頻繁に発火するため、ノイズを減らす）
      // ログは初回のみ出力（連打防止）
      _logOnce(
        'lifecycle_inactive',
        '[LifecycleObserver] App is inactive - timers continue running',
      );
      // inactiveでは停止しない（paused/detachedで停止する）
    } else if (state == AppLifecycleState.resumed) {
      // resumed時にタイマーを再開（debugビルド限定、多重起動防止）
      _logOnce(
        'lifecycle_resumed_resuming',
        '[LifecycleObserver] App is resumed - resuming timers',
      );
      assert(() {
        if (!kDebugMode) {
          return true;
        }
        resumeTimers();
        return true;
      }());
    } else if (state == AppLifecycleState.detached) {
      // detached時は必ずタイマーを停止（例外なく）
      _logOnce(
        'lifecycle_detached_stopping',
        '[LifecycleObserver] App is being detached - termination imminent',
      );
      CrashLogger.stopAllTimers();
      assert(() {
        if (!kDebugMode) {
          return true;
        }
        // 終了時にログを記録
        CrashLogger.logShutdown(exitCode: 0);
        return true;
      }());
    } else if (state == AppLifecycleState.paused) {
      // paused時にタイマーを停止（バックグラウンド移行時）
      _logOnce(
        'lifecycle_paused_stopping',
        '[LifecycleObserver] App is being paused - stopping timers',
      );
      // タイマーを停止（副作用なし、確実に実行）
      CrashLogger.stopAllTimers();
    }
  }

  @override
  void didHaveMemoryPressure() {
    assert(() {
      if (kDebugMode) {
        CrashLogger.logInfo(
          '[LifecycleObserver] Memory pressure detected',
          level: 'WARNING',
        );
      }
      return true;
    }());
  }

  @override
  void didChangeAccessibilityFeatures() {
    // 通常はログ不要
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    // 通常はログ不要
  }

  @override
  void didChangeTextScaleFactor() {
    // 通常はログ不要
  }
}

