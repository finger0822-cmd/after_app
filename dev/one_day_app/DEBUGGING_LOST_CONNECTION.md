# Lost Connection デバッグ手順

## 実装した機能

### 1. ハートビートログ
- 1秒ごとに `[HEARTBEAT] pid=<pid> timestamp=...` をログファイルに出力
- 「Lost connection」発生時に、アプリが生きているかログファイルから判断可能

### 2. Future.delayed コールバックの詳細ログ
- `mounted` チェック前後をログ出力
- `setState` 前後をログ出力
- 例外を `CrashLogger` に記録
- dispose 後に実行された場合もログに記録

### 3. Windows ネイティブクラッシュ採取
- `std::set_terminate`: C++例外を捕捉
- `std::signal`: SIGABRT, SIGFPE, SIGILL, SIGSEGV, SIGTERM を捕捉
- `SetUnhandledExceptionFilter`: SEH例外を捕捉

### 4. プラグイン初期化の段階的無効化
- `lib/core/debug_flags.dart` でフラグを設定
- Database, NotificationService, NotificationScheduling を個別に無効化可能

## 切断時の切り分け手順

### ステップ1: ログファイルを確認

ログファイルの場所: `%USERPROFILE%\Documents\after_app\logs\crash_*.log`

#### アプリがクラッシュした場合
以下のログが出力される:
- `[HEARTBEAT]` が突然停止する
- `[EXCEPTION]` または `[Windows Runner] === UNHANDLED EXCEPTION ===` が出力される
- 最後の `[HEARTBEAT]` のタイムスタンプを確認

#### flutter run が落ちただけの場合
- `[HEARTBEAT]` は継続して出力される（アプリは生きている）
- 例外ログは出力されない
- 「Lost connection」の直前のログを確認

### ステップ2: プロセス確認

#### PowerShell でプロセスを確認
```powershell
# after_app.exe が実行中か確認
Get-Process | Where-Object {$_.ProcessName -like "*after_app*"}

# プロセスIDを確認
Get-Process | Where-Object {$_.ProcessName -like "*after_app*"} | Select-Object Id, ProcessName, StartTime
```

#### 「Lost connection」発生時の確認
1. ログファイルで最後の `[HEARTBEAT]` のタイムスタンプを確認
2. PowerShell でプロセスが生きているか確認
3. プロセスが生きている場合 → flutter tool の問題
4. プロセスが死んでいる場合 → アプリクラッシュ

### ステップ3: Windows Event Viewer を確認

#### イベントビューアーでクラッシュ情報を確認
1. `Win + R` → `eventvwr.msc`
2. Windows ログ → アプリケーション
3. 「Lost connection」発生時刻付近のエラーを確認
4. イベントID 1000 (Application Error) を確認

### ステップ4: デバッガーでアタッチ

#### Visual Studio でアタッチ
1. Visual Studio を起動
2. デバッグ → プロセスにアタッチ
3. `after_app.exe` を選択
4. 「Lost connection」発生時にブレークポイントで停止

#### WinDbg でアタッチ
```cmd
# WinDbg を起動
windbg -pn after_app.exe

# クラッシュ時に自動的に停止
```

### ステップ5: Minidump を取得

#### レジストリで Minidump を有効化
```reg
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps]
"DumpFolder"="C:\\dumps"
"DumpType"=dword:00000002
"Auto"=dword:00000001
```

#### Minidump の場所
- `C:\dumps\after_app.exe.<timestamp>.dmp`

## プラグイン初期化の段階的無効化

### `lib/core/debug_flags.dart` を編集

```dart
class DebugFlags {
  /// Database (Isar) の初期化を無効化
  static const bool disableDatabase = true;  // ← true に変更
  
  /// NotificationService の初期化を無効化
  static const bool disableNotificationService = true;  // ← true に変更
  
  /// 通知スケジュール処理を無効化
  static const bool disableNotificationScheduling = true;  // ← true に変更
  
  /// すべてのプラグイン初期化を無効化
  static const bool disableAllPlugins = false;  // ← true にすると全て無効化
}
```

### 二分探索の手順

1. **すべて無効化**: `disableAllPlugins = true`
   - 「Lost connection」が発生しない → プラグイン初期化が原因
   - 「Lost connection」が発生する → プラグイン以外が原因

2. **個別に有効化**: 1つずつ `false` に戻す
   - Database を有効化 → 発生する → Database が原因
   - NotificationService を有効化 → 発生する → NotificationService が原因

## 追加ログの例

### 正常な動作時
```
[2026-01-07T18:47:24.422868] [INFO] [main] START
[2026-01-07T18:47:24.422868] [HEARTBEAT] pid=12345 timestamp=2026-01-07T18:47:24.422868
[2026-01-07T18:47:25.422868] [HEARTBEAT] pid=12345 timestamp=2026-01-07T18:47:25.422868
[2026-01-07T18:47:26.422868] [HEARTBEAT] pid=12345 timestamp=2026-01-07T18:47:26.422868
```

### 「Lost connection」発生時（アプリクラッシュ）
```
[2026-01-07T18:47:24.422868] [HEARTBEAT] pid=12345 timestamp=2026-01-07T18:47:24.422868
[2026-01-07T18:47:25.422868] [HEARTBEAT] pid=12345 timestamp=2026-01-07T18:47:25.422868
[2026-01-07T18:47:26.422868] [EXCEPTION] === EXCEPTION ===
Context: NowSheet Windows Future.delayed
Error: ...
Stack: ...
```

### 「Lost connection」発生時（flutter tool の問題）
```
[2026-01-07T18:47:24.422868] [HEARTBEAT] pid=12345 timestamp=2026-01-07T18:47:24.422868
[2026-01-07T18:47:25.422868] [HEARTBEAT] pid=12345 timestamp=2026-01-07T18:47:25.422868
[2026-01-07T18:47:26.422868] [HEARTBEAT] pid=12345 timestamp=2026-01-07T18:47:26.422868
[2026-01-07T18:47:27.422868] [HEARTBEAT] pid=12345 timestamp=2026-01-07T18:47:27.422868
# ← ハートビートは継続（アプリは生きている）
```

## 次のステップ

1. アプリを再起動して動作確認
2. 「Lost connection」発生時にログファイルを確認
3. プロセスが生きているか確認
4. 必要に応じてプラグイン初期化を無効化して原因を特定

