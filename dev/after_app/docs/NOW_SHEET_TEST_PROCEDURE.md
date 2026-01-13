# NowSheet実動作テスト手順書

## 目的
NowSheetの実動作テストを通し、以下を検証する:
- 二重送信が完全に防げている
- sent→input復帰が必ず起きる（Windows）
- dispose後setStateが絶対に起きない（タイマー/ポストフレーム含む）
- 連続送信で状態が破綻しない

---

## [1] 合否判定ログ一覧

### 必須ログ（すべて出現する必要がある）

#### A. 二重送信テスト
| ログパターン | 期待回数 | 条件 |
|------------|---------|------|
| `[NowSheet] _handleSubmit called` | 10回 | 10連打した場合 |
| `[NowSheet] _handleSubmit: BLOCKED (already submitting)` | 9回以上 | 2回目以降はブロック |
| `[NowSheet] _handleSubmit: START submitting` | 1回 | 最初の1回のみ実行 |
| `[MessageRepo] SAVED` | **1回のみ** | データ保存は1回のみ |
| `[NowSheet] _handleSubmit: _isSubmitting reset to false` | 1回 | 送信完了後 |

**判定基準**:
- ✅ `SAVED`が1回のみ → PASS
- ✅ `BLOCKED`が9回以上 → PASS
- ❌ `SAVED`が2回以上 → FAIL（二重送信防止が機能していない）

#### B. dispose耐性テスト
| ログパターン | 期待 | 条件 |
|------------|------|------|
| `[NowSheet] dispose: _sentResetTimer cancelled` | 必須 | dispose時にタイマーキャンセル |
| `[NowSheet] Windows: _onSentResetTimer called after dispose` | 条件付き | タイマー実行時にdispose済みの場合 |
| `[NowSheet] Windows: _onSentResetTimer postFrameCallback called after dispose` | 条件付き | postFrame実行時にdispose済みの場合 |
| `[NowSheet] Windows: _onSentResetTimerPostFrame called after dispose` | 条件付き | postFrame実行時にdispose済みの場合 |
| `setState() called after dispose` | **絶対に出ない** | エラーが出たらFAIL |

**判定基準**:
- ✅ `setState() called after dispose`エラーが出ない → PASS
- ✅ dispose時にタイマーキャンセルログがある → PASS
- ❌ `setState() called after dispose`エラーが出る → FAIL

#### C. 連続送信テスト
| ログパターン | 期待 | 条件 |
|------------|------|------|
| `[NowSheet] _handleSubmit: SUCCESS` | 10回 | 各送信が成功 |
| `[NowSheet] Windows: sent UI shown` | 10回 | sent表示 |
| `[NowSheet] Windows: _sentResetTimer started` | 10回 | タイマー開始 |
| `[NowSheet] Windows: _onSentResetTimer STARTED` | 10回 | タイマー実行 |
| `[NowSheet] Windows: reset completed, back to input screen` | 10回 | 復帰完了 |
| `[NowSheet] _updateUiState: state=input` | 10回 | input状態に戻る |

**判定基準**:
- ✅ 各送信で復帰ログが10回出現 → PASS
- ✅ `_updateUiState: state=input`が10回 → PASS
- ❌ 復帰ログが10回未満 → FAIL（状態が破綻）

---

## [2] Windows実動作テスト手順

### 準備
```powershell
# プロジェクトディレクトリに移動
cd C:\Users\taker\develop\flutter\dev\after_app

# アプリ起動（ログをコンソールに出力）
flutter run -d windows --verbose
```

### A. 二重送信テスト

**手順**:
1. NowSheetを開く
2. "test" と入力
3. 送信ボタンを**10連打**（1秒以内に連続クリック）

