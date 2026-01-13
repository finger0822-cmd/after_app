# ライフサイクル契約(v1)実装

## 変更差分

### 1. `after_app/lib/core/crash_logger.dart`

```diff
--- a/after_app/lib/core/crash_logger.dart
+++ b/after_app/lib/core/crash_logger.dart
@@ -1,4 +1,5 @@
 import 'dart:async';
+import 'dart:developer' as developer;
 import 'dart:io';
 import 'package:flutter/foundation.dart';
 import 'package:path_provider/path_provider.dart';
@@ -7,6 +8,7 @@ class CrashLogger {
   static File? _logFile;
   static bool _initialized = false;
   static Timer? _heartbeatTimer;
+  static Timer? _serviceCheckTimer;
   
   /// プロセスIDを取得
   static int get processId => pid;
@@ -111,24 +113,75 @@ class CrashLogger {
 
   /// ハートビートを開始（debugビルド限定、10秒ごとにプロセス生存確認ログを出力）
+  /// 冪等性: 既に起動済みの場合は何もしない
   static void startHeartbeat() {
-    // 既に起動している場合は何もしない（多重起動防止）
-    if (_heartbeatTimer != null) {
-      return;
-    }
-    
-    // debugビルド限定
-    if (!kDebugMode) {
-      return;
-    }
-    
-    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
-      log(
-        '[HEARTBEAT] pid=$processId timestamp=${DateTime.now().toIso8601String()}',
-        level: 'HEARTBEAT',
-      );
-    });
+    assert(() {
+      // Releaseビルドでは絶対に動かない
+      if (!kDebugMode) {
+        return true;
+      }
+      
+      // 既に起動している場合は何もしない（多重起動防止）
+      if (_heartbeatTimer != null) {
+        return true;
+      }
+      
+      _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
+        log(
+          '[HEARTBEAT] pid=$processId timestamp=${DateTime.now().toIso8601String()}',
+          level: 'HEARTBEAT',
+        );
+      });
+      
+      return true;
+    }());
   }
 
   /// ハートビートを停止
   static void stopHeartbeat() {
     _heartbeatTimer?.cancel();
     _heartbeatTimer = null;
   }
+  
+  /// Service diagnostics を開始（debugビルド限定、30秒ごとにVM Service接続状態をチェック）
+  /// 冪等性: 既に起動済みの場合は何もしない
+  static void startServiceDiagnostics() {
+    assert(() {
+      // Releaseビルドでは絶対に動かない
+      if (!kDebugMode) {
+        return true;
+      }
+      
+      // 既に起動している場合は何もしない（多重起動防止）
+      if (_serviceCheckTimer != null) {
+        return true;
+      }
+      
+      _serviceCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
+        try {
+          final serviceInfo = await developer.Service.getInfo();
+          if (serviceInfo.serverUri != null) {
+            final vmServiceUrl = 'ws://localhost:${serviceInfo.serverUri!.port}${serviceInfo.serverUri!.path}ws';
+            final vmServiceHttpUrl = 'http://localhost:${serviceInfo.serverUri!.port}${serviceInfo.serverUri!.path}';
+            await log(
+              '[SERVICE_CHECK] VM Service is alive\n'
+              '[SERVICE_CHECK] URL: $vmServiceHttpUrl\n'
+              '[SERVICE_CHECK] WebSocket: $vmServiceUrl',
+              level: 'INFO',
+            );
+          } else {
+            await log('[SERVICE_CHECK] VM Service not available', level: 'WARNING');
+          }
+        } catch (e, stack) {
+          await logException(e, stack, context: 'Service connection check');
+          await log(
+            '[SERVICE_CHECK] Connection lost! Check log file for VM Service URL to reconnect.',
+            level: 'ERROR',
+          );
+        }
+      });
+      
+      return true;
+    }());
+  }
+  
+  /// Service diagnostics を停止
+  static void stopServiceDiagnostics() {
+    _serviceCheckTimer?.cancel();
+    _serviceCheckTimer = null;
+  }
+  
+  /// すべてのタイマーを停止（detached/dispose時に呼び出す）
+  static void stopAllTimers() {
+    stopHeartbeat();
+    stopServiceDiagnostics();
+  }
 }
```

### 2. `after_app/lib/core/app_lifecycle_observer.dart`

