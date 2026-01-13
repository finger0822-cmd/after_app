# ログ診断結果

## 診断日時
2026-01-11

## 対象ログファイル
`C:\Users\taker\AppData\Local\after_app\logs\crash_2026-01-11T08-49-19.600202.log`

---

## 段階1: ログファイルの先頭/末尾確認

### 確認結果

**ログファイルの統計情報（事実）**:
- **総行数**: 48行（非常に少ない）
- **INFO行数**: 16行
- **DEBUG行数**: 6行
- **NowSheet行数**: 6行
- **NowController行数**: **0行**（期待: 1行以上）
- **MessageRepo行数**: **0行**（期待: 1行以上）

**確認されたログ（事実）**:
- `[2026-01-11T08:49:45.357282] [DEBUG] [NowSheet] _handleSubmit: START submitting source=button sessionId=1768088985351278`
- `[2026-01-11T08:49:50.369201] [DEBUG] [NowSheet] Windows: reset completed, back to input screen sessionId=1768088985351278`

**欠落ログ（事実）**:
- `[NowController] submit: 開始` → **0件**
- `[NowController] submit: 成功` → **0件**
- `[MessageRepo] SAVED` → **0件**

### 判定

**ログファイルにはログが記録されているが、NowControllerとMessageRepoのログが記録されていない**。

---

## 段階2: 文字列一致の確認

### 2-A) MessageRepo 文字列の検索

**結果**: **0件**（見つかりません）

### 2-B) SAVED 文字列の検索

**結果**: **0件**（見つかりません）

### 2-C) NowController 文字列の検索

**結果**: **0件**（見つかりません）

### 判定

**MessageRepo、SAVED、NowControllerのいずれの文字列もログファイルに存在しない**。

---

## 段階3: コード確認

### message_repo.dart

**確認結果（事実）**:
- 17行目: `CrashLogger.logInfo('[MessageRepo] SAVED ...')`（正しく修正されている）
- `debugPrint` の使用: **なし**（削除済み）

### now_controller.dart

**確認結果（事実）**:
- 63行目: `CrashLogger.logDebug('[NowController] submit: 開始 ... → 失敗（空文字）')`
- 71行目: `CrashLogger.logDebug('[NowController] submit: 開始 ... → 失敗（文字数超過）')`
- 79行目: `CrashLogger.logDebug('[NowController] submit: 開始 ...')`
- 97行目: `CrashLogger.logDebug('[NowController] notification schedule error: ...')`
- 101行目: `CrashLogger.logDebug('[NowController] submit: 成功 ...')`
- 107行目: `CrashLogger.logDebug('[NowController] submit: 失敗 ...')`
- `debugPrint` の使用: **なし**（削除済み）

### 判定

**コードは正しく修正されている（CrashLogger使用、debugPrint削除済み）**。

---

## 原因の特定

### 可能性が高い原因

**CrashLoggerに切り替えたコードが実行バイナリに反映されていない可能性が高い**。

**理由（事実ベース）**:
1. コードは正しく修正されている（CrashLogger使用）
2. しかし、ログファイルにはNowController/MessageRepoのログが記録されていない（0件）
3. ログファイルは48行しかなく、INFO/DEBUGログは記録されている
4. NowSheetのログは記録されている（`_handleSubmit: START submitting` など）

**結論**: このログファイルは、CrashLogger変更前のコードで実行されたテスト結果である可能性が高い。

---

## 次アクション（優先順）

### アクション1: flutter clean を実行して再ビルド

**内容**:
```powershell
cd C:\Users\taker\develop\flutter\dev\after_app
flutter clean
flutter pub get
flutter run -d windows
```

**理由**: CrashLoggerに切り替えたコードが実行バイナリに反映されていない可能性が高いため、クリーンビルドが必要。

---

### アクション2: 新しいテストを実行

**内容**:
1. flutter clean後にアプリを再起動
2. 新しいTestStart時刻を記録（`$TestStart = Get-Date`）
3. テストを実行（二重送信、連続送信、dispose耐性）
4. `scripts/test_now_sheet.ps1 -TestStart $TestStart` を実行してログを確認

**理由**: 修正後のコードで実行されたログを確認する必要がある。

---

## 補足: 確認された事実

### コード修正状況
- ✅ `message_repo.dart`: `CrashLogger.logInfo` 使用（修正済み）
- ✅ `now_controller.dart`: `CrashLogger.logDebug` 使用（修正済み）
- ✅ `debugPrint` の使用: なし（削除済み）

### ログファイルの状態
- ✅ CrashLoggerは動作している（INFO/DEBUGログが記録されている）
- ❌ NowController/MessageRepoのログが記録されていない（0件）
- ✅ NowSheetのログは記録されている（6行）

### 推測
このログファイル（`crash_2026-01-11T08-49-19.600202.log`）は、CrashLogger変更前のコードで実行されたテスト結果である可能性が高い。
