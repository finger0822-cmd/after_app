# ライフサイクル契約(v2) 最終検証結果

**検証日時**: [検証実施日を記載]  
**検証者**: [検証者名を記載]  
**検証環境**: Flutter Windows Desktop (Debug/Release)

---

## 検証対象

- CrashLogger（LogLevel v2設計）
- Heartbeat / Service diagnostics タイマー
- タイマー停止（detached / dispose / isolate exit）
- kEnableTraceLogs フラグ

---

## テスト1: kEnableTraceLogs = false（デフォルト）

### 検証条件

```dart
// main.dart
const bool kEnableTraceLogs = false;  // デフォルト値
```

**実行コマンド:**
```bash
flutter run -d windows --vm-service-port=0 --disable-service-auth-codes
```

**観測時間**: 起動後45秒間

### 判定ロジック

- **初期ログレベル**: `_currentLevel = LogLevel.info` (index=2)
- **Heartbeatログ**: `logTrace()` (trace=0) → `0 >= 2` → `false` → 出力されない
- **Service aliveログ**: `logDebug()` (debug=1) → `1 >= 2` → `false` → 出力されない

**実装箇所:**
- `crash_logger.dart:23`: `static LogLevel _currentLevel = LogLevel.info;`
- `crash_logger.dart:139`: `return messageLevel.index >= _currentLevel.index;`
- `crash_logger.dart:209`: `logTrace('[HEARTBEAT] ...')`
- `crash_logger.dart:253`: `await logDebug('[SERVICE_CHECK] VM Service is alive...')`

### 観測結果

**確認対象**: 標準出力 + ログファイル

| 項目 | 期待値 | 実測値 | 確認方法 |
|------|--------|--------|----------|
| `[HEARTBEAT]` | 0件 | [実測値を記載] | `grep -c "\[HEARTBEAT\]" crash_*.log` |
| `[SERVICE_CHECK] VM Service is alive` | 0件 | [実測値を記載] | `grep -c "VM Service is alive" crash_*.log` |

**証跡（ログファイル名）**:  
`crash_[YYYY-MM-DDTHH-mm-ss].log`  
（例: `crash_2024-01-15T14-30-45.log`）

**ログファイルパス**:  
Windows: `%LOCALAPPDATA%\after_app\logs\crash_*.log`

### 結論

- [ ] **PASS**: 実測値が期待値と一致
- [ ] **FAIL**: 実測値が期待値と不一致

**検証者署名**: _________________  
**検証日時**: _________________

---

## テスト2: kEnableTraceLogs = true

### 検証条件

```dart
// main.dart
const bool kEnableTraceLogs = true;  // ← 変更
```

**実行コマンド:**
```bash
flutter run -d windows --vm-service-port=0 --disable-service-auth-codes
```

**観測時間**: 起動後45秒間

### 判定ロジック

- **ログレベル設定**: `CrashLogger.setLogLevel(LogLevel.trace)` → `_currentLevel = LogLevel.trace` (index=0)
- **Heartbeatログ**: `logTrace()` (trace=0) → `0 >= 0` → `true` → 10秒周期で出力
- **Service aliveログ**: `logDebug()` (debug=1) → `1 >= 0` → `true` → 30秒周期で出力

**実装箇所:**
- `main.dart:171`: `CrashLogger.setLogLevel(LogLevel.trace);` (assert内、kEnableTraceLogs=true時のみ)
- `crash_logger.dart:207`: `Timer.periodic(const Duration(seconds: 10), ...)`
- `crash_logger.dart:242`: `Timer.periodic(const Duration(seconds: 30), ...)`

### 観測結果

**確認対象**: 標準出力 + ログファイル

| 項目 | 期待値 | 実測値 | 確認方法 |
|------|--------|--------|----------|
| `[HEARTBEAT]` | 4件以上（10秒周期） | [実測値を記載] | `grep -c "\[HEARTBEAT\]" crash_*.log` |
| `[SERVICE_CHECK] VM Service is alive` | 1件以上（30秒周期） | [実測値を記載] | `grep -c "VM Service is alive" crash_*.log` |

**タイミング確認:**
- 起動後10秒: `[HEARTBEAT]` 1回目
- 起動後20秒: `[HEARTBEAT]` 2回目
- 起動後30秒: `[HEARTBEAT]` 3回目 + `[SERVICE_CHECK] VM Service is alive` 1回目
- 起動後40秒: `[HEARTBEAT]` 4回目

**証跡（ログファイル名）**:  
`crash_[YYYY-MM-DDTHH-mm-ss].log`  
（例: `crash_2024-01-15T14-35-20.log`）

**ログファイルパス**:  
Windows: `%LOCALAPPDATA%\after_app\logs\crash_*.log`

### 結論

- [ ] **PASS**: 実測値が期待値と一致
- [ ] **FAIL**: 実測値が期待値と不一致

**検証者署名**: _________________  
**検証日時**: _________________

---

## テスト3: アプリ終了後の停止確認

### 検証条件

**実行コマンド:**
```bash
flutter run -d windows --vm-service-port=0 --disable-service-auth-codes
```

**終了操作**: アプリウィンドウを閉じる（または `Ctrl+C`）

**観測時間**: 終了操作後30秒間

### 判定ロジック

**停止経路（すべてassert外で実行）:**