```diff
--- a/after_app/lib/core/app_lifecycle_observer.dart
+++ b/after_app/lib/core/app_lifecycle_observer.dart
@@ -1,5 +1,4 @@
-import 'dart:async';
-import 'dart:developer' as developer;
 import 'dart:isolate';
 import 'package:flutter/foundation.dart';
 import 'package:flutter/widgets.dart';
@@ -9,7 +8,7 @@ class AppLifecycleObserver with WidgetsBindingObserver {
   static AppLifecycleObserver? _instance;
   static RawReceivePort? _exitPort;
-  static Timer? _serviceCheckTimer;
+  static final Set<String> _loggedKeys = <String>{};
   
   static void initialize() {
     if (_instance == null) {
@@ -33,63 +32,30 @@ class AppLifecycleObserver with WidgetsBindingObserver {
     }
   }
   
-  /// Service diagnostics タイマーを登録（inactive/detached時に停止するため）
-  static void registerServiceCheckTimer(Timer timer) {
-    _serviceCheckTimer ??= timer; // 既に値があれば上書きしない
-  }
-  
-  /// Service diagnostics タイマーを再作成（resumed時に呼び出す）
-  static void resumeServiceCheckTimer() {
-    if (!kDebugMode) {
-      return;
-    }
-    
-    // 既に起動している場合は何もしない
-    if (_serviceCheckTimer != null) {
-      return;
-    }
-    
-    // タイマーを再作成
-    _serviceCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
-      try {
-        final serviceInfo = await developer.Service.getInfo();
-        if (serviceInfo.serverUri != null) {
-          final vmServiceUrl = 'ws://localhost:${serviceInfo.serverUri!.port}${serviceInfo.serverUri!.path}ws';
-          final vmServiceHttpUrl = 'http://localhost:${serviceInfo.serverUri!.port}${serviceInfo.serverUri!.path}';
-          await CrashLogger.log(
-            '[SERVICE_CHECK] VM Service is alive\n'
-            '[SERVICE_CHECK] URL: $vmServiceHttpUrl\n'
-            '[SERVICE_CHECK] WebSocket: $vmServiceUrl',
-            level: 'INFO',
-          );
-        } else {
-          await CrashLogger.log('[SERVICE_CHECK] VM Service not available', level: 'WARNING');
-        }
-      } catch (e, stack) {
-        await CrashLogger.logException(e, stack, context: 'Service connection check');
-        await CrashLogger.log(
-          '[SERVICE_CHECK] Connection lost! Check log file for VM Service URL to reconnect.',
-          level: 'ERROR',
-        );
-      }
-    });
-    CrashLogger.log('[LifecycleObserver] Service diagnostics resumed', level: 'INFO');
+  /// 同一キーのログを1回だけ出力する（inactive時のログ連打防止用）
+  static void _logOnce(String key, String message) {
+    if (_loggedKeys.add(key)) {
+      CrashLogger.log(message, level: 'INFO');
+    }
   }
   
   /// タイマーを再開（resumed時に呼び出す）
+  /// debugビルド限定、冪等性保証
   static void resumeTimers() {
-    if (!kDebugMode) {
-      return;
-    }
-    
-    // Heartbeatを再開（既に起動していない場合のみ）
-    CrashLogger.startHeartbeat();
-    
-    // Service diagnosticsを再開（既に起動していない場合のみ）
-    resumeServiceCheckTimer();
+    assert(() {
+      if (!kDebugMode) {
+        return true;
+      }
+      
+      // Heartbeatを再開（既に起動していない場合のみ）
+      CrashLogger.startHeartbeat();
+      
+      // Service diagnosticsを再開（既に起動していない場合のみ）
+      CrashLogger.startServiceDiagnostics();
+      
+      return true;
+    }());
   }
   
   static void dispose() {
     if (_instance != null) {
       WidgetsBinding.instance.removeObserver(_instance!);
       _instance = null;
       _exitPort?.close();
       _exitPort = null;
-      _stopTimers(); // タイマーを確実に停止
+      // タイマーを確実に停止（例外なく）
+      CrashLogger.stopAllTimers();
       CrashLogger.log('[LifecycleObserver] Disposed', level: 'INFO');
     }
   }
 
   @override
   void didChangeAppLifecycleState(AppLifecycleState state) {
-    CrashLogger.log(
-      '[LifecycleObserver] App lifecycle changed: $state',
-      level: 'INFO',
-    );
+    assert(() {
+      // Releaseビルドではログ出力もしない
+      if (!kDebugMode) {
+        return true;
+      }
+      
+      CrashLogger.log(
+        '[LifecycleObserver] App lifecycle changed: $state',
+        level: 'INFO',
+      );
+      
+      return true;
+    }());
     
     if (state == AppLifecycleState.inactive) {
-      // inactive時にタイマーを停止（Windowsでdetachedが来ない場合の対策）
-      CrashLogger.log(
-        '[LifecycleObserver] App is inactive - stopping timers',
-        level: 'INFO',
-      );
+      // inactive時にタイマーを停止（Windowsでdetachedが来ない場合の対策）
+      // ログは初回のみ出力（連打防止）
+      _logOnce(
+        'lifecycle_inactive_stopping',
+        '[LifecycleObserver] App is inactive - stopping timers',
+      );
       // タイマーを停止（副作用なし、確実に実行）
       CrashLogger.stopAllTimers();
     } else if (state == AppLifecycleState.resumed) {
-      // resumed時にタイマーを再開（debugビルド限定、多重起動防止）
-      CrashLogger.log(
-        '[LifecycleObserver] App is resumed - resuming timers',
-        level: 'INFO',
-      );
-      resumeTimers();
+      // resumed時にタイマーを再開（debugビルド限定、多重起動防止）
+      assert(() {
+        if (!kDebugMode) {
+          return true;
+        }
+        CrashLogger.log(
+          '[LifecycleObserver] App is resumed - resuming timers',
+          level: 'INFO',
+        );
+        resumeTimers();
+        return true;
+      }());
     } else if (state == AppLifecycleState.detached) {
-      CrashLogger.log(
-        '[LifecycleObserver] App is being detached - termination imminent',
-        level: 'WARNING',
-      );
-      // タイマーを停止
-      _stopTimers();
-      // 終了時にログを記録
-      CrashLogger.logShutdown(exitCode: 0);
+      assert(() {
+        if (!kDebugMode) {
+          return true;
+        }
+        CrashLogger.log(
+          '[LifecycleObserver] App is being detached - termination imminent',
+          level: 'WARNING',
+        );
+        // タイマーを停止（例外なく）
+        CrashLogger.stopAllTimers();
+        // 終了時にログを記録
+        CrashLogger.logShutdown(exitCode: 0);
+        return true;
+      }());
     } else if (state == AppLifecycleState.paused) {
-      CrashLogger.log(
-        '[LifecycleObserver] App is being paused - this may lead to termination',
-        level: 'WARNING',
-      );
+      assert(() {
+        if (!kDebugMode) {
+          return true;
+        }
+        CrashLogger.log(
+          '[LifecycleObserver] App is being paused - this may lead to termination',
+          level: 'WARNING',
+        );
+        return true;
+      }());
     }
   }
-  
-  /// タイマーを停止（内部メソッド）
-  static void _stopTimers() {
-    CrashLogger.stopHeartbeat();
-    _serviceCheckTimer?.cancel();
-    _serviceCheckTimer = null;
-  }
 }
```

