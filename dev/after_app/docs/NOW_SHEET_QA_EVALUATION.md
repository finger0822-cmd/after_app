# NowSheet 品質監査評価レポート

## 評価日時
2026-01-10

## 評価者
QA Lead / リリース判定官

## 対象機能
- 機能: NowSheet（投稿・保存・UI復帰フロー）
- プラットフォーム: Windows / Android
- ログ基盤: CrashLogger（sessionId付き）
- 検証スクリプト: `scripts/test_now_sheet.ps1`

---

## 1. 総合評価

### 評価: **B**

**判定理由（事実ベース）**:
- コード構造・ログ整備・自動検証スクリプトは完成度が高い（事実）
- 実動作テストの実行結果が未確認（事実）
- 静的チェック（`flutter analyze`）では新規エラーなし（事実）
- コードレビューで要件（二重送信防止、dispose後setState防止、UI状態enum化）を満たしている（事実）

---

## 2. 評価観点別の詳細評価

### 2.1 正常系の完成度

**評価: A**

**判定理由（事実ベース）**:

#### ✅ 実装済み（コード確認）
- `enum NowSheetUiState { input, submitting, sent }` で状態管理（`now_sheet.dart:19-23`）
- Windows用の自動復帰：`Timer` + `postFrameCallback`で実装（`now_sheet.dart:1024-1076`）
- 投稿→保存→sent表示→復帰のフローは実装済み（`now_sheet.dart:939-1041`）
- `_updateUiState()` で状態更新を一元化（`now_sheet.dart:1080-1091`）

#### ⚠️ 未確認（事実）
- 連続操作（10回以上）の実動作テスト結果が未確認
- 実測ログ（`SAVED`回数、`reset completed`回数）が確認されていない

**コード証跡**:
```18:23:after_app/lib/features/calendar/now_sheet.dart
enum NowSheetUiState {
  input,      // 入力中
  submitting, // 送信中
  sent,       // 送信成功（Windows用）
}
```

```1024:1028:after_app/lib/features/calendar/now_sheet.dart
_sentResetTimer = Timer(const Duration(milliseconds: 1000), () {
  _onSentResetTimer(sessionId: submitSessionId);
});
CrashLogger.logDebug('[NowSheet] Windows: _sentResetTimer started (1000ms) sessionId=$submitSessionId');
```

---

### 2.2 異常系耐性

**評価: A**

**判定理由（事実ベース）**:

#### ✅ 実装済み（コード確認）
- `_isSubmitting` フラグで二重送信防止（`try/finally`で確実に解除、`now_sheet.dart:952-955, 978-982`）
- `AbsorbPointer` で送信中はすべての入力を吸収（`now_sheet.dart:1101-1103`）
- `TextField.enabled` と `ElevatedButton.onPressed` でUI無効化（`now_sheet.dart:1151, 1194`）
- dispose時に `Timer` をキャンセル（`now_sheet.dart:111-115`）
- すべての非同期処理で `mounted` チェック（`now_sheet.dart:1047-1071`）
- `safeSetState` ヘルパーで `setState` 前の `mounted` チェック（`now_sheet.dart:72-78`）

#### ⚠️ 未確認（事実）
- `setState() called after dispose` エラーが実際に出ていないかの確認が未実施
- 二重送信の実動作テスト結果（`SAVED`が1回のみ）が未確認

**コード証跡**:
```951:955:after_app/lib/features/calendar/now_sheet.dart
// 二重送信ガード（ログ出力後にチェック）
if (_isSubmitting) {
  CrashLogger.logDebug('[NowSheet] _handleSubmit: BLOCKED (already submitting) source=$source sessionId=$submitSessionId');
  return;
}
```

```111:115:after_app/lib/features/calendar/now_sheet.dart
void dispose() {
  // タイマーをキャンセル（dispose後setState防止）
  _sentResetTimer?.cancel();
  _sentResetTimer = null;
  CrashLogger.logDebug('[NowSheet] dispose: _sentResetTimer cancelled');
```

---

### 2.3 観測可能性（デバッグ耐性）

**評価: S**

**判定理由（事実ベース）**:

#### ✅ 実装済み（コード確認）
- すべてのログに `sessionId` を付与（41箇所で `CrashLogger` を使用、`now_sheet.dart` 全体）
- submit開始/成功/失敗/ブロックのログを出力（`now_sheet.dart:947-1035`）
- タイマー開始/キャンセル/実行のログを出力（`now_sheet.dart:1021-1076`）
- dispose時のログを出力（`now_sheet.dart:115`）
- エラー時は `logException` でスタックトレースを記録（`now_sheet.dart:976, 1006, 1048, 1057, 1069`）

