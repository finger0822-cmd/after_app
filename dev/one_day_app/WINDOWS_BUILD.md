# Windows ビルド/実行手順（One Day App）

## クリーンビルド手順（PathExistsException 対策）

Windows で `PathExistsException: windows/flutter/ephemeral/.plugin_symlinks/...` エラーが出る場合は、以下の手順でクリーンビルドを実行してください。

### PowerShell コマンド

```powershell
cd C:\Users\taker\develop\flutter\dev\one_day_app

# 1. Flutter のクリーン
flutter clean

# 2. ephemeral ディレクトリを削除（特に .plugin_symlinks）
if (Test-Path "windows\flutter\ephemeral") {
    Remove-Item -Recurse -Force "windows\flutter\ephemeral"
    Write-Host "Removed windows\flutter\ephemeral" -ForegroundColor Green
}

# 3. 依存関係を取得
flutter pub get

# 4. アプリを実行
flutter run -d windows
```

### 削除対象

- `windows/flutter/ephemeral/.plugin_symlinks/` ディレクトリ全体

### エラー例

```
PathExistsException: windows/flutter/ephemeral/.plugin_symlinks/isar_flutter_libs (errno 183)
```

このエラーは、過去のビルドで作成されたシンボリックリンクが残っている場合に発生します。

## 確実に one_day_app を実行する方法

他のプロジェクト（例: after_app）と混同しないように、必ず `one_day_app` ディレクトリで実行してください。

```powershell
# 現在のディレクトリを確認
pwd

# one_day_app ディレクトリに移動
cd C:\Users\taker\develop\flutter\dev\one_day_app

# アプリを実行
flutter run -d windows
```

### 確認ポイント

- 実行ファイル: `build\windows\x64\runner\Release\one_day_app.exe` が生成されること
- 起動ログ: `[OneDayApp] main ok` が表示されること
- UI: 「One Day」と表示されること