**確認コマンド**（別のPowerShellウィンドウで実行）:
```powershell
# ログファイルから確認
$logPath = "$env:LOCALAPPDATA\after_app\logs\crash_*.log"
$latestLog = Get-ChildItem $logPath | Sort-Object LastWriteTime -Descending | Select-Object -First 1

Write-Host "=== 二重送信テスト ログ確認 ===" -ForegroundColor Cyan

# SAVEDログの回数（1回のみであることを確認）
$savedCount = (Get-Content $latestLog.FullName | Select-String "\[MessageRepo\] SAVED").Count
Write-Host "SAVEDログ回数: $savedCount (期待: 1)" -ForegroundColor $(if ($savedCount -eq 1) { "Green" } else { "Red" })

# BLOCKEDログの回数（9回以上であることを確認）
$blockedCount = (Get-Content $latestLog.FullName | Select-String "BLOCKED \(already submitting\)").Count
Write-Host "BLOCKEDログ回数: $blockedCount (期待: 9以上)" -ForegroundColor $(if ($blockedCount -ge 9) { "Green" } else { "Yellow" })

# 最新のsubmitセッションIDを取得
$latestSessionId = (Get-Content $latestLog.FullName | Select-String "_handleSubmit called" | Select-Object -Last 1) -replace '.*sessionId=(\d+).*', '$1'
Write-Host "最新sessionId: $latestSessionId" -ForegroundColor Cyan

# 該当sessionIdのログを抽出
Get-Content $latestLog.FullName | Select-String "sessionId=$latestSessionId" | Select-Object -Last 20
```

**期待結果**:
- ✅ `SAVEDログ回数: 1`
- ✅ `BLOCKEDログ回数: 9以上`
- ✅ UIがフリーズしない

### B. dispose耐性テスト

**手順**:
1. NowSheetで送信
2. **sent表示の直後（0.5秒以内）**にウィンドウを閉じる、または別画面へ遷移

**確認コマンド**:
```powershell
$logPath = "$env:LOCALAPPDATA\after_app\logs\crash_*.log"
$latestLog = Get-ChildItem $logPath | Sort-Object LastWriteTime -Descending | Select-Object -First 1

Write-Host "=== dispose耐性テスト ログ確認 ===" -ForegroundColor Cyan

# dispose後setStateエラーの有無
$setStateError = Get-Content $latestLog.FullName | Select-String "setState\(\) called after dispose"
if ($setStateError) {
    Write-Host "❌ FAIL: setState() called after dispose エラーが検出されました" -ForegroundColor Red
    $setStateError | ForEach-Object { Write-Host $_ -ForegroundColor Red }
} else {
    Write-Host "✅ PASS: setState() called after dispose エラーなし" -ForegroundColor Green
}

# タイマーキャンセルログ
$timerCancel = Get-Content $latestLog.FullName | Select-String "dispose: _sentResetTimer cancelled"
if ($timerCancel) {
    Write-Host "✅ PASS: タイマーキャンセルログあり" -ForegroundColor Green
    $timerCancel | Select-Object -Last 1
} else {
    Write-Host "⚠️ WARNING: タイマーキャンセルログが見つかりません" -ForegroundColor Yellow
}

# dispose後のコールバック実行ログ（正常な動作）
$disposeCallback = Get-Content $latestLog.FullName | Select-String "called after dispose"
if ($disposeCallback) {
    Write-Host "✅ INFO: dispose後のコールバック実行が検出されました（正常）" -ForegroundColor Cyan
    $disposeCallback | Select-Object -Last 5
}
```

**期待結果**:
- ✅ `setState() called after dispose`エラーが出ない
- ✅ `dispose: _sentResetTimer cancelled`ログがある
- ✅ dispose後のコールバック実行時は適切にログが記録される

### C. 連続送信テスト

**手順**:
1. "test1" 入力 → 送信 → 復帰を確認（入力欄が表示されるまで待つ）
2. "test2" 入力 → 送信 → 復帰を確認
3. これを**10回繰り返す**

