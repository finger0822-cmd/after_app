# 物理洗浄手順（反映ズレを潰す）

## 目的
CrashLogger変更が実行バイナリに反映されていない問題を解決するため、物理的にクリーンビルドを実行する。

## 手順（最短・確実）

### 1) 実行中の after_app.exe を完全に止める

**方法1: Flutterコンソールから**
- `flutter run` のウィンドウで `q` キー（Quit）

**方法2: タスクマネージャーから**
- タスクマネージャーを開く
- `after_app.exe` を探して終了

**確認コマンド（PowerShell）**:
```powershell
Get-Process -Name "after_app" -ErrorAction SilentlyContinue
```
実行中のプロセスが見つかった場合は終了する。

---

### 2) 物理洗浄

**PowerShell（プロジェクトルート）で実行**:
```powershell
cd C:\Users\taker\develop\flutter\dev\after_app
flutter clean
flutter pub get
flutter run -d windows
```

**注意**: Hot restart / hot reload は信用しない。Windowsデスクトップは特に"残骸"が残りやすい。

---

### 3) 新ログファイル名を必ず確認

**起動直後に出るログ**:
```
[CrashLogger] Initialized: ...\crash_YYYY-...
```

**この新しいファイル名を控える（コピペ推奨）**

**確認コマンド（PowerShell）**:
```powershell
$logDir = Join-Path $env:LOCALAPPDATA "after_app\logs"
Get-ChildItem $logDir -Filter "crash_*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 Name, LastWriteTime
```

---

## 確認事項

### 修正後のコードが反映されているか確認

**新しいログファイルで以下を確認**:
```powershell
$newLog = "C:\Users\taker\AppData\Local\after_app\logs\crash_YYYY-MM-DDTHH-MM-SS.XXXXXX.log"
Select-String -Path $newLog -Pattern "\[MessageRepo\] SAVED" -AllMatches
Select-String -Path $newLog -Pattern "\[NowController\] submit" -AllMatches
```

**期待結果**:
- `[MessageRepo] SAVED` が1回以上記録されている
- `[NowController] submit: 開始` が記録されている
- `[NowController] submit: 成功` が記録されている

---

## トラブルシューティング

### プロセスが残っている場合

```powershell
# プロセスを強制終了
Get-Process -Name "after_app" -ErrorAction SilentlyContinue | Stop-Process -Force
```

### ログファイルが見つからない場合

```powershell
# ログディレクトリを確認
$logDir = Join-Path $env:LOCALAPPDATA "after_app\logs"
if (-not (Test-Path $logDir)) {
    Write-Host "ログディレクトリが存在しません: $logDir" -ForegroundColor Red
    Write-Host "アプリを一度起動してログを生成してください" -ForegroundColor Yellow
}
```

---

## 補足

- Hot restart / hot reload は信用しない（Windowsデスクトップは特に"残骸"が残りやすい）
- `flutter clean` は必須（古いビルドキャッシュを削除）
- 新しいログファイル名を必ず控える（テスト時に使用）