### 3. `after_app/lib/main.dart`

```diff
--- a/after_app/lib/main.dart
+++ b/after_app/lib/main.dart
@@ -156,42 +156,15 @@ void main() async {
       await CrashLogger.log('[main] Starting app...', level: 'INFO');
       runApp(const ProviderScope(child: App()));
       await CrashLogger.log('[main] App started', level: 'INFO');
       
-      // Start heartbeat to track process survival (debugビルド限定)
-      if (kDebugMode) {
-        CrashLogger.startHeartbeat();
-        await CrashLogger.log('[main] Heartbeat started (debug mode)', level: 'INFO');
-      }
-      
-      // Start VM Service connection diagnostics (debugビルド限定、30秒ごと)
-      Timer? serviceCheckTimer;
-      if (kDebugMode) {
-        serviceCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
-          try {
-            final serviceInfo = await developer.Service.getInfo();
-            if (serviceInfo.serverUri != null) {
-              final vmServiceUrl = 'ws://localhost:${serviceInfo.serverUri!.port}${serviceInfo.serverUri!.path}ws';
-              final vmServiceHttpUrl = 'http://localhost:${serviceInfo.serverUri!.port}${serviceInfo.serverUri!.path}';
-              await CrashLogger.log(
-                '[SERVICE_CHECK] VM Service is alive\n'
-                '[SERVICE_CHECK] URL: $vmServiceHttpUrl\n'
-                '[SERVICE_CHECK] WebSocket: $vmServiceUrl',
-                level: 'INFO',
-              );
-            } else {
-              await CrashLogger.log('[SERVICE_CHECK] VM Service not available', level: 'WARNING');
-            }
-          } catch (e, stack) {
-            await CrashLogger.logException(e, stack, context: 'Service connection check');
-            // 接続が切れた場合はURLを再表示
-            await CrashLogger.log(
-              '[SERVICE_CHECK] Connection lost! Check log file for VM Service URL to reconnect.',
-              level: 'ERROR',
-            );
-          }
-        });
-        await CrashLogger.log('[main] Service diagnostics started (debug mode)', level: 'INFO');
-        
-        // AppLifecycleObserverにタイマーを登録して、detached時に停止できるようにする
-        AppLifecycleObserver.registerServiceCheckTimer(serviceCheckTimer);
+      // Start debug timers (debugビルド限定、冪等性保証)
+      assert(() {
+        if (!kDebugMode) {
+          return true;
+        }
+        
+        // Heartbeat開始（既に起動済みなら何もしない）
+        CrashLogger.startHeartbeat();
+        
+        // Service diagnostics開始（既に起動済みなら何もしない）
+        CrashLogger.startServiceDiagnostics();
+        
+        return true;
+      }());
+      
+      if (kDebugMode) {
+        await CrashLogger.log('[main] Debug timers started (heartbeat + service diagnostics)', level: 'INFO');
       }
     },
```

