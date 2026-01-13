# ログ抑制とタイマー管理の改善

## 修正差分

### 1. `after_app/lib/core/crash_logger.dart` - Heartbeatの改善

**変更箇所**: `startHeartbeat()`メソッド

**変更前:**
```dart
/// ハートビートを開始（1秒ごとにプロセス生存確認ログを出力）
static void startHeartbeat() {
  _heartbeatTimer?.cancel();
  _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
    log(
      '[HEARTBEAT] pid=$processId timestamp=${DateTime.now().toIso8601String()}',
      level: 'HEARTBEAT',
    );
  });
}
```

**変更後:**
```dart
/// ハートビートを開始（debugビルド限定、10秒ごとにプロセス生存確認ログを出力）
static void startHeartbeat() {
  // 既に起動している場合は何もしない（多重起動防止）
  if (_heartbeatTimer != null) {
    return;
  }
  
  // debugビルド限定
  if (!kDebugMode) {
    return;
  }
  
  _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
    log(
      '[HEARTBEAT] pid=$processId timestamp=${DateTime.now().toIso8601String()}',
      level: 'HEARTBEAT',
    );
  });
}
```

**変更内容:**
- ✅ `kDebugMode`限定に変更
- ✅ 間隔を1秒→10秒に変更
- ✅ 多重起動防止: `_heartbeatTimer != null`チェックで早期リターン

---

### 2. `after_app/lib/main.dart` - Service diagnosticsの改善

**変更箇所**: VM Service connection diagnosticsの起動部分

**変更前:**
```dart
// Start heartbeat to track process survival
CrashLogger.startHeartbeat();
await CrashLogger.log('[main] Heartbeat started', level: 'INFO');

// Start VM Service connection diagnostics (定期チェック)
Timer.periodic(const Duration(seconds: 10), (timer) async {
  try {
    final serviceInfo = await developer.Service.getInfo();
    if (serviceInfo.serverUri != null) {
      final vmServiceUrl = 'ws://localhost:${serviceInfo.serverUri!.port}${serviceInfo.serverUri!.path}ws';
      final vmServiceHttpUrl = 'http://localhost:${serviceInfo.serverUri!.port}${serviceInfo.serverUri!.path}';
      await CrashLogger.log(
        '[SERVICE_CHECK] VM Service is alive\n'
        '[SERVICE_CHECK] URL: $vmServiceHttpUrl\n'
        '[SERVICE_CHECK] WebSocket: $vmServiceUrl',
        level: 'INFO',
      );
    } else {
      await CrashLogger.log('[SERVICE_CHECK] VM Service not available', level: 'WARNING');
    }
  } catch (e, stack) {
    await CrashLogger.logException(e, stack, context: 'Service connection check');
    await CrashLogger.log(
      '[SERVICE_CHECK] Connection lost! Check log file for VM Service URL to reconnect.',
      level: 'ERROR',
    );
  }
});
await CrashLogger.log('[main] Service diagnostics started', level: 'INFO');
```

**変更後:**
```dart
// Start heartbeat to track process survival (debugビルド限定)
if (kDebugMode) {
  CrashLogger.startHeartbeat();
  await CrashLogger.log('[main] Heartbeat started (debug mode)', level: 'INFO');
}

// Start VM Service connection diagnostics (debugビルド限定、30秒ごと)
Timer? serviceCheckTimer;
if (kDebugMode) {
  serviceCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
    try {
      final serviceInfo = await developer.Service.getInfo();
      if (serviceInfo.serverUri != null) {
        final vmServiceUrl = 'ws://localhost:${serviceInfo.serverUri!.port}${serviceInfo.serverUri!.path}ws';
        final vmServiceHttpUrl = 'http://localhost:${serviceInfo.serverUri!.port}${serviceInfo.serverUri!.path}';
        await CrashLogger.log(
          '[SERVICE_CHECK] VM Service is alive\n'
          '[SERVICE_CHECK] URL: $vmServiceHttpUrl\n'
          '[SERVICE_CHECK] WebSocket: $vmServiceUrl',
          level: 'INFO',
        );
      } else {
        await CrashLogger.log('[SERVICE_CHECK] VM Service not available', level: 'WARNING');
      }
    } catch (e, stack) {
      await CrashLogger.logException(e, stack, context: 'Service connection check');
      await CrashLogger.log(
        '[SERVICE_CHECK] Connection lost! Check log file for VM Service URL to reconnect.',
        level: 'ERROR',
      );
    }
  });
  await CrashLogger.log('[main] Service diagnostics started (debug mode)', level: 'INFO');
  
  // AppLifecycleObserverにタイマーを登録して、detached時に停止できるようにする
  AppLifecycleObserver.registerServiceCheckTimer(serviceCheckTimer);
}
```