**ログ出力一覧（証跡）**:
- `_handleSubmit called` (947行目)
- `BLOCKED (already submitting)` (953行目)
- `START submitting` (969行目)
- `SUCCESS` (990行目)
- `Windows: sent UI shown` (1016行目)
- `Windows: _sentResetTimer started` (1027行目)
- `Windows: reset completed, back to input screen` (1075行目)
- `dispose: _sentResetTimer cancelled` (115行目)
- `[MessageRepo] SAVED` (message_repo.dart:17)

**コード証跡**:
```947:949:after_app/lib/features/calendar/now_sheet.dart
CrashLogger.logDebug('[NowSheet] _handleSubmit called source=$source sessionId=$submitSessionId timestamp=$submitTimestamp');
CrashLogger.logDebug('[NowSheet] _handleSubmit stackTrace (first 10 lines):\n$stackLines');
CrashLogger.logDebug('[NowSheet] _handleSubmit state: _isSubmitting=$_isSubmitting mounted=$mounted uiState=$_uiState');
```

---

### 2.4 自動検証適合性

**評価: A**

**判定理由（事実ベース）**:

#### ✅ 実装済み（コード確認）
- `test_now_sheet.ps1` で exit code を返す（exit 1/2/3/0、`scripts/test_now_sheet.ps1:15-19, 142-153, 175`）
- `-TestStart` パラメータで開始時刻以降のログだけを集計可能（`scripts/test_now_sheet.ps1:5-7`）
- `SAVED`回数、`setState() called after dispose`エラー、dispose時のタイマーキャンセルを自動検証（`scripts/test_now_sheet.ps1:56-94`）

#### ⚠️ 未確認（事実）
- 自動検証スクリプトの実際の実行結果が未確認
- Windows/Android での実動作テストが未実施

**コード証跡**:
```5:7:after_app/scripts/test_now_sheet.ps1
param(
    [datetime]$TestStart = (Get-Date)
)
```

```141:153:after_app/scripts/test_now_sheet.ps1
# 優先度1: setState() called after dispose が1回でも見つかれば exit 2
if ($setStateErr) {
    Write-Host "FAIL: setState() called after dispose エラーが検出されました" -ForegroundColor Red
    $exitCode = 2
}

# 優先度2: SAVEDが1回以外なら exit 3
if ($savedCount -ne 1) {
    Write-Host "FAIL: SAVEDログが$savedCount回 (期待: 1回)" -ForegroundColor Red
    if ($exitCode -eq 0) {
        $exitCode = 3
    }
}
```

---

### 2.5 保守性・将来耐性

**評価: A**

**判定理由（事実ベース）**:

#### ✅ 実装済み（コード確認）
- `enum NowSheetUiState` で状態を明確化（`now_sheet.dart:19-23`）
- `_updateUiState()` で状態更新を一元化（`now_sheet.dart:1080-1091`）
- `safeSetState()` ヘルパーで `mounted` チェックを統一（`now_sheet.dart:72-78`）
- コメントで「なぜこのガードがあるか」を説明（例: `now_sheet.dart:952, 1023`）
- `Platform.isWindows` でプラットフォーム分岐（`now_sheet.dart:997`）

#### ⚠️ 改善の余地（事実）
- Android での実動作テストが未実施（`Platform.isWindows` の分岐が正しく動作するか未確認）

**コード証跡**:
```72:78:after_app/lib/features/calendar/now_sheet.dart
/// 安全なsetState（mountedチェック付き、例外は握りつぶさない）
void safeSetState(VoidCallback fn) {
  if (!mounted) {
    return;
  }
  setState(fn);
}
```

```997:1029:after_app/lib/features/calendar/now_sheet.dart
// Windows DesktopではNavigator操作を完全にやめて、NowSheet内の状態遷移だけで完結
// 理由：Navigator.pop直後に Lost connection が発生するため
if (Platform.isWindows) {
  CrashLogger.logDebug('[NowSheet] Windows: Navigator operations disabled, using local state transition sessionId=$submitSessionId');
  
  // ... Windows用の処理 ...
  
  return;
}

// iOS / Android では現状のabsorb演出を保持
// 吸い込み処理を1箇所に集約
await _runAbsorbAndClose(text.trim());
```

---

## 3. 現時点でのリリース可否

### 判定: **条件付き可**