**確認コマンド**:
```powershell
$logPath = "$env:LOCALAPPDATA\after_app\logs\crash_*.log"
$latestLog = Get-ChildItem $logPath | Sort-Object LastWriteTime -Descending | Select-Object -First 1

Write-Host "=== 連続送信テスト ログ確認 ===" -ForegroundColor Cyan

# 成功ログの回数
$successCount = (Get-Content $latestLog.FullName | Select-String "_handleSubmit: SUCCESS").Count
Write-Host "SUCCESSログ回数: $successCount (期待: 10)" -ForegroundColor $(if ($successCount -eq 10) { "Green" } else { "Red" })

# 復帰完了ログの回数
$resetCount = (Get-Content $latestLog.FullName | Select-String "reset completed, back to input screen").Count
Write-Host "復帰完了ログ回数: $resetCount (期待: 10)" -ForegroundColor $(if ($resetCount -eq 10) { "Green" } else { "Red" })

# input状態への遷移ログ
$inputStateCount = (Get-Content $latestLog.FullName | Select-String "_updateUiState: state=input").Count
Write-Host "input状態遷移ログ回数: $inputStateCount (期待: 10)" -ForegroundColor $(if ($inputStateCount -eq 10) { "Green" } else { "Red" })

# 最新10回の送信セッションIDを取得
$latestSessions = (Get-Content $latestLog.FullName | Select-String "_handleSubmit: SUCCESS" | Select-Object -Last 10) -replace '.*sessionId=(\d+).*', '$1'
Write-Host "`n最新10回の送信セッションID:" -ForegroundColor Cyan
$latestSessions | ForEach-Object { Write-Host "  $_" }
```

**期待結果**:
- ✅ `SUCCESSログ回数: 10`
- ✅ `復帰完了ログ回数: 10`
- ✅ `input状態遷移ログ回数: 10`
- ✅ 毎回復帰が成功し、入力欄が正常に表示される

---

## [3] Android実動作テスト手順

### 準備
```powershell
# デバイス一覧を確認
flutter devices

# アプリ起動
flutter run -d <device-id>
```

### テスト手順
1. NowSheetで投稿フローを実行
2. 通知権限を許可/拒否の両方でテスト

### 確認コマンド
```powershell
# Androidのログはadb経由で確認
adb logcat | Select-String "NowSheet|MessageRepo|sessionId"
```

**期待結果**:
- ✅ 投稿フローが安定する（absorbアニメーションが正常に動作）
- ✅ 通知権限の許可/拒否どちらでもクラッシュしない
- ✅ Windowsと同様に二重送信防止が機能する

---

## [4] 統合確認コマンド（PowerShell）

### スクリプトファイルを使用（推奨）
```powershell
# プロジェクトディレクトリに移動
cd C:\Users\taker\develop\flutter\dev\after_app

# テスト開始前に実行（テスト開始時刻を記録）
$TestStart = Get-Date
Write-Host "TEST_START=$TestStart" -ForegroundColor Cyan

# 以降、flutter run でテストを実施

# テスト完了後、スクリプトを実行
.\scripts\test_now_sheet.ps1
```

### 手動で確認する場合
```powershell
# ログファイルのパス
$logPath = "$env:LOCALAPPDATA\after_app\logs\crash_*.log"
$latestLog = Get-ChildItem $logPath | Sort-Object LastWriteTime -Descending | Select-Object -First 1

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "NowSheet実動作テスト 結果サマリー" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# A. 二重送信テスト
Write-Host "[A] 二重送信テスト" -ForegroundColor Yellow
$savedCount = (Get-Content $latestLog.FullName | Select-String "\[MessageRepo\] SAVED").Count
$blockedCount = (Get-Content $latestLog.FullName | Select-String "BLOCKED \(already submitting\)").Count
Write-Host "  SAVED: $savedCount回 (期待: 1)" -ForegroundColor $(if ($savedCount -eq 1) { "Green" } else { "Red" })
Write-Host "  BLOCKED: $blockedCount回 (期待: 9以上)" -ForegroundColor $(if ($blockedCount -ge 9) { "Green" } else { "Yellow" })

# B. dispose耐性テスト
Write-Host "`n[B] dispose耐性テスト" -ForegroundColor Yellow
$setStateError = Get-Content $latestLog.FullName | Select-String "setState\(\) called after dispose"
$timerCancel = Get-Content $latestLog.FullName | Select-String "dispose: _sentResetTimer cancelled"
Write-Host "  setState() called after dispose: $(if ($setStateError) { 'FAIL' } else { 'PASS' })" -ForegroundColor $(if ($setStateError) { "Red" } else { "Green" })
Write-Host "  タイマーキャンセル: $(if ($timerCancel) { 'PASS' } else { 'WARNING' })" -ForegroundColor $(if ($timerCancel) { "Green" } else { "Yellow" })

