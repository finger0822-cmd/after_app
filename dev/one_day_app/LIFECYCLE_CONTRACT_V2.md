# ライフサイクル契約(v2) 実装

## v1からの変更点

### 主な目的
- **ログと診断の暴走を防ぐ**: Heartbeatログの連打を抑制
- **v1の契約を維持**: タイマー一元管理・冪等start・安全stop・停止経路の完全性は維持

### 新機能
1. **ログレベル管理**: `LogLevel` enum（info/debug/trace）を導入
2. **Heartbeatログの隔離**: traceレベルに変更し、通常は出力されない
3. **デフォルトはinfoのみ**: debug時でも、traceは明示的にONにしない限り出ない
4. **ログ連打抑制の強化**: `_logOnce()`を拡張し、同一state/同一開始ログの連打を防止

## 変更差分

### 1. `after_app/lib/core/crash_logger.dart`

#### LogLevel enumの追加
```dart
/// ログレベル（v2）
enum LogLevel {
  info,   // 通常の情報ログ（デフォルト）
  debug,  // デバッグ用ログ
  trace,  // 詳細トレースログ（Heartbeat等）
}
```

#### ログレベル管理の追加
```dart
// v2: ログレベル管理（初期値はinfo）
static LogLevel _currentLevel = LogLevel.info;

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
```

#### ログメソッドの追加（logInfo/logDebug/logTrace）
```dart
/// Infoレベルのログ（currentLevel >= info の時のみ出力）
static Future<void> logInfo(String message, {String? level}) async {
  if (_shouldLog(LogLevel.info)) {
    await _writeLog(message, level ?? 'INFO');
  }
}

/// Debugレベルのログ（currentLevel >= debug の時のみ出力）
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

/// Traceレベルのログ（currentLevel >= trace の時のみ出力）
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
static bool _shouldLog(LogLevel messageLevel) {
  if (!kDebugMode) {
    return false;
  }
  // 数値比較: info=0, debug=1, trace=2
  return messageLevel.index <= _currentLevel.index;
}
```

#### Heartbeatログをtraceレベルに変更
```diff
- _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
-   log(
-     '[HEARTBEAT] pid=$processId timestamp=${DateTime.now().toIso8601String()}',
-     level: 'HEARTBEAT',
-   );
- });
+ _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
+   // v2: Heartbeatログはtraceレベル（通常は出ない）
+   logTrace(
+     '[HEARTBEAT] pid=$processId timestamp=${DateTime.now().toIso8601String()}',
+     level: 'HEARTBEAT',
+   );
+ });
```

#### startHeartbeat/startServiceDiagnosticsの「startedログ」をdebugレベルに変更
```diff
- // Timer作成後にログを1回出力
- log('[CrashLogger] Heartbeat timer started', level: 'INFO');
+ // Timer作成後にログを1回出力（debugレベル、多重起動時は出さない）
+ logDebug('[CrashLogger] Heartbeat timer started', level: 'INFO');

- // Timer作成後にログを1回出力
- log('[CrashLogger] Service diagnostics timer started', level: 'INFO');
+ // Timer作成後にログを1回出力（debugレベル、多重起動時は出さない）
+ logDebug('[CrashLogger] Service diagnostics timer started', level: 'INFO');
```

#### 多重起動時のログ抑制
```diff
  // 既に起動している場合は何もしない（多重起動防止）
  if (_heartbeatTimer != null) {
    return true;
  }
+ // v2: 多重起動時はログも出さない（コメント追加）
```

### 2. `after_app/lib/core/app_lifecycle_observer.dart`

#### _logOnce()をdebugレベルに変更
```diff
  /// 同一キーのログを1回だけ出力する（inactive時のログ連打防止用）
+ /// v2: debugレベルのログとして出力
  static void _logOnce(String key, String message) {
    assert(() {
      if (!kDebugMode) {
        return true;
      }
      if (_loggedKeys.add(key)) {
-       CrashLogger.log(message, level: 'INFO');
+       CrashLogger.logDebug(message, level: 'INFO');
      }
      return true;
    }());
  }
```

