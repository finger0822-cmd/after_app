# 置換反映の即時確認手順

## 目的
CrashLogger変更が実行バイナリに反映されているかを最短で確認する。

## 手順

### 1. アプリ起動後、NowSheetで1回だけ送信

- NowSheetを開く
- 任意のテキストを入力（例: "test"）
- 送信ボタンを1回クリック

### 2. 最新ログファイルを確認

**PowerShellコマンド**:
```powershell
$logDir = Join-Path $env:LOCALAPPDATA "after_app\logs"
$latestLog = Get-ChildItem $logDir -Filter "crash_*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$log = $latestLog.FullName

Write-Host "ログファイル: $($latestLog.Name)" -ForegroundColor Yellow
Write-Host ""

# MessageRepo / NowController / SAVED の検索
Select-String -Path $log -Pattern "MessageRepo|NowController|SAVED" -AllMatches
```

### 3. 期待する結果

**PASS条件**:
- `[MessageRepo] SAVED ...` が **1件以上**
- `[NowController] submit ...` が **1件以上**

**これが出れば「置換が反映された世界線」に入った合図。**

### 4. 判定

**PASS**: 上記のログが1件以上見つかった
- → 置換が反映されている
- → 次のステップ: 正式なテスト（A/B/C）を実行

**FAIL**: 上記のログが0件
- → まだ置換が反映されていない可能性
- → 次のステップ: アプリを再起動して再確認

---

## 簡易確認コマンド（1行）

```powershell
$log = (Get-ChildItem "$env:LOCALAPPDATA\after_app\logs\crash_*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName; Select-String -Path $log -Pattern "MessageRepo|NowController|SAVED" -AllMatches
```

---

## トラブルシューティング

### ログファイルが見つからない場合

```powershell
$logDir = Join-Path $env:LOCALAPPDATA "after_app\logs"
if (-not (Test-Path $logDir)) {
    Write-Host "ログディレクトリが存在しません" -ForegroundColor Red
    Write-Host "アプリを一度起動してログを生成してください" -ForegroundColor Yellow
}
```

### ログが0件の場合

1. アプリが正しく起動しているか確認
2. NowSheetで送信を実行したか確認
3. ログファイルの最終更新時刻を確認（送信後に更新されているか）
