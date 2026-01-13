# クラッシュログ実装レポート

## 実装内容

### 1. グローバル例外ハンドラの強化

#### 変更ファイル: `after_app/lib/main.dart`

**追加内容:**
- `CrashLogger`を最初に初期化
- `FlutterError.onError`: 例外内容とスタックトレースを標準出力とファイルの両方に出力
- `PlatformDispatcher.instance.onError`: プラットフォームレベルの例外を捕捉してログ出力
- `runZonedGuarded`: 未捕捉例外を捕捉してログ出力
- 各初期化ステップでログを出力（Database、NotificationServiceなど）

**ログ出力例:**
```
[main] === FlutterError ===
[main] Time: 2026-01-07T18:47:24.422868
[main] Exception: Exception: ...
[main] Stack: ...
[main] Library: ...
[main] Context: ...
[main] ===================
```

### 2. クラッシュログファイルへの書き込み

#### 新規ファイル: `after_app/lib/core/crash_logger.dart`

**機能:**
- Windowsのユーザーデータ配下（`%USERPROFILE%\Documents\after_app\logs\`）にログファイルを作成
- ファイル名: `crash_YYYY-MM-DDTHH-MM-SS.log`
- 標準出力とファイルの両方にログを書き込む
- 例外情報を構造化して記録

**ログファイルの場所:**
```
C:\Users\<USERNAME>\Documents\after_app\logs\crash_2026-01-07T18-47-24.log
```

**ログフォーマット:**
```
[2026-01-07T18:47:24.422868] [INFO] [main] START
[2026-01-07T18:47:24.422868] [EXCEPTION] === EXCEPTION ===
Context: FlutterError: ...
Time: 2026-01-07T18:47:24.422868
Error: ...
Error Type: ...
Stack:
...
================
```

### 3. Windows Runner側のクラッシュログ

#### 変更ファイル: `after_app/windows/runner/main.cpp`

**追加内容:**
- `SetUnhandledExceptionFilter`: Windowsの未処理例外を捕捉
- 各初期化ステップで標準出力にログを出力
- C++例外をtry-catchで捕捉

**ログ出力例:**
```
[Windows Runner] === START ===
[Windows Runner] Instance: 0x...
[Windows Runner] Command Line: ...
[Windows Runner] COM initialized
[Windows Runner] DartProject created
[Windows Runner] Creating window...
[Windows Runner] Window created successfully
[Windows Runner] Entering message loop...
```

**未処理例外時のログ:**
```
[Windows Runner] === UNHANDLED EXCEPTION ===
[Windows Runner] Exception Code: 0x...
[Windows Runner] Exception Address: 0x...
```

### 4. Isar Inspectorの無効化（Windows Debug環境）

#### 変更ファイル: `after_app/lib/data/db.dart`

**追加内容:**
- Windows Debug環境ではIsar Inspectorを無効化
- `inspector: !(Platform.isWindows && kDebugMode)` を設定

**理由:**
- Isar InspectorはWebSocketを使用してVM Serviceと干渉する可能性がある
- Windows Debug環境での「Lost connection」を回避するため

**ログ出力:**
```
[Database] Opening Isar...
[Database] Platform: windows
[Database] Debug Mode: true
[Database] Inspector Enabled: false
[Database] Isar opened successfully
```

## ログの確認方法

### 1. 標準出力（flutter run）
- `flutter run`のコンソールにリアルタイムで表示される
- 「Lost connection」が発生した場合、直前のログを確認

### 2. ログファイル
- 場所: `%USERPROFILE%\Documents\after_app\logs\crash_*.log`
- 「Lost connection」発生後、ログファイルを確認してアプリがクラッシュしたかどうかを判断

## 「Lost connection」の切り分け方法

### アプリがクラッシュした場合
以下のログが出力される:
1. `[main] === FlutterError ===` または `[main] === PlatformDispatcher Error ===`
2. `[Windows Runner] === UNHANDLED EXCEPTION ===`
3. ログファイルに例外情報が記録される

### flutter runが落ちただけの場合
- アプリ側のログは正常に出力される
- Windows Runner側のログも正常に出力される
- ログファイルに例外情報は記録されない
- 「Lost connection」の直前のログを確認して、どの処理中に発生したかを特定

## 追加されるログの例

### 正常な起動時
```
[main] START - 2026-01-07T18:47:19.583755
[main] runZonedGuarded START
[main] WidgetsFlutterBinding initialized
[main] date format initialized
[main] Initializing Database...
[Database] Opening Isar...
[Database] Platform: windows
[Database] Debug Mode: true
[Database] Inspector Enabled: false
[Database] Isar opened successfully
[main] Database initialized
[main] Initializing NotificationService...
[main] NotificationService initialized, permission: true
[main] Starting app...
[main] App started
```

### 例外発生時
```
[main] === FlutterError ===
[main] Time: 2026-01-07T18:47:24.422868
[main] Exception: Exception: ...
[main] Stack: ...
[main] Library: ...
[main] Context: ...
[main] ===================
```

### Windows Runner側のクラッシュ時
```
[Windows Runner] === UNHANDLED EXCEPTION ===
[Windows Runner] Exception Code: 0xC0000005
[Windows Runner] Exception Address: 0x...
```

## 次のステップ

1. アプリを再起動して動作確認
2. 「Lost connection」が発生した場合、ログファイルを確認
3. ログから原因箇所を特定
4. 必要に応じて追加の対策を実装

