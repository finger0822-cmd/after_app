# Windows 実行手順（混線防止版）

## 目的

one_day_app と after_app の混線を防ぐため、確実に one_day_app を実行する手順を記載します。

## 前提条件

- 現在のディレクトリが `one_day_app` であることを確認
- 他のプロジェクト（after_app など）の build/ephemeral が混在しないようにする

## クリーンビルド手順（推奨）

以下の PowerShell コマンドを順番に実行してください。

```powershell
# 1. one_day_app ディレクトリに移動（必須）
cd C:\Users\taker\develop\flutter\dev\one_day_app

# 2. Flutter のクリーン
flutter clean

# 3. ephemeral ディレクトリを削除（特に .plugin_symlinks を削除）
Remove-Item -Recurse -Force .\windows\flutter\ephemeral -ErrorAction SilentlyContinue

# 4. build ディレクトリを削除
Remove-Item -Recurse -Force .\build -ErrorAction SilentlyContinue

# 5. 依存関係を取得
flutter pub get

# 6. アプリを実行
flutter run -d windows
```

## ワンライナー（コピペ用）

```powershell
cd C:\Users\taker\develop\flutter\dev\one_day_app; flutter clean; Remove-Item -Recurse -Force .\windows\flutter\ephemeral -ErrorAction SilentlyContinue; Remove-Item -Recurse -Force .\build -ErrorAction SilentlyContinue; flutter pub get; flutter run -d windows
```

## 確認ポイント

### 起動ログ
```
[OneDayApp] main ok
```

### UI表示
- 画面中央に **"One Day (one_day_app)"** と表示されること
- AppBar に **"One Day"** と表示されること

### 実行ファイル
- `build\windows\x64\runner\Release\one_day_app.exe` が生成されること
- `after_app.exe` が生成されないこと

### エラー確認
- `PathExistsException` が出ないこと
- `Lost connection` が出ないこと
- `[NowSheet]` のログが出ないこと（After アプリのログが出ないこと）

## トラブルシューティング

### PathExistsException が出る場合

```powershell
# ephemeral を強制削除
Remove-Item -Recurse -Force .\windows\flutter\ephemeral -ErrorAction SilentlyContinue

# 再度実行
flutter run -d windows
```

### after_app.exe が生成される場合

- 現在のディレクトリが `one_day_app` であることを確認
- `flutter clean` を実行してから再ビルド

### UI が After アプリのままの場合

- `lib/main.dart` が `OneDayApp` を起動しているか確認
- `lib/one_day_app.dart` が存在し、正しく表示されているか確認
- クリーンビルドを実行
