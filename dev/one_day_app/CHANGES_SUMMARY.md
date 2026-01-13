# 変更サマリー

## 完了した作業

### 1. パッケージID/Bundle IDの統一（com.taker.oneday）

- ✅ Android: `build.gradle.kts` (namespace, applicationId)
- ✅ Android: `MainActivity.kt` (パッケージ名、ディレクトリ移動)
- ✅ iOS: `project.pbxproj` (PRODUCT_BUNDLE_IDENTIFIER, 9箇所)

### 2. 表示名を"one day"に設定

- ✅ Android: `AndroidManifest.xml` (android:label)
- ✅ iOS: `Info.plist` (CFBundleDisplayName, CFBundleName)
- ✅ Windows: `Runner.rc` (各種文字列リソース)

### 3. 24時間自動消去機能の追加

- ✅ `message_repo.dart`: `deleteMessagesOlderThan24Hours()`, `getMessagesWithin24Hours()` 追加
- ✅ `main.dart`: 起動時に期限切れメッセージを自動削除

## 変更ファイル一覧（8ファイル）

1. `android/app/build.gradle.kts`
2. `android/app/src/main/AndroidManifest.xml`
3. `android/app/src/main/kotlin/com/taker/oneday/MainActivity.kt` (ディレクトリ移動)
4. `ios/Runner.xcodeproj/project.pbxproj`
5. `ios/Runner/Info.plist`
6. `windows/runner/Runner.rc`
7. `lib/data/message_repo.dart`
8. `lib/main.dart`

詳細は `STORE_SETUP_CHANGES.md` を参照してください。
