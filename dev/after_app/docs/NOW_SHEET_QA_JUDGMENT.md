# NowSheet QA判定結果

## テスト条件
- **TestStart**: 2026-01-11 08:49:20
- **OS**: Windows
- **デバイス**: Windows Desktop
- **Exit code**: 3

---

## A. 二重送信防止テスト

### 判定: **不明（判定不可）**

### 根拠ログ行
- `[2026-01-11T08:49:45.357282] [DEBUG] [NowSheet] _handleSubmit: START submitting source=button sessionId=1768088985351278`（**1回**）

### 欠落ログ（事実）
- `[MessageRepo] SAVED` ログ: **0回**（期待: 1回）
- `[NowSheet] _handleSubmit: BLOCKED (already submitting)` ログ: **0回**（期待: 9回以上）
- `[NowSheet] _handleSubmit called` ログ: **0回**

### 原因カテゴリ
**観測不足**: `[MessageRepo] SAVED` ログが `debugPrint` を使用しており、ログファイルに記録されていない。実害（DBへの2件保存）の有無を確認できない。

---

## B. dispose耐性テスト

### 判定: **PASS**

### 根拠ログ行
- `setState() called after dispose` エラー: **0回**（期待: 0回）

### 確認ログ（事実）
- `[2026-01-11T08:49:46.505736] [DEBUG] [NowSheet] Windows: _onSentResetTimer STARTED sessionId=1768088985351278`
- `[2026-01-11T08:49:50.369201] [DEBUG] [NowSheet] Windows: reset completed, back to input screen sessionId=1768088985351278`

### 判定理由
- `setState() called after dispose` エラーが1回も記録されていない（事実）
- dispose後のタイマー実行（`_onSentResetTimer STARTED`）が記録されているが、エラーは発生していない（事実）

---

## C. sent→input復帰テスト

### 判定: **FAIL**

### 根拠ログ行
- `[2026-01-11T08:49:50.369201] [DEBUG] [NowSheet] Windows: reset completed, back to input screen sessionId=1768088985351278`（**1回**、期待: 10回）

### 欠落ログ（事実）
- `[NowSheet] _handleSubmit: SUCCESS` ログ: **0回**（期待: 10回）
- `[NowSheet] Windows: sent UI shown` ログ: **0回**（期待: 10回）
- `[NowSheet] Windows: _sentResetTimer started` ログ: **0回**（期待: 10回）
- `[NowSheet] _updateUiState: state=input` ログ: **0回**（期待: 10回）

### 原因カテゴリ
**手順未実施**: 連続送信テストが実行されていないか、1回のみ実行されている。期待される10回の連続送信が実施されていない。

---

## 次のアクション（最大2つ）

### アクション1: `debugPrint` を `CrashLogger` に置き換え
**内容**: `message_repo.dart:17` の `debugPrint('[MessageRepo] SAVED ...')` を `CrashLogger.logInfo('[MessageRepo] SAVED ...')` に変更。同様に `now_controller.dart` の `debugPrint` も `CrashLogger.logDebug` または `CrashLogger.logInfo` に変更。

**理由**: A項目の判定のために `[MessageRepo] SAVED` ログをログファイルに記録する必要がある。

### アクション2: 連続送信テストの完全実行
**内容**: 修正後にアプリを再起動し、C項目のテストを10回完全に実行する。各送信で以下を確認: `_handleSubmit: START submitting` → `SUCCESS` → `sent UI shown` → `timer started` → `reset completed` → `state=input`。

**理由**: C項目の判定のために10回の連続送信ログが必要。

---

## 総合判定

- **A. 二重送信防止**: 不明（判定不可）- 観測不足
- **B. dispose耐性**: PASS
- **C. sent→input復帰**: FAIL - 手順未実施

**Exit code 3 の原因**: `[MessageRepo] SAVED` ログが0回（期待: 1回）のため。