1. **AppLifecycleState.detached**
   - `app_lifecycle_observer.dart:127-133`: `CrashLogger.stopAllTimers()` (assert外)
   - 実装: `if (state == AppLifecycleState.detached) { CrashLogger.stopAllTimers(); }`

2. **dispose()**
   - `app_lifecycle_observer.dart:83`: `CrashLogger.stopAllTimers()` (assert外)
   - 実装: `static void dispose() { ... CrashLogger.stopAllTimers(); }`

3. **isolate exit**
   - `app_lifecycle_observer.dart:31`: `CrashLogger.stopAllTimers()` (assert外)
   - 実装: `RawReceivePort((message) { ... CrashLogger.stopAllTimers(); });`

**stopAllTimers()の実装:**
- `crash_logger.dart:286-289`: `static void stopAllTimers() { stopHeartbeat(); stopServiceDiagnostics(); }`
- `crash_logger.dart:219-222`: `stopHeartbeat()` → `_heartbeatTimer?.cancel(); _heartbeatTimer = null;`
- `crash_logger.dart:280-283`: `stopServiceDiagnostics()` → `_serviceDiagnosticsTimer?.cancel(); _serviceDiagnosticsTimer = null;`

**Releaseビルドでの動作確認:**
- `stopAllTimers()`はassert外で実装されているため、Releaseビルドでも確実に実行される
- タイマーの停止処理（`cancel()`と`null`代入）はassert外で実行される

### 観測結果

**確認対象**: 標準出力 + ログファイル

| 項目 | 期待値 | 実測値 | 確認方法 |
|------|--------|--------|----------|
| 終了操作後の`[HEARTBEAT]` | 0件 | [実測値を記載] | 終了後30秒間のログを確認 |
| 終了操作後の`[SERVICE_CHECK]` | 0件 | [実測値を記載] | 終了後30秒間のログを確認 |

**検証手順:**
1. アプリ起動（`kEnableTraceLogs=true`推奨）
2. ログが出力されていることを確認
3. アプリ終了（ウィンドウを閉じる）
4. 終了時刻を記録
5. 終了後30秒間、ログファイルを監視
6. `[HEARTBEAT]`と`[SERVICE_CHECK]`の出力件数をカウント

**証跡（ログファイル名）**:  
`crash_[YYYY-MM-DDTHH-mm-ss].log`  
（例: `crash_2024-01-15T14-40-10.log`）

**ログファイルパス**:  
Windows: `%LOCALAPPDATA%\after_app\logs\crash_*.log`

**終了時刻**: [実測値を記載]  
**観測終了時刻**: [実測値を記載]

### 結論

- [ ] **PASS**: 終了後、ログが完全に停止（0件）
- [ ] **FAIL**: 終了後もログが出力される（残響あり）

**検証者署名**: _________________  
**検証日時**: _________________

---

## Releaseビルドでの動作確認（オプション）

### 検証条件

**実行コマンド:**
```bash
flutter build windows --release
# ビルド後、実行
```

**観測時間**: 起動後45秒間

### 判定ロジック

- **assert内の処理**: Releaseビルドでは削除される
  - `startHeartbeat()`: assert内 → Releaseでは実行されない
  - `startServiceDiagnostics()`: assert内 → Releaseでは実行されない
  - `setLogLevel()`: assert内 → Releaseでは実行されない

- **assert外の処理**: Releaseビルドでも確実に実行される
  - `stopAllTimers()`: assert外 → Releaseでも実行される
  - `stopHeartbeat()`: assert外 → Releaseでも実行される
  - `stopServiceDiagnostics()`: assert外 → Releaseでも実行される

### 観測結果

**確認対象**: 標準出力 + ログファイル

| 項目 | 期待値 | 実測値 | 確認方法 |
|------|--------|--------|----------|
| `[HEARTBEAT]` | 0件 | [実測値を記載] | Releaseビルドではタイマーが起動しない |
| `[SERVICE_CHECK]` | 0件 | [実測値を記載] | Releaseビルドではタイマーが起動しない |
| アプリ終了時の停止 | 正常動作 | [実測値を記載] | `stopAllTimers()`が実行されることを確認 |

### 結論

- [ ] **PASS**: Releaseビルドで期待通り動作
- [ ] **FAIL**: Releaseビルドで問題あり

**検証者署名**: _________________  
**検証日時**: _________________

---

## 最終判定

### 検証結果サマリー

| テスト | 結果 | 備考 |
|--------|------|------|
| テスト1: kEnableTraceLogs=false | [ ] PASS / [ ] FAIL | |
| テスト2: kEnableTraceLogs=true | [ ] PASS / [ ] FAIL | |
| テスト3: アプリ終了後の停止 | [ ] PASS / [ ] FAIL | |
| Releaseビルド確認（オプション） | [ ] PASS / [ ] FAIL | |

### 最終結論

**すべてのテストがPASSの場合のみ、以下を記載:**

---

## ✅ 契約(v2)は実戦配備OK

**検証完了日時**: [日時を記載]  
**最終承認者**: [承認者名を記載]  
**承認日時**: [日時を記載]

---

**注意事項:**
- このドキュメントは監査ログとして保存してください
- 実測値は必ず数値で記載してください（「出ない」ではなく「0件」）
- ログファイル名は必ず記載してください
- 検証者署名は必須です
