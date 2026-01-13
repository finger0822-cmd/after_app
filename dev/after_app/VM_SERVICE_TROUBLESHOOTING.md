# VM Service接続トラブルシューティング

## 問題: "Lost connection to device"

Windows Desktopで`flutter run`が一定時間後に「Lost connection to device」で切断される場合の対処方法。

## 原因の切り分け

### 1. アプリがクラッシュした場合
- ログファイルで`[HEARTBEAT]`が突然停止する
- 例外ログが出力される
- プロセスが死んでいる

### 2. flutter tool が接続を見失った場合（一般的）
- `[HEARTBEAT]`は継続して出力される（アプリは生きている）
- 例外ログは出力されない
- プロセスが生きている

## 推奨起動コマンド

VM Service接続の安定化のため、以下のオプションを追加してください：

```bash
flutter run -d windows \
  --vm-service-port=0 \
  --disable-service-auth-codes \
  --verbose
```

**各オプションの説明：**
- `--vm-service-port=0`: ポートを自動割り当て（競合回避）
- `--disable-service-auth-codes`: 認証コードを無効化（接続簡素化）
- `--verbose`: 詳細ログを出力（診断用）

## 切断直後の診断手順

### ステップ1: プロセス確認

PowerShellでプロセスが生きているか確認：

```powershell
Get-Process | Where-Object {$_.ProcessName -like "*after_app*"}
```

プロセスが生きている場合 → flutter tool の問題（接続が切れただけ）

### ステップ2: VM Service URL確認

ログファイルを確認してVM Service URLを取得：

**ログファイルの場所:**
- Windows: `%LOCALAPPDATA%\after_app\logs\crash_*.log`
- その他: `%USERPROFILE%\Documents\after_app\logs\crash_*.log`

**ログファイル内で以下を検索:**
```
VM Service URL:
```

例：
```
[main] VM Service URL: http://127.0.0.1:56805/dp1Anzcabm4=/
[main] VM Service WebSocket: ws://127.0.0.1:56805/dp1Anzcabm4=/ws
[main] To reconnect: flutter attach --debug-url=ws://127.0.0.1:56805/dp1Anzcabm4=/ws
```

### ステップ3: ポート確認

VM Service URLのポート番号を確認し、ポートが開いているか確認：

```cmd
netstat -ano | findstr <port>
```

例：
```cmd
netstat -ano | findstr 56805
```

ポートが開いている場合 → VM Serviceは動作中

### ステップ4: 再接続

ログファイルに記録されたVM Service URLを使用して再接続：

```bash
flutter attach --debug-url <VM Service URL>
```

例：
```bash
flutter attach --debug-url ws://127.0.0.1:56805/dp1Anzcabm4=/ws
```

## ログファイルの確認方法

### ログファイルの場所

- **Windows**: `%LOCALAPPDATA%\after_app\logs\crash_*.log`
  - 例: `C:\Users\<USERNAME>\AppData\Local\after_app\logs\crash_2026-01-07T18-47-24.log`
- **その他**: `%USERPROFILE%\Documents\after_app\logs\crash_*.log`

### 重要なログエントリ

#### 起動時
```
[main] VM Service URL: http://127.0.0.1:56805/dp1Anzcabm4=/
[main] VM Service WebSocket: ws://127.0.0.1:56805/dp1Anzcabm4=/ws
[main] Process ID: 12345
[main] To reconnect: flutter attach --debug-url=ws://127.0.0.1:56805/dp1Anzcabm4=/ws
```

#### 接続状態チェック（10秒ごと）
```
[SERVICE_CHECK] VM Service is alive
[SERVICE_CHECK] URL: http://127.0.0.1:56805/dp1Anzcabm4=/
[SERVICE_CHECK] WebSocket: ws://127.0.0.1:56805/dp1Anzcabm4=/ws
```

#### 接続が切れた場合
```
[SERVICE_CHECK] Connection lost! Check log file for VM Service URL to reconnect.
```

#### ハートビート（1秒ごと）
```
[HEARTBEAT] pid=12345 timestamp=2026-01-07T18:47:24.422868
```

## よくある問題と対処

### 問題1: ポートが既に使用されている

**症状:**
```
Error: Port 56805 is already in use
```

**対処:**
- `--vm-service-port=0` を使用して自動割り当て
- または別のポートを指定: `--vm-service-port=56806`

### 問題2: 認証コードが一致しない

**症状:**
```
Error: Authentication failed
```

**対処:**
- `--disable-service-auth-codes` を使用して認証を無効化

### 問題3: 接続が不安定

**症状:**
- 一定時間後に「Lost connection」が発生

**対処:**
1. 推奨オプションを使用して起動
2. ログファイルでVM Service URLを確認
3. 切断後、`flutter attach`で再接続

## 自動再接続スクリプト（PowerShell）

切断を検知して自動的に再接続するスクリプト：

```powershell
# reconnect.ps1
$logFile = Get-ChildItem "$env:LOCALAPPDATA\after_app\logs\crash_*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$content = Get-Content $logFile -Raw
if ($content -match "VM Service WebSocket: (ws://[^\s]+)") {
    $url = $matches[1]
    Write-Host "Reconnecting to: $url"
    flutter attach --debug-url $url
} else {
    Write-Host "VM Service URL not found in log file"
}
```

使用方法：
```powershell
.\reconnect.ps1
```

## 参考情報

- [Flutter Debugging](https://docs.flutter.dev/tools/debugging)
- [Flutter Attach](https://docs.flutter.dev/tools/cli/attach)

