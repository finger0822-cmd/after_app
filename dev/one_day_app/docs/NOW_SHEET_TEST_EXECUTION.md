# NowSheet実動作テスト実行ガイド

## クイックスタート

### Windowsテスト実行手順

```powershell
# 1. プロジェクトディレクトリに移動
cd C:\Users\taker\develop\flutter\dev\after_app

# 2. テスト開始時刻を記録（別ウィンドウで実行）
$TestStart = Get-Date
Write-Host "TEST_START=$TestStart" -ForegroundColor Cyan

# 3. アプリ起動（このウィンドウで実行）
flutter run -d windows --verbose

# 4. テスト実行
#    - A. 二重送信: 送信ボタン10連打
#    - B. dispose: sent表示直後にウィンドウ閉じる
#    - C. 連続送信: 10回連続送信

# 5. アプリ終了後、結果確認（別ウィンドウで実行）
.\scripts\test_now_sheet.ps1
```

---

## 合否判定ログ一覧

### [A] 二重送信テスト

| ログパターン | 期待 | 判定 |
|------------|------|------|
| `[MessageRepo] SAVED` | **1回のみ** | ✅ PASS / ❌ FAIL |
| `[NowSheet] _handleSubmit: BLOCKED (already submitting)` | 9回以上 | ✅ PASS / ⚠️ WARNING |

**判定基準**:
- ✅ `SAVED`が1回のみ → PASS（二重送信防止が機能）
- ❌ `SAVED`が2回以上 → FAIL（二重送信防止が機能していない）

### [B] dispose耐性テスト

| ログパターン | 期待 | 判定 |
|------------|------|------|
| `setState() called after dispose` | **絶対に出ない** | ❌ FAIL（出たら） |
| `[NowSheet] dispose: _sentResetTimer cancelled` | 必須 | ✅ PASS / ⚠️ WARNING |

**判定基準**:
- ✅ `setState() called after dispose`エラーが出ない → PASS
- ✅ dispose時にタイマーキャンセルログがある → PASS
- ❌ `setState() called after dispose`エラーが出る → FAIL

### [C] 連続送信テスト

| ログパターン | 期待 | 判定 |
|------------|------|------|
| `[NowSheet] _handleSubmit: SUCCESS` | 10回 | ✅ PASS / ❌ FAIL |
| `[NowSheet] Windows: reset completed` | 10回 | ✅ PASS / ❌ FAIL |
| `[NowSheet] _updateUiState: state=input` | 10回 | ✅ PASS / ❌ FAIL |

**判定基準**:
- ✅ 各ログが10回出現 → PASS（状態が破綻しない）
- ❌ 10回未満 → FAIL（状態が破綻している）

---

## スクリプト使用法

### 基本使用
```powershell
# テスト開始前に実行
$TestStart = Get-Date
Write-Host "TEST_START=$TestStart" -ForegroundColor Cyan

# テスト実行後、スクリプト実行
.\scripts\test_now_sheet.ps1
```

### 手動実行（スクリプトなし）
スクリプトファイルの内容を直接実行することも可能です。
詳細は `scripts/test_now_sheet.ps1` を参照してください。

---

## ログ出力ポイント確認（完了）

### ✅ すべての必要なログが揃っている

- submit開始: `_handleSubmit called`
- submit blocked: `BLOCKED (already submitting)`
- saved: `[MessageRepo] SAVED`
- sent表示: `Windows: sent UI shown`
- timer start: `Windows: _sentResetTimer started`
- timer cancel: `dispose: _sentResetTimer cancelled`
- postFrame start: `Windows: _onSentResetTimer STARTED`, `Windows: _onSentResetTimerPostFrame STARTED`
- reset完了: `Windows: reset completed, back to input screen`

**追加ログ**: **不要** - 現在のログで十分に検証可能

---

## 実行手順（Windows/Android）

### Windows
```powershell
# 1. アプリ起動
cd C:\Users\taker\develop\flutter\dev\after_app
flutter run -d windows --verbose

# 2. テスト実行
#    - A. 二重送信: 送信ボタン10連打
#    - B. dispose: sent表示直後にウィンドウ閉じる
#    - C. 連続送信: 10回連続送信

# 3. 結果確認
.\scripts\test_now_sheet.ps1
```

### Android
```powershell
# 1. デバイス確認
flutter devices

# 2. アプリ起動
flutter run -d <device-id>

# 3. テスト実行
#    - 投稿フローが安定することを確認
#    - 通知権限の許可/拒否どちらでもクラッシュしないことを確認

# 4. ログ確認
adb logcat | Select-String "NowSheet|MessageRepo|sessionId"
```

---

## トラブルシューティング

### ログファイルが見つからない場合
```powershell
# ログディレクトリを確認
$logDir = "$env:LOCALAPPDATA\after_app\logs"
if (-not (Test-Path $logDir)) {
    Write-Host "ログディレクトリが存在しません: $logDir" -ForegroundColor Yellow
    Write-Host "アプリを一度起動してログを生成してください" -ForegroundColor Yellow
} else {
    Write-Host "ログディレクトリ: $logDir" -ForegroundColor Green
    Get-ChildItem $logDir | Select-Object Name, LastWriteTime
}
```

### ログが出力されない場合
- `CrashLogger.initialize()`が呼ばれているか確認
- `kDebugMode`が`true`か確認
- `CrashLogger.setLogLevel(LogLevel.debug)`が設定されているか確認
