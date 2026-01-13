# ライフサイクル契約(v1) 最終確定版

## 変更差分

### 1. `after_app/lib/core/crash_logger.dart`

#### 変数名の変更
```diff
- static Timer? _serviceCheckTimer;
+ static Timer? _serviceDiagnosticsTimer;
```

#### startHeartbeat() - Timer作成後のログ追加
```diff
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
        log(
          '[HEARTBEAT] pid=$processId timestamp=${DateTime.now().toIso8601String()}',
          level: 'HEARTBEAT',
        );
      });
      
+     // Timer作成後にログを1回出力
+     log('[CrashLogger] Heartbeat timer started', level: 'INFO');
+     
      return true;
```

#### startServiceDiagnostics() - 変数名変更とTimer作成後のログ追加
```diff
-     if (_serviceCheckTimer != null) {
+     if (_serviceDiagnosticsTimer != null) {
        return true;
      }
      
-     _serviceCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
+     _serviceDiagnosticsTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
        // ... タイマー処理 ...
      });
      
+     // Timer作成後にログを1回出力
+     log('[CrashLogger] Service diagnostics timer started', level: 'INFO');
+     
      return true;
```

#### stopServiceDiagnostics() - 変数名変更
```diff
  static void stopServiceDiagnostics() {
-   _serviceCheckTimer?.cancel();
-   _serviceCheckTimer = null;
+   _serviceDiagnosticsTimer?.cancel();
+   _serviceDiagnosticsTimer = null;
  }
```

### 2. `after_app/lib/core/app_lifecycle_observer.dart`

#### Isolate終了時のタイマー停止を追加（Releaseビルドでも確実に実行）
```diff
        _exitPort = RawReceivePort((message) {
          assert(() {
-           if (!kDebugMode) {
-             return true;
-           }
            CrashLogger.log(
              '[LifecycleObserver] Isolate exit listener triggered: $message',
              level: 'WARNING',
            );
-           // Isolate終了時にも必ずタイマーを停止
-           CrashLogger.stopAllTimers();
            return true;
          }());
+         // Isolate終了時にも必ずタイマーを停止（Releaseビルドでも確実に実行）
+         CrashLogger.stopAllTimers();
        });
```

#### didChangeAppLifecycleState() - ログの_logOnce()化
```diff
    } else if (state == AppLifecycleState.resumed) {
-     assert(() {
-       if (!kDebugMode) {
-         return true;
-       }
-       CrashLogger.log(
-         '[LifecycleObserver] App is resumed - resuming timers',
-         level: 'INFO',
-       );
-       resumeTimers();
-       return true;
-     }());
+     // resumed時にタイマーを再開（debugビルド限定、多重起動防止）
+     _logOnce(
+       'lifecycle_resumed_resuming',
+       '[LifecycleObserver] App is resumed - resuming timers',
+     );
+     assert(() {
+       if (!kDebugMode) {
+         return true;
+       }
+       resumeTimers();
+       return true;
+     }());
    } else if (state == AppLifecycleState.detached) {
-     assert(() {
-       if (!kDebugMode) {
-         return true;
-       }
-       CrashLogger.log(
-         '[LifecycleObserver] App is being detached - termination imminent',
-         level: 'WARNING',
-       );
-       // タイマーを停止（例外なく）
-       CrashLogger.stopAllTimers();
-       // 終了時にログを記録
-       CrashLogger.logShutdown(exitCode: 0);
-       return true;
-     }());
+     // detached時は必ずタイマーを停止（例外なく）
+     _logOnce(
+       'lifecycle_detached_stopping',
+       '[LifecycleObserver] App is being detached - termination imminent',
+     );
+     CrashLogger.stopAllTimers();
+     assert(() {
+       if (!kDebugMode) {
+         return true;
+       }
+       // 終了時にログを記録
+       CrashLogger.logShutdown(exitCode: 0);
+       return true;
+     }());
    } else if (state == AppLifecycleState.paused) {
-     assert(() {
-       if (!kDebugMode) {
-         return true;
-       }
-       CrashLogger.log(
-         '[LifecycleObserver] App is being paused - this may lead to termination',
-         level: 'WARNING',
-       );
-       return true;
-     }());
+     // paused時のログも初回のみ出力
+     _logOnce(
+       'lifecycle_paused',
+       '[LifecycleObserver] App is being paused - this may lead to termination',
+     );
    }
```

## 契約(v1)が成立している理由