**変更内容:**
- ✅ `kDebugMode`限定に変更
- ✅ 間隔を10秒→30秒に変更
- ✅ タイマーを変数に保持し、`AppLifecycleObserver`に登録して停止可能に

---

### 3. `after_app/lib/core/app_lifecycle_observer.dart` - タイマー停止の実装

**変更箇所**: 
- `_serviceCheckTimer`フィールドの追加
- `registerServiceCheckTimer()`メソッドの追加
- `didChangeAppLifecycleState()`でのタイマー停止
- `dispose()`でのタイマー停止

**変更前:**
```dart
class AppLifecycleObserver with WidgetsBindingObserver {
  static AppLifecycleObserver? _instance;
  static RawReceivePort? _exitPort;
  
  // ...
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    CrashLogger.log(
      '[LifecycleObserver] App lifecycle changed: $state',
      level: 'INFO',
    );
    
    if (state == AppLifecycleState.detached) {
      CrashLogger.log(
        '[LifecycleObserver] App is being detached - termination imminent',
        level: 'WARNING',
      );
      CrashLogger.logShutdown(exitCode: 0);
    }
  }
  
  static void dispose() {
    if (_instance != null) {
      WidgetsBinding.instance.removeObserver(_instance!);
      _instance = null;
      _exitPort?.close();
      _exitPort = null;
      CrashLogger.log('[LifecycleObserver] Disposed', level: 'INFO');
    }
  }
}
```

**変更後:**
```dart
class AppLifecycleObserver with WidgetsBindingObserver {
  static AppLifecycleObserver? _instance;
  static RawReceivePort? _exitPort;
  static Timer? _serviceCheckTimer;  // 追加
  
  // ...
  
  /// Service diagnostics タイマーを登録（detached時に停止するため）
  static void registerServiceCheckTimer(Timer timer) {  // 追加
    _serviceCheckTimer = timer;
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    CrashLogger.log(
      '[LifecycleObserver] App lifecycle changed: $state',
      level: 'INFO',
    );
    
    if (state == AppLifecycleState.detached) {
      CrashLogger.log(
        '[LifecycleObserver] App is being detached - termination imminent',
        level: 'WARNING',
      );
      // タイマーを停止（追加）
      CrashLogger.stopHeartbeat();
      _serviceCheckTimer?.cancel();
      _serviceCheckTimer = null;
      CrashLogger.logShutdown(exitCode: 0);
    }
  }
  
  static void dispose() {
    if (_instance != null) {
      WidgetsBinding.instance.removeObserver(_instance!);
      _instance = null;
      _exitPort?.close();
      _exitPort = null;
      _serviceCheckTimer?.cancel();  // 追加
      _serviceCheckTimer = null;     // 追加
      CrashLogger.log('[LifecycleObserver] Disposed', level: 'INFO');
    }
  }
}
```

**変更内容:**
- ✅ `_serviceCheckTimer`フィールドを追加
- ✅ `registerServiceCheckTimer()`メソッドを追加
- ✅ `AppLifecycleState.detached`時に両方のタイマーを停止
- ✅ `dispose()`でもタイマーを停止

---

### 4. `after_app/lib/core/notification.dart` - 変更なし

**確認結果:**
- 既に`_logOnce()`メソッドで初回のみログ出力されているため、変更不要
- `scheduleNotificationForMessage()`と`scheduleNotificationsForDate()`の両方で`_logOnce('notificationsScheduleSkippedDesktop', ...)`を使用

---

## 実装状況の確認

### ✅ 1. debugビルド限定
- Heartbeat: `kDebugMode`チェックで実装済み
- Service diagnostics: `kDebugMode`チェックで実装済み

### ✅ 2. 間隔の変更
- Heartbeat: 1秒→10秒に変更済み
- Service diagnostics: 10秒→30秒に変更済み

### ✅ 3. 多重起動防止
- Heartbeat: `_heartbeatTimer != null`チェックで実装済み
- Service diagnostics: `kDebugMode`チェックとタイマー登録で管理

### ✅ 4. タイマーの確実な停止
- `AppLifecycleState.detached`時に両方のタイマーを停止
- `dispose()`でもタイマーを停止

### ✅ 5. NotificationServiceのログ抑制
- 既に`_logOnce()`で初回のみログ出力されているため、変更不要

---

## 効果

1. **ログ出力の削減**
   - Heartbeat: 1秒→10秒（約90%削減）
   - Service diagnostics: 10秒→30秒（約67%削減）
   - Releaseビルドでは両方とも無効化

2. **多重起動防止**
   - Heartbeat: `_heartbeatTimer != null`チェックで防止
   - Service diagnostics: `kDebugMode`チェックとタイマー登録で管理

3. **タイマーの確実な停止**
   - `AppLifecycleState.detached`時に両方のタイマーを停止
   - `dispose()`でもタイマーを停止

4. **NotificationService**
   - 既に`_logOnce()`で初回のみログ出力されているため、変更不要

