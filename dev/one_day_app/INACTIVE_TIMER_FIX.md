# Windows inactive時のタイマー停止・再開対応

## 変更点の説明

Windowsで`AppLifecycleState.detached`が期待通り来ない場合に備え、`inactive`時にタイマーを停止し、`resumed`時に再開するように修正しました。

### 主な変更
1. **`app_lifecycle_observer.dart`**: `inactive`時にタイマー停止、`resumed`時に再開ロジックを追加
2. **`crash_logger.dart`**: 変更なし（既に適切に実装済み）
3. **`main.dart`**: 変更なし（既に適切に実装済み）

## git diff形式の差分

```diff
diff --git a/after_app/lib/core/app_lifecycle_observer.dart b/after_app/lib/core/app_lifecycle_observer.dart
index 1234567..abcdefg 100644
--- a/after_app/lib/core/app_lifecycle_observer.dart
+++ b/after_app/lib/core/app_lifecycle_observer.dart
@@ -1,5 +1,7 @@
 import 'dart:async';
+import 'dart:developer' as developer;
 import 'dart:isolate';
+import 'package:flutter/foundation.dart';
 import 'package:flutter/widgets.dart';
 import 'crash_logger.dart';
 
@@ -33,8 +35,50 @@ class AppLifecycleObserver with WidgetsBindingObserver {
   }
   
   /// Service diagnostics タイマーを登録（detached時に停止するため）
   static void registerServiceCheckTimer(Timer timer) {
-    _serviceCheckTimer = timer;
+    _serviceCheckTimer ??= timer; // 既に値があれば上書きしない
+  }
+  
+  /// Service diagnostics タイマーを再作成（resumed時に呼び出す）
+  static void resumeServiceCheckTimer() {
+    if (!kDebugMode) {
+      return;
+    }
+    
+    // 既に起動している場合は何もしない
+    if (_serviceCheckTimer != null) {
+      return;
+    }
+    
+    // タイマーを再作成
+    _serviceCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
+      try {
+        final serviceInfo = await developer.Service.getInfo();
+        if (serviceInfo.serverUri != null) {
+          final vmServiceUrl = 'ws://localhost:${serviceInfo.serverUri!.port}${serviceInfo.serverUri!.path}ws';
+          final vmServiceHttpUrl = 'http://localhost:${serviceInfo.serverUri!.port}${serviceInfo.serverUri!.path}';
+          await CrashLogger.log(
+            '[SERVICE_CHECK] VM Service is alive\n'
+            '[SERVICE_CHECK] URL: $vmServiceHttpUrl\n'
+            '[SERVICE_CHECK] WebSocket: $vmServiceUrl',
+            level: 'INFO',
+          );
+        } else {
+          await CrashLogger.log('[SERVICE_CHECK] VM Service not available', level: 'WARNING');
+        }
+      } catch (e, stack) {
+        await CrashLogger.logException(e, stack, context: 'Service connection check');
+        await CrashLogger.log(
+          '[SERVICE_CHECK] Connection lost! Check log file for VM Service URL to reconnect.',
+          level: 'ERROR',
+        );
+      }
+    });
+    CrashLogger.log('[LifecycleObserver] Service diagnostics resumed', level: 'INFO');
+  }
+  
+  /// タイマーを再開（resumed時に呼び出す）
+  static void resumeTimers() {
+    if (!kDebugMode) {
+      return;
+    }
+    
+    // Heartbeatを再開（既に起動していない場合のみ）
+    CrashLogger.startHeartbeat();
+    
+    // Service diagnosticsを再開（既に起動していない場合のみ）
+    resumeServiceCheckTimer();
   }
   
   static void dispose() {
@@ -42,8 +86,7 @@ class AppLifecycleObserver with WidgetsBindingObserver {
       WidgetsBinding.instance.removeObserver(_instance!);
       _instance = null;
       _exitPort?.close();
       _exitPort = null;
-      _serviceCheckTimer?.cancel();
-      _serviceCheckTimer = null;
+      _stopTimers(); // タイマーを確実に停止
       CrashLogger.log('[LifecycleObserver] Disposed', level: 'INFO');
     }
   }
@@ -52,20 +95,30 @@ class AppLifecycleObserver with WidgetsBindingObserver {
   void didChangeAppLifecycleState(AppLifecycleState state) {
     CrashLogger.log(
       '[LifecycleObserver] App lifecycle changed: $state',
       level: 'INFO',
     );
     
-    // 終了状態を検知
-    if (state == AppLifecycleState.detached) {
+    if (state == AppLifecycleState.inactive) {
+      // inactive時にタイマーを停止（Windowsでdetachedが来ない場合の対策）
+      CrashLogger.log(
+        '[LifecycleObserver] App is inactive - stopping timers',
+        level: 'INFO',
+      );
+      _stopTimers();
+    } else if (state == AppLifecycleState.resumed) {
+      // resumed時にタイマーを再開（debugビルド限定、多重起動防止）
+      CrashLogger.log(
+        '[LifecycleObserver] App is resumed - resuming timers',
+        level: 'INFO',
+      );
+      resumeTimers();
+    } else if (state == AppLifecycleState.detached) {
       CrashLogger.log(
         '[LifecycleObserver] App is being detached - termination imminent',
         level: 'WARNING',
       );
       // タイマーを停止
-      CrashLogger.stopHeartbeat();
-      _serviceCheckTimer?.cancel();
-      _serviceCheckTimer = null;
+      _stopTimers();
       // 終了時にログを記録
       CrashLogger.logShutdown(exitCode: 0);
     } else if (state == AppLifecycleState.paused) {
       CrashLogger.log(
         '[LifecycleObserver] App is being paused - this may lead to termination',
         level: 'WARNING',
       );
     }
   }
+  
+  /// タイマーを停止（内部メソッド）
+  static void _stopTimers() {
+    CrashLogger.stopHeartbeat();
+    _serviceCheckTimer?.cancel();
+    _serviceCheckTimer = null;
+  }
 }
```

## Windowsでの再現/確認手順

### 1. アプリを起動
```bash
cd after_app
flutter run -d windows --vm-service-port=0 --disable-service-auth-codes
```

### 2. 起動直後のログを確認
- `[main] Heartbeat started (debug mode)` が1回だけ出力されることを確認
- `[main] Service diagnostics started (debug mode)` が1回だけ出力されることを確認
- `[HEARTBEAT]` が10秒ごとに出力されることを確認

### 3. アプリを非アクティブにする
- アプリウィンドウを最小化する、または別のウィンドウに切り替える
- `[LifecycleObserver] App is inactive - stopping timers` が出力されることを確認
- 以降、`[HEARTBEAT]` と `[SERVICE_CHECK]` が出力されなくなることを確認

### 4. アプリに戻す（resumed）
- アプリウィンドウを再度アクティブにする
- `[LifecycleObserver] App is resumed - resuming timers` が出力されることを確認
- `[LifecycleObserver] Heartbeat resumed` が出力されることを確認（既に起動している場合は出力されない）
- `[LifecycleObserver] Service diagnostics resumed` が出力されることを確認（既に起動している場合は出力されない）
- 以降、`[HEARTBEAT]` が10秒ごとに再開されることを確認

### 5. 多重起動防止の確認
- アプリを複数回非アクティブ/アクティブにしても、タイマーが1つだけ動作することを確認
- `[HEARTBEAT]` が増殖しないことを確認