#### 各種ログをdebugレベルに変更
```diff
- CrashLogger.log('[LifecycleObserver] Initialized', level: 'INFO');
+ assert(() {
+   if (kDebugMode) {
+     CrashLogger.logDebug('[LifecycleObserver] Initialized', level: 'INFO');
+   }
+   return true;
+ }());

- CrashLogger.log(
-   '[LifecycleObserver] Isolate exit listener triggered: $message',
-   level: 'WARNING',
- );
+ CrashLogger.logDebug(
+   '[LifecycleObserver] Isolate exit listener triggered: $message',
+   level: 'WARNING',
+ );

- CrashLogger.log('[LifecycleObserver] Disposed', level: 'INFO');
+ assert(() {
+   if (kDebugMode) {
+     CrashLogger.logDebug('[LifecycleObserver] Disposed', level: 'INFO');
+   }
+   return true;
+ }());
```

#### didChangeAppLifecycleState()のログをdebugレベルに変更
```diff
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
+   // v2: state変化時のみdebugログを出力（連打抑制）
    assert(() {
      if (!kDebugMode) {
        return true;
      }
-     CrashLogger.log(
+     CrashLogger.logDebug(
        '[LifecycleObserver] App lifecycle changed: $state',
        level: 'INFO',
      );
      return true;
    }());
```

### 3. `after_app/lib/main.dart`

#### kEnableTraceLogsフラグの追加
```dart
// v2: Traceログを有効にするか（デフォルトはfalse、明示的にtrueにした時のみtraceログが出る）
const bool kEnableTraceLogs = false;
```

#### Traceログ有効化の処理追加
```dart
// v2: Traceログが有効な場合のみログレベルを上げる
assert(() {
  if (!kDebugMode) {
    return true;
  }
  if (kEnableTraceLogs) {
    CrashLogger.setLogLevel(LogLevel.trace);
  }
  return true;
}());
```

#### タイマー開始ログをlogInfoに変更
```diff
- await CrashLogger.log('[main] Debug timers started (heartbeat + service diagnostics)', level: 'INFO');
+ await CrashLogger.logInfo('[main] Debug timers started (heartbeat + service diagnostics)', level: 'INFO');
```

## 契約(v2)が成立している理由

### ✅ 1. ログレベルの導入
- **LogLevel enum**: `info`（デフォルト）、`debug`、`trace`の3段階
- **初期値はinfo**: デフォルトではinfoレベルのみ出力
- **setLogLevel()**: debugビルド限定でログレベルを変更可能

### ✅ 2. Heartbeatログの隔離
- **traceレベルに変更**: `logTrace()`を使用
- **通常は出力されない**: `kEnableTraceLogs=false`（デフォルト）では出力されない
- **明示的にONにした時のみ**: `kEnableTraceLogs=true`にした時のみ出力

### ✅ 3. debug時でもデフォルトはinfoのみ
- **初期値はinfo**: `_currentLevel = LogLevel.info`
- **traceは明示ONの時のみ**: `kEnableTraceLogs=true`の時だけ`setLogLevel(LogLevel.trace)`を呼ぶ

### ✅ 4. Release/Profileビルドでの沈黙（v1維持）
- **`assert(() { ...; return true; }());`形式**: Releaseビルドではコードが削除される
- **stopAllTimers()は必ず実行**: `assert()`の外で呼び出し、Releaseビルドでも確実に実行

### ✅ 5. ログ連打抑制の強化
- **`_logOnce()`を拡張**: debugレベルのログとして出力
- **同一state連打抑制**: `lifecycle_inactive_stopping`、`lifecycle_resumed_resuming`など、同一キーで初回のみ
- **同一開始ログ連打抑制**: `startHeartbeat()`と`startServiceDiagnostics()`で、多重起動時はログを出さない

### ✅ 6. Timer生成の一元化（v1維持）
- **`crash_logger.dart`のみ**: `Timer.periodic()`の呼び出しは`startHeartbeat()`と`startServiceDiagnostics()`内のみ
- **`main.dart`と`app_lifecycle_observer.dart`**: Timerを直接作成せず、`CrashLogger.startXXX()`を呼ぶだけ