## 契約(v1)が満たされる理由

### ✅ 1. Debug専用処理の囲い
- **`assert(() { ...; return true; }());`形式を採用**: Releaseビルドでは`assert`が削除されるため、コードが実行されない
- **`kDebugMode`チェックも併用**: 二重の安全策として、`assert`内でも`kDebugMode`をチェック
- **適用箇所**: `startHeartbeat()`, `startServiceDiagnostics()`, `resumeTimers()`, `didChangeAppLifecycleState()`

### ✅ 2. タイマーの冪等性保証
- **Heartbeat**: `_heartbeatTimer != null`チェックで既に起動済みなら早期リターン
- **Service diagnostics**: `_serviceCheckTimer != null`チェックで既に起動済みなら早期リターン
- **`startHeartbeat()`と`startServiceDiagnostics()`は何度呼ばれても1つのタイマーのみ動作**

### ✅ 3. Timer停止の確実な実行
- **`detached`時**: `CrashLogger.stopAllTimers()`を呼び出し
- **`dispose()`時**: `CrashLogger.stopAllTimers()`を呼び出し
- **`stopAllTimers()`**: `stopHeartbeat()`と`stopServiceDiagnostics()`の両方を呼び出し、確実に停止

### ✅ 4. inactive時の副作用防止
- **`_logOnce()`メソッドを追加**: 同一キーで初回のみログ出力
- **`inactive`時のログ**: `_logOnce('lifecycle_inactive_stopping', ...)`で初回のみ出力
- **タイマー停止は副作用なし**: `CrashLogger.stopAllTimers()`はログ出力せず、タイマーのみ停止

### ✅ 5. ログ間隔の保証
- **Heartbeat**: 10秒間隔（`Duration(seconds: 10)`）
- **Service diagnostics**: 30秒間隔（`Duration(seconds: 30)`）
- **debugビルド限定**: `assert(() { ... }());`でReleaseでは無効化

### ✅ 6. タイマー管理の一元化
- **`crash_logger.dart`に統一**: HeartbeatとService diagnosticsの両方を`CrashLogger`クラスで管理
- **`main.dart`から直接作成しない**: `CrashLogger.startHeartbeat()`と`CrashLogger.startServiceDiagnostics()`を呼ぶだけ
- **`app_lifecycle_observer.dart`からも直接作成しない**: `CrashLogger`のメソッドを呼ぶだけ

### ✅ 7. 二重管理の排除
- **`main.dart`**: タイマーを作成せず、`CrashLogger`のメソッドを呼ぶだけ
- **`app_lifecycle_observer.dart`**: `registerServiceCheckTimer()`を削除し、`CrashLogger.startServiceDiagnostics()`を呼ぶだけ
- **`crash_logger.dart`**: すべてのタイマーを一元管理

## 動作確認手順

### 1. 起動時の確認
```bash
flutter run -d windows --vm-service-port=0 --disable-service-auth-codes
```
- `[main] Debug timers started (heartbeat + service diagnostics)` が1回だけ出力される
- `[HEARTBEAT]` が10秒ごとに出力される
- `[SERVICE_CHECK]` が30秒ごとに出力される

### 2. inactive時の確認
- アプリウィンドウを最小化または別ウィンドウに切り替える
- `[LifecycleObserver] App is inactive - stopping timers` が初回のみ出力される
- 以降、`[HEARTBEAT]` と `[SERVICE_CHECK]` が出力されなくなる

### 3. resumed時の確認
- アプリウィンドウを再度アクティブにする
- `[LifecycleObserver] App is resumed - resuming timers` が出力される
- 以降、`[HEARTBEAT]` が10秒ごとに再開される

### 4. 多重起動防止の確認
- アプリを複数回非アクティブ/アクティブにしても、タイマーが1つだけ動作する
- `[HEARTBEAT]` が増殖しない

### 5. Releaseビルドでの確認
```bash
flutter build windows --release
```
- `[HEARTBEAT]` と `[SERVICE_CHECK]` が一切出力されない
- タイマー関連のコードが実行されない