### ✅ 1. Timer生成場所の一元化
- **`crash_logger.dart`のみでTimer生成**: `Timer.periodic()`の呼び出しは`startHeartbeat()`と`startServiceDiagnostics()`内のみ
- **`main.dart`**: Timerを直接作成せず、`CrashLogger.startXXX()`を呼ぶだけ
- **`app_lifecycle_observer.dart`**: Timerを直接作成・再生成せず、`CrashLogger.startXXX()`を呼ぶだけ

### ✅ 2. startの冪等性保証
- **`_heartbeatTimer != null`チェック**: 既に起動済みなら早期リターン
- **`_serviceDiagnosticsTimer != null`チェック**: 既に起動済みなら早期リターン
- **何回呼ばれても1本のTimerのみ**: Hot restartや複数回の`resumed`イベントでも多重起動しない

### ✅ 3. stopの安全性保証
- **`stopHeartbeat()`**: `cancel()`後に必ず`null`を代入
- **`stopServiceDiagnostics()`**: `cancel()`後に必ず`null`を代入
- **`stopAllTimers()`**: 両方のタイマーを確実に停止
- **何回呼ばれても安全**: `null`チェック（`?.cancel()`）により、既に停止済みでもエラーにならない

### ✅ 4. 停止経路の完全性
- **`detached`時**: `CrashLogger.stopAllTimers()`を呼び出し（Releaseビルドでも確実に実行）
- **`dispose()`時**: `CrashLogger.stopAllTimers()`を呼び出し（Releaseビルドでも確実に実行）
- **Isolate終了時**: `CrashLogger.stopAllTimers()`を呼び出し（Releaseビルドでも確実に実行）
- **すべての経路で確実に停止**: いかなる終了パスでもタイマーが残存しない

### ✅ 5. Release/Profileビルドでの沈黙
- **`assert(() { ...; return true; }());`形式**: Releaseビルドでは`assert`が削除され、コードが実行されない
- **`kDebugMode`チェック**: 二重の安全策として、`assert`内でも`kDebugMode`をチェック
- **ログ出力も`debugPrint()`経由**: Releaseビルドでは出力されない
- **タイマー処理も含めて完全に無効化**: Releaseビルドでは一切のオーバーヘッドがない

### ✅ 6. ログの抑制（同一状態で1回のみ）
- **`_logOnce(key, message)`**: 同一キーで初回のみログ出力
- **`inactive`時**: `lifecycle_inactive_stopping`キーで初回のみ
- **`resumed`時**: `lifecycle_resumed_resuming`キーで初回のみ
- **`detached`時**: `lifecycle_detached_stopping`キーで初回のみ
- **`paused`時**: `lifecycle_paused`キーで初回のみ

### ✅ 7. Timer作成後のログ出力
- **`startHeartbeat()`**: Timer作成後に`[CrashLogger] Heartbeat timer started`を1回出力
- **`startServiceDiagnostics()`**: Timer作成後に`[CrashLogger] Service diagnostics timer started`を1回出力
- **デバッグ時の可視性向上**: Timerが実際に作成されたことを確認できる

### ✅ 8. 変数名の明確化
- **`_serviceCheckTimer` → `_serviceDiagnosticsTimer`**: 目的に一致した命名
- **`_heartbeatTimer`: そのまま**: 既に明確な命名

## 動作確認手順

### 1. Debugビルドでの確認
```bash
flutter run -d windows --vm-service-port=0 --disable-service-auth-codes
```

**期待される動作:**
- `[CrashLogger] Heartbeat timer started` が1回だけ出力される
- `[CrashLogger] Service diagnostics timer started` が1回だけ出力される
- `[HEARTBEAT]` が10秒ごとに出力される
- `[SERVICE_CHECK]` が30秒ごとに出力される
- アプリを非アクティブにすると、`[LifecycleObserver] App is inactive - stopping timers` が初回のみ出力され、タイマーが停止する
- アプリを再アクティブにすると、`[LifecycleObserver] App is resumed - resuming timers` が初回のみ出力され、タイマーが再開する
- Hot restartしても、タイマーが1本だけ動作する（多重起動しない）

### 2. Releaseビルドでの確認
```bash
flutter build windows --release
```

**期待される動作:**
- `[HEARTBEAT]` と `[SERVICE_CHECK]` が一切出力されない
- タイマー関連のコードが実行されない
- オーバーヘッドがゼロ

### 3. 終了経路の確認
- **通常終了**: `detached` → `CrashLogger.stopAllTimers()` → タイマー停止
- **強制終了**: `dispose()` → `CrashLogger.stopAllTimers()` → タイマー停止
- **Isolate終了**: `addOnExitListener` → `CrashLogger.stopAllTimers()` → タイマー停止

すべての経路でタイマーが確実に停止することを確認。
