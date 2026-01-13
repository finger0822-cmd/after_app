# ストア提出前チェックリスト

## A. Release ビルドでのデバッグ機能排除確認（最重要）

### 実行手順

```powershell
cd C:\Users\taker\develop\flutter\dev\one_day_app
flutter clean
flutter build windows --release
start build\windows\x64\runner\Release\one_day_app.exe
```

### チェック項目

#### A-1. デバッグ機能が物理的に存在しないこと

- [ ] 「-25h」ボタンが存在しない（AppBar右側に表示されない）
- [ ] UI上にデバッグ関連の文言・ボタン・メニューが一切ない
- [ ] ショートカットキー/隠し操作でもデバッグ機能が起動できない
- [ ] コンソールに `[OneDayHomePage] Debug:` 系のログが出ない
- [ ] コンソールに `[OneDayRepo]` 系のログが出ない（kDebugMode ガード済み）

#### A-2. 通常機能の動作確認

- [ ] メッセージ追加が正常に動作する
- [ ] メッセージ一覧が正しく表示される（新しい順）
- [ ] 残り時間表示が正しく表示される
- [ ] アプリ再起動後もメッセージが残る（永続化確認）

### 期待結果

Release ビルドでは `kDebugMode` が `false` のため、デバッグ機能は実行されず、ログも出力されません。`assert()` も無効化されるため、デバッグコードは完全に除外されます。

## B. ビルド成果物の取り違え防止チェック

### 実行手順

```powershell
cd C:\Users\taker\develop\flutter\dev\one_day_app
dir build\windows\x64\runner\Release\*.exe
```

### チェック項目

- [ ] `one_day_app.exe` のみが存在する
- [ ] `after_app.exe` が紛れていない
- [ ] その他の不要な `.exe` ファイルが存在しない

### Version Info 確認

1. `build\windows\x64\runner\Release\one_day_app.exe` を右クリック
2. 「プロパティ」→「詳細」タブを開く

#### チェック項目

- [ ] **会社名**: `taker`
- [ ] **ファイルの説明**: `One Day`
- [ ] **製品名**: `One Day`
- [ ] **内部名**: `One Day`
- [ ] **著作権**: `Copyright (C) 2026 taker. All rights reserved.`
- [ ] **元のファイル名**: `one_day_app.exe`

### 設定ファイル

- `windows/runner/Runner.rc`: Version Info の定義

## C. バージョン番号・表示名の整合確認

### チェック項目

#### C-1. pubspec.yaml のバージョン

- [ ] `version: 1.0.0+1` が提出用に適切に設定されている
- [ ] ストア側の「バージョン」「ビルド番号」と矛盾していない

#### C-2. 表示名の整合

- [ ] アプリ名: `One Day`
- [ ] ストア表示名と端末表示名が一致している

### 確認ファイル

- `pubspec.yaml`: `version:` フィールド
- `windows/runner/Runner.rc`: `ProductName`, `FileDescription`
- `windows/runner/main.cpp`: ウィンドウタイトル

## D. アプリ名・表示名・パッケージIDの整合（Android/iOS対応時）

### チェック項目

#### D-1. 表示名

- [ ] 表示名: `One Day`
- [ ] ストア表示名と端末表示名が一致

#### D-2. パッケージID / Bundle ID

- [ ] Android Package ID: `com.taker.oneday`（変更しない）
- [ ] iOS Bundle ID: `com.taker.oneday`（変更しない）
- [ ] 後から変更しない（変更が痛いため）

### 確認ファイル

- `android/app/build.gradle.kts`: `applicationId`
- `ios/Runner.xcodeproj/project.pbxproj`: `PRODUCT_BUNDLE_IDENTIFIER`
- `pubspec.yaml`: `name: one_day_app`

## E. プライバシー/データ取り扱い確認

### チェック項目

#### E-1. データ収集

- [ ] 収集データ: 基本なし（SharedPreferencesでローカルのみ）
- [ ] ネットワーク通信: なし（ある場合は目的を明記）

#### E-2. 自動削除仕様

- [ ] 「24時間で自動削除」仕様が説明文と一致
- [ ] ユーザーに明示されている（アプリ説明文等）

### プライバシーポリシー記載例

```
- データ保存: 端末ローカルのみ（SharedPreferences）
- ネットワーク通信: なし
- データ保持期間: 24時間（自動削除）
- データ共有: なし
```

## F. 24時間消去の境界条件テスト（提出前の再現性確認）

### チェック項目

#### F-1. 境界条件

- [ ] **24:00:00 ちょうど**: 残す（`diff <= Duration(hours: 24)` の条件）
- [ ] **24:00:01 超え**: 消える（24時間を超えた場合）

#### F-2. 削除タイミング

- [ ] **起動時**: 24時間経過したメッセージが削除される
- [ ] **復帰時（resumed）**: 24時間経過したメッセージが削除される

#### F-3. デバッグ機能での確認（Debug ビルドのみ）

- [ ] 「-25h」ボタンで即座に削除される（24時間超のため）
- [ ] ログに `cleanupExpired deleted=X remain=Y` が表示される

### 実装確認

- `lib/data/one_day_repo.dart`: `cleanupExpired()` の判定ロジック
  ```dart
  return diff <= const Duration(hours: 24);  // 24時間ピッタリは残す
  ```

## 追加確認項目

### ログ順序確認（Debug ビルド）

#### 期待されるログ順序

```
[OneDayApp] main ok
[OneDayHomePage] init
[OneDayRepo] cleanupExpired deleted=.. remain=..
```

#### 確認ポイント

- [ ] `main ok` より前に `cleanupExpired` が出ない
- [ ] ログが正しい順序で出力される

### 今後の検討事項

#### Android/iOS 対応時のデータ保存方法

**現状**: SharedPreferences（JSON形式）で保存

**検討ポイント**:
- 端末移行/バックアップ要件
- データの永続性要件
- パフォーマンス要件

**選択肢**:
1. SharedPreferences のまま（軽量、端末ローカルのみ）
2. Isar データベース（高速、端末ローカルのみ）
3. クラウド同期（Firebase等、端末間同期可能）

**推奨**: アプリの思想（「One Day」= 24時間で消える一時的なメモ）を考慮し、SharedPreferences のままで良い可能性が高い。

## チェックリスト実行手順

1. **A. Release ビルドでのデバッグ機能排除確認**（最重要）
2. **B. ビルド成果物の取り違え防止チェック**
3. **C. バージョン番号・表示名の整合確認**
4. **D. アプリ名・表示名・パッケージIDの整合**（Android/iOS対応時）
5. **E. プライバシー/データ取り扱い確認**
6. **F. 24時間消去の境界条件テスト**

すべての項目にチェックが入ったら、ストア提出準備完了です。
