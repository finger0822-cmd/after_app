# NowSheet実動作テスト結果評価レポート

## 評価日時
2026-01-11

## 評価者
QA/検証責任者

## テスト条件
- **OS**: Windows 10 Home 10.0 (Build 26200)
- **Flutter**: デバッグビルド
- **テスト開始時刻**: 2026-01-11 08:49:20
- **ログファイル**: `crash_2026-01-11T08-49-19.600202.log`
- **テストスクリプト exit code**: 3

---

## 1. 合否判定（PASS/FAIL）と根拠ログ行

### 判定: **FAIL**（Exit code: 3）

**根拠ログ行**:
- `[2026-01-11T08:49:45.357282] [DEBUG] [NowSheet] _handleSubmit: START submitting source=button sessionId=1768088985351278`
- `[2026-01-11T08:49:45.419282] [DEBUG] [NowSheet] Windows: BEFORE refresh() call sessionId=1768088985351278`
- `[2026-01-11T08:49:45.502284] [DEBUG] [NowSheet] Windows: existing timer cancelled (if any) sessionId=1768088985351278`
- `[2026-01-11T08:49:46.505736] [DEBUG] [NowSheet] Windows: _onSentResetTimer STARTED sessionId=1768088985351278`
- `[2026-01-11T08:49:50.369201] [DEBUG] [NowSheet] Windows: reset completed, back to input screen sessionId=1768088985351278`

**欠落ログ（事実）**:
- `[MessageRepo] SAVED` ログがログファイルに記録されていない（`debugPrint` 使用のため）
- `[NowController] submit: 成功` ログがログファイルに記録されていない（`debugPrint` 使用のため）
- `[NowSheet] _handleSubmit called` ログがログファイルに記録されていない（スタックトレースのみ記録）
- `[NowSheet] _handleSubmit: SUCCESS` ログがログファイルに記録されていない
- `[NowSheet] Windows: sent UI shown` ログがログファイルに記録されていない

---

## 2. 3大要件の評価

### A. 二重送信防止

**判定: 不明（評価不可）**

**根拠ログ行**:
- `[2026-01-11T08:49:45.357282] [DEBUG] [NowSheet] _handleSubmit: START submitting source=button sessionId=1768088985351278`（1回のみ）

**判定理由（事実ベース）**:
- `START submitting` ログが1回のみ記録されている（事実）
- しかし、`[MessageRepo] SAVED` ログがログファイルに記録されていないため、**実際にデータが保存されたかどうかを確認できない**（事実）
- `BLOCKED (already submitting)` ログも記録されていない（事実：二重送信が発生していない、またはログが記録されていない）
- **結論**: `START submitting` が1回のみであることは確認できるが、実害（DBへの2件保存）の有無を確認できないため、**評価不可**

---

### B. dispose耐性

**判定: PASS**

**根拠ログ行**:
- `setState() called after dispose` エラーがログファイルに記録されていない（事実）

**判定理由（事実ベース）**:
- `setState() called after dispose` エラーが1回も記録されていない（事実）
- `timer cancelled log` は記録されていないが、これは `dispose` が呼ばれていないため（正常）
- **結論**: dispose後のsetStateエラーは発生していない。**PASS**

---

### C. sent→input復帰

**判定: FAIL（不完全実行）**

**根拠ログ行**:
- `[2026-01-11T08:49:46.505736] [DEBUG] [NowSheet] Windows: _onSentResetTimer STARTED sessionId=1768088985351278`
- `[2026-01-11T08:49:50.369201] [DEBUG] [NowSheet] Windows: reset completed, back to input screen sessionId=1768088985351278`（1回のみ）

**判定理由（事実ベース）**:
- `reset completed` ログが1回のみ記録されている（期待: 10回、事実: 1回）
- `SUCCESS` ログが0回（期待: 10回、事実: 0回）
- `sent UI shown` ログが0回（期待: 10回、事実: 0回）
- `timer started` ログが0回（期待: 10回、事実: 0回）
- **結論**: 連続送信テストが実行されていないか、ログが記録されていない。**FAIL（テスト未完了）**

---

## 3. 潜在リスク（異常がない場合でも）

### リスク1: `debugPrint` ログがログファイルに記録されない

**事実**:
- `[MessageRepo] SAVED` は `debugPrint` を使用（`message_repo.dart:17`）
- `[NowController] submit: 成功` は `debugPrint` を使用（`now_controller.dart:101`）
- `debugPrint` は標準出力にのみ出力され、CrashLoggerのログファイルには記録されない

**影響**:
- 実害（DBへの2件保存）の確認ができない
- テストスクリプトが `[MessageRepo] SAVED` を検索しても見つからない

**最小修正案**:
```dart
// message_repo.dart:17
// 変更前
debugPrint('[MessageRepo] SAVED id=${message.id} ... sessionId=$auditSessionId');

// 変更後
CrashLogger.logInfo('[MessageRepo] SAVED id=${message.id} ... sessionId=$auditSessionId');
```

同様に、`now_controller.dart` の `debugPrint` も `CrashLogger.logInfo` または `CrashLogger.logDebug` に変更する。

---

### リスク2: `_handleSubmit called` ログが記録されない

