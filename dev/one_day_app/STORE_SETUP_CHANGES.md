# ストア提出用設定変更まとめ

## 実施日
2026-01-11

## 目的
one_day_appを「Android/iOS/Windowsでストア提出できる土台」に整備

## 変更内容

### 1. パッケージID/Bundle IDの統一

#### Android
- **ファイル**: `android/app/build.gradle.kts`
- **変更**: 
  - `namespace = "com.example.after_app"` → `namespace = "com.taker.oneday"`
  - `applicationId = "com.example.after_app"` → `applicationId = "com.taker.oneday"`

- **ファイル**: `android/app/src/main/kotlin/com/taker/oneday/MainActivity.kt`
- **変更**: 
  - パッケージディレクトリを `com/example/after_app` → `com/taker/oneday` に移動
  - `package com.example.after_app` → `package com.taker.oneday`

- **ファイル**: `android/app/src/main/kotlin/com/taker/oneday/MainActivity.kt`
- **変更**: 
  - パッケージディレクトリを `com/example/after_app` → `com/taker/oneday` に移動
  - `package com.example.after_app` → `package com.taker.oneday`

#### iOS
- **ファイル**: `ios/Runner.xcodeproj/project.pbxproj`
- **変更**: 
  - `PRODUCT_BUNDLE_IDENTIFIER = com.example.afterApp;` → `PRODUCT_BUNDLE_IDENTIFIER = com.taker.oneday;` (6箇所)
  - `PRODUCT_BUNDLE_IDENTIFIER = com.example.afterApp.RunnerTests;` → `PRODUCT_BUNDLE_IDENTIFIER = com.taker.oneday.RunnerTests;` (3箇所)

### 2. 表示名を"one day"に設定

#### Android
- **ファイル**: `android/app/src/main/AndroidManifest.xml`
- **変更**: `android:label="after_app"` → `android:label="one day"`

#### iOS
- **ファイル**: `ios/Runner/Info.plist`
- **変更**: 
  - `CFBundleDisplayName`: `After App` → `one day`
  - `CFBundleName`: `after_app` → `one_day_app`

#### Windows
- **ファイル**: `windows/runner/Runner.rc`
- **変更**: 
  - `CompanyName`: `com.example` → `com.taker`
  - `FileDescription`: `after_app` → `one day`
  - `InternalName`: `after_app` → `one_day_app`
  - `OriginalFilename`: `after_app.exe` → `one_day_app.exe`
  - `ProductName`: `after_app` → `one day`
  - `LegalCopyright`: `com.example` → `com.taker`

### 3. pubspec.yaml

- **ファイル**: `pubspec.yaml`
- **状態**: `name: one_day_app` のまま（変更なし、OK）

### 4. 24時間自動消去機能の追加

#### MessageRepo
- **ファイル**: `lib/data/message_repo.dart`
- **追加メソッド**:
  - `deleteMessagesOlderThan24Hours()`: 24時間以上経過したメッセージを削除
  - `getMessagesWithin24Hours()`: 24時間以内のメッセージのみ取得

#### main.dart
- **ファイル**: `lib/main.dart`
- **変更**: Database初期化後に、起動時に期限切れメッセージを自動削除する処理を追加

## 変更ファイル一覧

1. `android/app/build.gradle.kts` - namespace, applicationId
2. `android/app/src/main/AndroidManifest.xml` - android:label
3. `ios/Runner.xcodeproj/project.pbxproj` - PRODUCT_BUNDLE_IDENTIFIER (9箇所)
4. `ios/Runner/Info.plist` - CFBundleDisplayName, CFBundleName
5. `windows/runner/Runner.rc` - 各種文字列リソース
6. `lib/data/message_repo.dart` - 24時間自動消去メソッド追加
7. `lib/main.dart` - 起動時に期限切れメッセージを削除

## 手動で実施が必要な作業

### Android

1. **署名設定**（リリースビルド用）
   - `android/app/build.gradle.kts`の`signingConfig`をリリース用に設定
   - `key.properties`ファイルの作成（推奨）
   - `keystore.jks`の生成（未作成の場合）

2. **Play Console登録**
   - Google Play Consoleでアプリを作成
   - パッケージ名: `com.taker.oneday`
   - アプリ名: `one day`

### iOS

1. **証明書とプロビジョニングプロファイルの設定**
   - Apple Developerアカウントで証明書を作成
   - Bundle ID: `com.taker.oneday` でプロビジョニングプロファイルを作成
   - Xcodeで証明書とプロファイルを設定

2. **App Store Connect登録**
   - App Store Connectでアプリを作成
   - Bundle ID: `com.taker.oneday`
   - アプリ名: `one day`

### Windows

1. **Microsoft Store登録**（任意）
   - Microsoft Partner Centerでアプリを作成
   - パッケージ名の設定

## ビルド確認

### Android
```bash
flutter build appbundle --release
```

### iOS
```bash
flutter build ios --release
```

### Windows
```bash
flutter build windows --release
```

## 注意事項

- 現在のAndroidビルド設定は、リリースビルドでもデバッグキーを使用しています（`signingConfig = signingConfigs.getByName("debug")`）
- ストア提出前に、リリース用の署名設定に変更する必要があります
- iOSのビルドには、適切な証明書とプロビジョニングプロファイルが必要です