**理由（事実ベース）**:
- コード構造・ログ整備・自動検証スクリプトは完成度が高い（事実）
- 静的チェック（`flutter analyze`）では新規エラーなし（事実）
- **しかし、実動作テストの実行結果が未確認**（事実）

**条件**:
1. Windows での実動作テストを実施し、以下を確認:
   - 二重送信テスト: `SAVED`ログが1回のみ（`scripts/test_now_sheet.ps1` で確認）
   - dispose耐性テスト: `setState() called after dispose`エラーが出ない（`scripts/test_now_sheet.ps1` で確認）
   - 連続送信テスト: 10回連続送信で復帰ログが10回出現（`scripts/test_now_sheet.ps1` で確認）
2. Android での実動作テストを実施し、同様の確認を行う（可能な場合）
3. 実動作テスト結果を `docs/NOW_SHEET_TEST_EXECUTION.md` に記録

---

## 4. 完成度を100%にするための残タスク

### タスク1: Windows での実動作テスト実施（必須）

**内容**:
1. `docs/NOW_SHEET_TEST_PROCEDURE.md` の手順に従って実動作テストを実施
2. `scripts/test_now_sheet.ps1 -TestStart (Get-Date).AddMinutes(-10)` を実行して結果を確認
3. 以下を確認:
   - exit code が 0（すべてのテストがPASS）
   - `SAVED`ログが1回のみ（二重送信テスト）
   - `setState() called after dispose`エラーが出ない（dispose耐性テスト）
   - `reset completed, back to input screen`ログが10回出現（連続送信テスト）

**実装可能性**: 高（手順・スクリプトは整備済み）

**証跡**:
- `docs/NOW_SHEET_TEST_PROCEDURE.md` に手順が記載されている
- `scripts/test_now_sheet.ps1` で自動検証可能

---

### タスク2: 実動作テスト結果の記録（必須）

**内容**:
1. 実動作テスト実行後、`docs/NOW_SHEET_TEST_EXECUTION.md` に以下を記録:
   - 実行日時
   - テスト環境（OS、Flutterバージョン、デバイス）
   - 各テストの結果（PASS/FAIL、ログ件数、exit code）
   - 観測された問題（あれば）

**実装可能性**: 高（テンプレートは不要、Markdownで記録）

**証跡**:
- `docs/NOW_SHEET_TEST_EXECUTION.md` が存在するが、実行結果が未記録

---

### タスク3: Android での実動作テスト実施（推奨）

**内容**:
1. Android デバイス/エミュレータで `flutter run -d <device-id>` を実行
2. Windows と同様のテスト（二重送信、dispose耐性、連続送信）を実施
3. `adb logcat | Select-String "NowSheet|MessageRepo|sessionId"` でログを確認
4. 結果を `docs/NOW_SHEET_TEST_EXECUTION.md` に記録

**実装可能性**: 中（Android デバイス/エミュレータが必要）

**証跡**:
- `docs/NOW_SHEET_TEST_PROCEDURE.md` にAndroidの手順が記載されている（192-217行目）

---

## 5. 結論文

**NowSheet は、コード構造・ログ整備・自動検証スクリプトの観点では実用リリース可能な完成度に達しているが、実動作テストの実行結果が未確認であるため、Windows での実動作テスト実施と結果記録を必須条件として、条件付きでリリース可能と判定する。**

---

## 補足: 評価の根拠

### コードレビューで確認した事実
1. 二重送信防止: `_isSubmitting` フラグ + `AbsorbPointer` + UI無効化（コード確認済み）
2. dispose後setState防止: `Timer.cancel()` + `mounted` チェック + `safeSetState` ヘルパー（コード確認済み）
3. UI状態管理: `enum NowSheetUiState` + `_updateUiState()` で一元化（コード確認済み）
4. ログ整備: 41箇所で `CrashLogger` を使用、すべてのログに `sessionId` 付与（コード確認済み）

### 未確認の事実
1. 実動作テストの実行結果（`SAVED`回数、`setState() called after dispose`エラーの有無、復帰ログの回数）
2. Android での動作確認

### 静的チェック結果
- `flutter analyze` で新規エラーなし（`docs/NOW_SHEET_VERIFICATION.md:14-25` に記載）

---

## 参照ドキュメント
- `docs/NOW_SHEET_VERIFICATION.md` - 静的チェック・コードレビュー結果
- `docs/NOW_SHEET_TEST_PROCEDURE.md` - 実動作テスト手順
- `docs/NOW_SHEET_LOG_REVIEW.md` - ログ出力ポイントレビュー
- `scripts/test_now_sheet.ps1` - 自動検証スクリプト
