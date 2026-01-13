# NowSheetログ出力ポイントレビュー

## レビュー日時
2025-12-11

## 目的
実動作テストの合否判定に必要なログが揃っているか確認

---

## [1] ログ出力ポイント一覧

### 現在のログ出力（すべてsessionId付き）

| ログパターン | 出力箇所 | 用途 | 必須 |
|------------|---------|------|------|
| `[NowSheet] _handleSubmit called` | 947行目 | submit開始 | ✅ |
| `[NowSheet] _handleSubmit: BLOCKED (already submitting)` | 953行目 | 二重送信ブロック | ✅ |
| `[NowSheet] _handleSubmit: BLOCKED (empty text)` | 959行目 | 空テキストブロック | - |
| `[NowSheet] _handleSubmit: START submitting` | 969行目 | 送信開始 | ✅ |
| `[NowSheet] _handleSubmit: submit() completed` | 974行目 | submit完了 | ✅ |
| `[NowSheet] _handleSubmit: _isSubmitting reset to false` | 981行目 | ロック解除 | ✅ |
| `[NowSheet] _handleSubmit: submitStatus=...` | 987行目 | 状態確認 | ✅ |
| `[NowSheet] _handleSubmit: SUCCESS` | 990行目 | 送信成功 | ✅ |
| `[NowSheet] _handleSubmit: FAILURE` | 1035行目 | 送信失敗 | ✅ |
| `[NowSheet] Windows: sent UI shown` | 1016行目 | sent表示 | ✅ |
| `[NowSheet] Windows: existing timer cancelled` | 1021行目 | タイマーキャンセル（既存） | ✅ |
| `[NowSheet] Windows: _sentResetTimer started` | 1027行目 | タイマー開始 | ✅ |
| `[NowSheet] Windows: _onSentResetTimer STARTED` | 1045行目 | タイマー実行開始 | ✅ |
| `[NowSheet] Windows: _onSentResetTimer called after dispose` | 1048行目 | dispose後実行（タイマー） | ✅ |
| `[NowSheet] Windows: _onSentResetTimer postFrameCallback called after dispose` | 1057行目 | dispose後実行（postFrame） | ✅ |
| `[NowSheet] Windows: _onSentResetTimerPostFrame STARTED` | 1066行目 | postFrame実行開始 | ✅ |
| `[NowSheet] Windows: _onSentResetTimerPostFrame called after dispose` | 1069行目 | dispose後実行（postFrame内） | ✅ |
| `[NowSheet] Windows: reset completed, back to input screen` | 1075行目 | 復帰完了 | ✅ |
| `[NowSheet] _updateUiState: not mounted, skipping` | 1082行目 | mountedチェック失敗 | ✅ |
| `[NowSheet] _updateUiState: state=...` | 1090行目 | UI状態遷移 | ✅ |
| `[NowSheet] dispose: _sentResetTimer cancelled` | 115行目 | タイマーキャンセル（dispose） | ✅ |
| `[MessageRepo] SAVED` | message_repo.dart | データ保存 | ✅ |

---

## [2] 合否判定に必要なログ

### A. 二重送信テスト
- ✅ `_handleSubmit called` - submit開始の確認
- ✅ `BLOCKED (already submitting)` - 二重送信ブロックの確認
- ✅ `START submitting` - 実際に実行された回数の確認
- ✅ `[MessageRepo] SAVED` - データ保存回数の確認（1回のみ）
- ✅ `_isSubmitting reset to false` - ロック解除の確認

**判定**: ✅ **すべて揃っている**

### B. dispose耐性テスト
- ✅ `dispose: _sentResetTimer cancelled` - タイマーキャンセルの確認
- ✅ `_onSentResetTimer called after dispose` - dispose後のタイマー実行検出
- ✅ `_onSentResetTimer postFrameCallback called after dispose` - dispose後のpostFrame実行検出
- ✅ `_onSentResetTimerPostFrame called after dispose` - dispose後のpostFrame内実行検出
- ✅ `setState() called after dispose` - エラーの有無（出ないことが期待）

**判定**: ✅ **すべて揃っている**

### C. 連続送信テスト
- ✅ `_handleSubmit: SUCCESS` - 各送信の成功確認
- ✅ `Windows: sent UI shown` - sent表示の確認
- ✅ `Windows: _sentResetTimer started` - タイマー開始の確認
- ✅ `Windows: _onSentResetTimer STARTED` - タイマー実行の確認
- ✅ `Windows: reset completed` - 復帰完了の確認
- ✅ `_updateUiState: state=input` - input状態への遷移確認

**判定**: ✅ **すべて揃っている**

---

## [3] ログ追加の必要性

### 検討した追加ログ

#### 1. `_updateUiState`で状態遷移の詳細ログ
**検討**: `state=input`への遷移時に、前の状態も記録するか
**判定**: ❌ **不要**
- 既に`state=$newState`で状態が記録されている
- 前の状態は`build`ログで`_uiState=$_uiState`として記録されている

#### 2. `safeSetState`内でのログ
**検討**: `safeSetState`内で`mounted`チェック失敗時にログを出すか
**判定**: ❌ **不要**
- `_updateUiState`で既に`not mounted, skipping`ログを出している
- 重複ログになる

#### 3. `_isSubmitting`の状態変化ログ
**検討**: `_isSubmitting`が`true`→`false`に変化する際のログ
**判定**: ❌ **不要**
- 既に`_isSubmitting reset to false`ログがある
- `_handleSubmit: START submitting`で`true`になることが記録されている

---

## [4] ログ出力の品質

### ✅ 良い点
1. **すべてのログにsessionIdが付与されている** - 追跡可能
2. **ログレベルが適切** - `logDebug`/`logInfo`/`logTrace`を使い分け
3. **エラー時は`logException`を使用** - スタックトレースを記録
4. **状態遷移が明確** - `state=$newState`で状態を記録

### ⚠️ 改善の余地（任意）
1. **ログの冗長性**: `build`ログが`logTrace`レベルなので、通常は出力されない（問題なし）
2. **ログの順序**: タイムスタンプで順序が確認できる（問題なし）

---

## [5] 判定結果

### ✅ 合否判定に必要なログはすべて揃っている

**理由**:
1. 二重送信防止: `BLOCKED`ログと`SAVED`ログで確認可能
2. dispose後setState防止: `dispose`ログと`called after dispose`ログで確認可能
3. sent→input復帰: `reset completed`ログと`state=input`ログで確認可能
4. 連続送信: 各送信の成功ログと復帰ログで確認可能

**追加ログ**: **不要**

---

## [6] ログ確認のベストプラクティス

### sessionIdで追跡
```powershell
# 特定のsessionIdのログを抽出
Get-Content $logPath | Select-String "sessionId=1234567890"
```

### 時系列で確認
```powershell
# タイムスタンプ順にソート
Get-Content $logPath | Select-String "NowSheet" | Sort-Object
```

### エラーの有無を確認
```powershell
# エラーログを検索
Get-Content $logPath | Select-String "ERROR|Exception|setState\(\) called after dispose"
```

---

## [7] まとめ

### 現在のログ出力
- ✅ 合否判定に必要なログはすべて揃っている
- ✅ すべてのログにsessionIdが付与されている
- ✅ ログレベルが適切に使い分けられている

### 追加ログ
- ❌ **不要** - 現在のログで十分に検証可能

### 次のステップ
1. 実動作テストを実行
2. `NOW_SHEET_TEST_PROCEDURE.md`の確認コマンドでログを検証
3. 合否判定基準に基づいて判定
