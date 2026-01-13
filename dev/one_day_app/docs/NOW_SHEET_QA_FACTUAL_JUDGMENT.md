# NowSheet QA判定結果（事実ベース）

## テスト条件
- **TestStart**: 2026-01-11 08:49:20
- **OS**: Windows
- **Exit code**: 3

---

## 1) 総合判定

### A. 二重送信防止
**判定**: **不明（観測不足）**

### B. dispose後setState防止
**判定**: **PASS**

### C. sent→input復帰の安定
**判定**: **FAIL**

---

## 2) 根拠ログ（最小引用）

### A. 二重送信防止

**確認されたログ（事実）**:
- `[2026-01-11T08:49:45.357282] [DEBUG] [NowSheet] _handleSubmit: START submitting source=button sessionId=1768088985351278`（**1回**）

**欠落ログ（事実）**:
- `[MessageRepo] SAVED`: **0回**（期待: 1回）
- `[NowSheet] _handleSubmit: BLOCKED (already submitting)`: **0回**（期待: 9回以上）
- `[NowSheet] _handleSubmit called`: **0回**

**判定理由**: `START submitting` が1回のみであることは確認できるが、`[MessageRepo] SAVED` ログがログファイルに記録されていないため、実害（DBへの2件保存）の有無を確認できない。

---

### B. dispose後setState防止

**確認されたログ（事実）**:
- `setState() called after dispose` エラー: **0回**（期待: 0回）
- `[2026-01-11T08:49:46.505736] [DEBUG] [NowSheet] Windows: _onSentResetTimer STARTED sessionId=1768088985351278`
- `[2026-01-11T08:49:50.369201] [DEBUG] [NowSheet] Windows: reset completed, back to input screen sessionId=1768088985351278`

**欠落ログ（事実）**:
- `[NowSheet] dispose: _sentResetTimer cancelled`: **0回**（出れば強いが、無くても即FAILではない）

**判定理由**: `setState() called after dispose` エラーが1回も記録されていない。dispose後のタイマー実行（`_onSentResetTimer STARTED`）が記録されているが、エラーは発生していない。

---

### C. sent→input復帰の安定

**確認されたログ（事実）**:
- `[2026-01-11T08:49:50.369201] [DEBUG] [NowSheet] Windows: reset completed, back to input screen sessionId=1768088985351278`（**1回**、期待: 10回）

**欠落ログ（事実）**:
- `[NowSheet] _handleSubmit: SUCCESS`: **0回**（期待: 10回）
- `[NowSheet] Windows: sent UI shown`: **0回**（期待: 10回）
- `[NowSheet] Windows: _sentResetTimer started`: **0回**（期待: 10回）
- `[NowSheet] _updateUiState: state=input`: **0回**（期待: 10回）

**判定理由**: `reset completed` が1回のみ記録されている。期待される10回の連続送信ログが記録されていない。

---

## 3) 不足している観測

1. **`[MessageRepo] SAVED` ログ**: `debugPrint` を使用しており、CrashLoggerのログファイルに記録されていない（`message_repo.dart:17`）
2. **`[NowController] submit: 成功` ログ**: 同様に `debugPrint` を使用（`now_controller.dart:101`）
3. **連続送信テストのログ**: 10回の連続送信が実行されていないか、ログが記録されていない

---

## 4) 原因カテゴリ（FAILがある場合）

### C. sent→input復帰の安定
**原因カテゴリ**: **手順未実施**

**理由**: 連続送信テストが実行されていないか、1回のみ実行されている。期待される10回の連続送信が実施されていない。

---

## 5) 次アクション（最大2つ、具体的に）

### アクション1: `message_repo.dart` と `now_controller.dart` の `debugPrint` を `CrashLogger` に置き換え

**内容**:
- `message_repo.dart:17` の `debugPrint('[MessageRepo] SAVED ...')` を `CrashLogger.logInfo('[MessageRepo] SAVED ...')` に変更
- `now_controller.dart:79, 101` の `debugPrint('[NowController] submit: ...')` を `CrashLogger.logDebug('[NowController] submit: ...')` に変更

**理由**: A項目の判定のために `[MessageRepo] SAVED` ログをログファイルに記録する必要がある。

---

### アクション2: 連続送信テストを10回完全実行

**内容**:
- アクション1の修正後にアプリを再起動
- NowSheetで10回連続送信を実行（各送信で入力欄が復帰するまで待つ）
- `scripts/test_now_sheet.ps1` で以下を確認:
  - `_handleSubmit: SUCCESS` が10回
  - `Windows: sent UI shown` が10回
  - `Windows: _sentResetTimer started` が10回
  - `Windows: reset completed, back to input screen` が10回
  - `_updateUiState: state=input` が10回

**理由**: C項目の判定のために10回の連続送信ログが必要。

---

## 補足: 確認されたコード実装（事実）

- `_isSubmitting` フラグによる二重送信防止（`now_sheet.dart:68, 952-955, 967, 980`）
- `_sentResetTimer` によるタイマー管理と `dispose` でのキャンセル（`now_sheet.dart:69, 111-115, 1019-1027`）
- `safeSetState` ヘルパーによる `mounted` チェック（`now_sheet.dart:72-78, 1087`）
- `addPostFrameCallback` 内での `mounted` チェック（`now_sheet.dart:1054-1059`）

以上、すべて事実ベースで評価しています。