# C. 連続送信テスト
Write-Host "`n[C] 連続送信テスト" -ForegroundColor Yellow
$successCount = (Get-Content $latestLog.FullName | Select-String "_handleSubmit: SUCCESS").Count
$resetCount = (Get-Content $latestLog.FullName | Select-String "reset completed, back to input screen").Count
$inputStateCount = (Get-Content $latestLog.FullName | Select-String "_updateUiState: state=input").Count
Write-Host "  SUCCESS: $successCount回 (期待: 10)" -ForegroundColor $(if ($successCount -eq 10) { "Green" } else { "Red" })
Write-Host "  復帰完了: $resetCount回 (期待: 10)" -ForegroundColor $(if ($resetCount -eq 10) { "Green" } else { "Red" })
Write-Host "  input状態遷移: $inputStateCount回 (期待: 10)" -ForegroundColor $(if ($inputStateCount -eq 10) { "Green" } else { "Red" })

Write-Host "`n========================================" -ForegroundColor Cyan
```

---

## [5] ログ出力ポイント一覧

### 現在のログ出力（すべてsessionId付き）

| ログパターン | 出力箇所 | 用途 |
|------------|---------|------|
| `_handleSubmit called` | 947行目 | submit開始 |
| `_handleSubmit: BLOCKED (already submitting)` | 953行目 | 二重送信ブロック |
| `_handleSubmit: START submitting` | 969行目 | 送信開始 |
| `_handleSubmit: submit() completed` | 974行目 | submit完了 |
| `_handleSubmit: SUCCESS` | 990行目 | 送信成功 |
| `_handleSubmit: FAILURE` | 1035行目 | 送信失敗 |
| `Windows: sent UI shown` | 1016行目 | sent表示 |
| `Windows: _sentResetTimer started` | 1027行目 | タイマー開始 |
| `Windows: _onSentResetTimer STARTED` | 1045行目 | タイマー実行開始 |
| `Windows: _onSentResetTimerPostFrame STARTED` | 1066行目 | postFrame実行開始 |
| `Windows: reset completed` | 1075行目 | 復帰完了 |
| `dispose: _sentResetTimer cancelled` | 115行目 | タイマーキャンセル |
| `_updateUiState: state=...` | 1090行目 | UI状態遷移 |
| `[MessageRepo] SAVED` | message_repo.dart | データ保存 |

**判定**: ✅ **すべての必要なログが揃っている**

---

## [6] 合否判定基準

### 総合判定

#### ✅ PASS条件（すべて満たす必要がある）
1. **二重送信防止**: `SAVED`ログが1回のみ
2. **dispose後setState防止**: `setState() called after dispose`エラーが出ない
3. **sent→input復帰**: 連続送信で復帰ログが10回出現
4. **状態管理**: `input状態遷移ログ`が10回出現

#### ❌ FAIL条件（1つでも該当すればFAIL）
1. `SAVED`ログが2回以上
2. `setState() called after dispose`エラーが出る
3. 復帰ログが10回未満（連続送信テスト）
4. UIがフリーズする

---

## [7] トラブルシューティング

### ログファイルが見つからない場合
```powershell
# ログディレクトリを確認
$logDir = "$env:LOCALAPPDATA\after_app\logs"
if (-not (Test-Path $logDir)) {
    Write-Host "ログディレクトリが存在しません: $logDir" -ForegroundColor Yellow
    Write-Host "アプリを一度起動してログを生成してください" -ForegroundColor Yellow
}
```

### ログが出力されない場合
- `CrashLogger.initialize()`が呼ばれているか確認
- `kDebugMode`が`true`か確認
- `CrashLogger.setLogLevel(LogLevel.debug)`が設定されているか確認

---

## [8] 実行手順まとめ

### Windows
```powershell
# 1. アプリ起動
cd C:\Users\taker\develop\flutter\dev\after_app
flutter run -d windows --verbose

# 2. テスト実行（別ウィンドウで）
# 上記の確認コマンドを実行

# 3. 結果確認
# 統合確認コマンドで一括確認
```

### Android
```powershell
# 1. デバイス確認
flutter devices

# 2. アプリ起動
flutter run -d <device-id>

# 3. ログ確認
adb logcat | Select-String "NowSheet|MessageRepo|sessionId"
```