### ✅ 7. startの冪等性（v1維持）
- **`_heartbeatTimer != null`チェック**: 既に起動済みなら早期リターン
- **`_serviceDiagnosticsTimer != null`チェック**: 既に起動済みなら早期リターン
- **多重起動時はログも出さない**: コメントで明記

### ✅ 8. stopの安全性（v1維持）
- **`stopHeartbeat()`**: `cancel()`後に必ず`null`を代入
- **`stopServiceDiagnostics()`**: `cancel()`後に必ず`null`を代入
- **`stopAllTimers()`**: 両方のタイマーを確実に停止

### ✅ 9. 停止経路の完全性（v1維持）
- **`detached`時**: `CrashLogger.stopAllTimers()`を呼び出し（Releaseビルドでも確実に実行）
- **`dispose()`時**: `CrashLogger.stopAllTimers()`を呼び出し（Releaseビルドでも確実に実行）
- **Isolate終了時**: `CrashLogger.stopAllTimers()`を呼び出し（Releaseビルドでも確実に実行）

## 動作確認手順

### 1. デフォルト（kEnableTraceLogs=false）での確認
```bash
flutter run -d windows --vm-service-port=0 --disable-service-auth-codes
```

**期待される動作:**
- `[HEARTBEAT]` が**出力されない**（traceレベルなので）
- `[CrashLogger] Heartbeat timer started` が**出力されない**（debugレベルなので）
- `[CrashLogger] Service diagnostics timer started` が**出力されない**（debugレベルなので）
- `[main] Debug timers started` が**出力される**（infoレベルなので）
- `[SERVICE_CHECK]` が**出力される**（infoレベルなので）

### 2. Traceログ有効（kEnableTraceLogs=true）での確認
```dart
// main.dart
const bool kEnableTraceLogs = true;  // ← 変更
```

```bash
flutter run -d windows --vm-service-port=0 --disable-service-auth-codes
```

**期待される動作:**
- `[HEARTBEAT]` が**10秒ごとに出力される**（traceレベルが有効なので）
- `[CrashLogger] Heartbeat timer started` が**1回だけ出力される**（debugレベルが有効なので）
- `[CrashLogger] Service diagnostics timer started` が**1回だけ出力される**（debugレベルが有効なので）

### 3. 多重起動防止の確認
- Hot restartしても、タイマーが1本だけ動作する
- `[CrashLogger] Heartbeat timer started` が複数回出ない（多重起動時はログも出さない）

### 4. Releaseビルドでの確認
```bash
flutter build windows --release
```

**期待される動作:**
- `[HEARTBEAT]` と `[SERVICE_CHECK]` が一切出力されない
- タイマー関連のコードが実行されない
- `stopAllTimers()`は確実に実行される（assert外なので）

## v1→v2の差分サマリー

| 項目 | v1 | v2 |
|------|----|----|
| ログレベル | なし（すべて出力） | info/debug/traceの3段階 |
| Heartbeatログ | 常に出力 | traceレベル（デフォルトでは出力されない） |
| 開始ログ | infoレベル | debugレベル（デフォルトでは出力されない） |
| ログ連打抑制 | `_logOnce()`で初回のみ | `_logOnce()`をdebugレベルに変更 |
| Traceログ有効化 | なし | `kEnableTraceLogs`フラグで制御 |
| タイマー管理 | 一元化（v1維持） | 一元化（v1維持） |
| 停止経路 | 完全性保証（v1維持） | 完全性保証（v1維持） |

## 注意点

1. **後方互換性**: `log()`メソッドは`logInfo()`を呼ぶように実装しており、既存のコードはそのまま動作します
2. **デフォルト動作**: `kEnableTraceLogs=false`（デフォルト）では、Heartbeatログは出力されません
3. **ログレベルの変更**: `setLogLevel()`はdebugビルド限定で、releaseビルドでは無視されます
4. **stopAllTimers()の実行**: Releaseビルドでも確実に実行されるよう、`assert()`の外で呼び出しています