**事実**:
- `[NowSheet] _handleSubmit called` ログは `CrashLogger.logDebug` を使用（`now_sheet.dart:947`）
- しかし、ログファイルには記録されていない
- スタックトレースのみ記録されている（`now_sheet.dart:948`）

**影響**:
- 二重送信の検出が困難（`_handleSubmit called` の回数で判定できない）

**確認事項**:
- `CrashLogger.logDebug` が正しく呼ばれているか
- ログレベルが `debug` 以上に設定されているか
- `_writeLog` が非同期で実行されるため、ログがファイルに書き込まれる前にアプリが終了した可能性

**最小修正案**:
- `_handleSubmit called` ログを `logInfo` に変更（確実に記録される）

---

### リスク3: タイマー実行時のライフサイクル状態変更による遅延

**事実**:
- `[2026-01-11T08:49:46.505736] [DEBUG] [NowSheet] Windows: _onSentResetTimer STARTED sessionId=1768088985351278`
- `[2026-01-11T08:49:50.342754] [INFO] [LifecycleObserver] App is inactive - stopping timers`
- `[2026-01-11T08:49:50.369201] [DEBUG] [NowSheet] Windows: reset completed, back to input screen sessionId=1768088985351278`

**影響**:
- タイマー実行中（`08:49:46`）にアプリが `inactive` 状態（`08:49:50`）になり、タイマーが停止された可能性
- ただし、`reset completed` ログが記録されているため、タイマーは正常に実行された
- しかし、`inactive` 状態でタイマーが停止される場合、`reset completed` が実行されないリスクがある

**最小修正案**:
- `AppLifecycleObserver` で `inactive` 時に `stopAllTimers()` を呼んでいるが、これは Heartbeat/Service diagnostics 用のタイマーのみ
- `NowSheet` の `_sentResetTimer` は `AppLifecycleObserver` の管理外（問題なし）
- **修正不要**（現在の実装で問題なし）

---

## 4. 次に実施すべきテスト（最大2つ）

### テスト1: `debugPrint` を `CrashLogger` に置き換えた後の再テスト

**内容**:
- `message_repo.dart` と `now_controller.dart` の `debugPrint` を `CrashLogger.logInfo` または `CrashLogger.logDebug` に置き換え
- アプリを再起動
- 同じテスト（二重送信、連続送信）を再実行
- `[MessageRepo] SAVED` と `[NowController] submit: 成功` ログがログファイルに記録されることを確認

**判定基準**:
- `[MessageRepo] SAVED` ログが1回のみ記録される（二重送信テスト）
- `[MessageRepo] SAVED` ログが10回記録される（連続送信テスト）

---

### テスト2: 連続送信テストの完全実行

**内容**:
- テスト1で修正後に、連続送信テストを10回完全に実行
- 各送信で以下を確認:
  - `_handleSubmit: START submitting` → `SUCCESS` → `sent UI shown` → `timer started` → `reset completed` → `state=input`
- `scripts/test_now_sheet.ps1` で exit code 0 を確認

**判定基準**:
- `SUCCESS` ログが10回
- `sent UI shown` ログが10回
- `timer started` ログが10回
- `reset completed` ログが10回
- `state=input` ログが10回

---

## 5. 総合評価

### 現時点での評価: **FAIL（テスト未完了）**

**理由（事実ベース）**:
1. ログファイルに `[MessageRepo] SAVED` が記録されていないため、実害確認ができない（`debugPrint` 使用のため）
2. 連続送信テストが実行されていないか、不完全（期待10回、実際1回）
3. dispose耐性は確認できた（`setState() called after dispose` エラーなし）

### 次のアクション
1. `debugPrint` を `CrashLogger` に置き換え（必須）
2. 修正後に再テスト実行（必須）
3. 連続送信テストを10回完全実行（必須）

---

## 補足: 確認された事実

### ログファイルに記録されているログ
- `_handleSubmit: START submitting` (1回)
- `Windows: BEFORE refresh() call` (1回)
- `Windows: existing timer cancelled` (1回)
- `Windows: _onSentResetTimer STARTED` (1回)
- `Windows: reset completed` (1回)

### ログファイルに記録されていないログ（`debugPrint` 使用）
- `[MessageRepo] SAVED`
- `[NowController] submit: 開始`
- `[NowController] submit: 成功`
- `[NowSheet] _handleSubmit called`（スタックトレースのみ記録）
- `[NowSheet] _handleSubmit: SUCCESS`
- `[NowSheet] Windows: sent UI shown`

### ログレベル設定
- `main.dart:171` で `CrashLogger.setLogLevel(LogLevel.debug)` が設定されている（修正後）
- `CrashLogger.logDebug` は `_shouldLog(LogLevel.debug)` で判定され、`currentLevel = debug` の場合、出力される（事実）

### タイマー管理
- `AppLifecycleObserver` の `stopAllTimers()` は Heartbeat/Service diagnostics 用タイマーのみ停止
- `NowSheet` の `_sentResetTimer` は `AppLifecycleObserver` の管理外（問題なし）

---

## 参照
- テストスクリプト: `scripts/test_now_sheet.ps1`
- ログファイル: `C:\Users\taker\AppData\Local\after_app\logs\crash_2026-01-11T08-49-19.600202.log`
- テスト手順: `docs/NOW_SHEET_TEST_PROCEDURE.md`
