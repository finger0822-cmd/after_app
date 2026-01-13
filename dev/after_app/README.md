# After

自分の言葉を少し先の自分にだけ送れる場所。

## ライフサイクル契約(v2)について

本アプリケーションは、**ライフサイクル契約(v2)**を実装・検証済みです。

### 保証されること

- **タイマー管理の一元化**: デバッグ用タイマー（Heartbeat/Service diagnostics）は一元管理され、多重起動が発生しません
- **確実な停止保証**: アプリ終了時（detached/dispose/isolate exit）にタイマーが確実に停止します
- **ログレベルの制御**: デフォルトでは詳細ログ（Heartbeat等）は出力されず、必要時のみ有効化できます

詳細は[責務分界・保証範囲](docs/SCOPE_AND_LIMITS.md)を参照してください。

### 保証しないこと

- 端末固有のバグ（OS固有の不具合、ハードウェア固有の問題）
- OS側制限（システム制限、メモリ不足時の動作）
- 外部SDKの不具合（Flutter SDK、依存パッケージのバグ）
- 設定変更の影響（`kEnableTraceLogs`フラグ変更による動作変化）

詳細は[責務分界・保証範囲](docs/SCOPE_AND_LIMITS.md)を参照してください。

### 解決する問題

- デバッグログの暴走によるログファイル肥大化の防止
- アプリ終了後のタイマー残響によるリソースリークの防止
- デバッグ情報の適切な管理

### 想定利用者

- 個人利用者（メッセージ管理アプリとして使用）
- 開発者（デバッグ機能を活用する場合）

### 向かない利用者

- Webブラウザでの利用（Isarデータベースの制約により非対応）

### 導入の考え方

ライフサイクル契約(v2)は、アプリケーションの**契約部品**として実装されています。設定変更や機能追加を行う場合は、契約に影響する変更がないか確認してください。

### ドキュメント

詳細は以下のドキュメントを参照してください：

- [ドキュメント目次](docs/INDEX.md)
- [責務分界・保証範囲](docs/SCOPE_AND_LIMITS.md)
- [運用・トラブルシュート](docs/OPERATIONS.md)
- [Releaseビルド注意点](docs/RELEASE_CHECK.md)
- [検証結果](LIFECYCLE_CONTRACT_V2_VERIFICATION.md)

---

## 注意事項

**⚠️ Web非対応（Isarのため）**

このアプリはIsarデータベースを使用しているため、Webプラットフォーム（Chrome/Edge）では動作しません。
以下のプラットフォームでのみ実行・ビルド可能です：

- Windows（デスクトップ）
- Android（エミュレータ/実機）
- iOS（シミュレータ/実機）

## セットアップ

### 前提条件

- Flutter SDK 3.0.0以上
- Dart SDK 3.0.0以上
- 以下のいずれか：
  - Windows: 
    - Visual Studio（Desktop development with C++）または
    - Developer Modeを有効化（設定 > プライバシーとセキュリティ > 開発者向け > Developer Mode）
  - Android: Android Studio + Android SDK
  - iOS: Xcode（macOSのみ）

#### Windowsでの注意事項

Windowsでプラグインを使用するには、**Developer Mode**を有効にする必要があります：

1. `Win + I` で設定を開く
2. 「プライバシーとセキュリティ」→「開発者向け」を選択
3. 「Developer Mode」をオンにする
4. 再起動を求められた場合は再起動

または、コマンドで設定を開く：
```bash
start ms-settings:developers
```

### 依存関係のインストール

```bash
flutter pub get
```

### Isarコード生成

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

## 実行方法

### Windows

#### 基本実行

```bash
flutter run -d windows
```

#### 推奨オプション（VM Service接続の安定化）

Windows Desktopで「Lost connection to device」が発生する場合、以下のオプションを追加してください：

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

#### 「Lost connection」発生時の対処

1. **プロセス確認**
   ```powershell
   Get-Process | Where-Object {$_.ProcessName -like "*after_app*"}
   ```

2. **VM Service URL確認**
   - ログファイルを確認: `%LOCALAPPDATA%\after_app\logs\crash_*.log`
   - `VM Service URL:` で始まる行を探す

3. **ポート確認**
   ```cmd
   netstat -ano | findstr <port>
   ```
   （`<port>`はVM Service URLのポート番号）

4. **再接続**
   ```bash
   flutter attach --debug-url <VM Service URL>
   ```
   （`<VM Service URL>`はログファイルに記録されたURL）

#### ログファイルの場所

- Windows: `%LOCALAPPDATA%\after_app\logs\crash_*.log`
- その他: `%USERPROFILE%\Documents\after_app\logs\crash_*.log`

### Android

```bash
# エミュレータを起動するか、実機を接続
flutter run -d android
```

### iOS

```bash
# シミュレータを起動するか、実機を接続
flutter run -d ios
```

## ビルド方法

### Windows

```bash
flutter build windows
```

### Android

```bash
flutter build apk
# または
flutter build appbundle
```

### iOS

```bash
flutter build ios
```

## 機能

- **NowPage**: メッセージを入力して封印日を設定
- **AfterPage**: 開封済みメッセージの閲覧と検索
- **封印中管理**: 封印中のメッセージの日付変更・削除（本文は非表示）
- **ローカル通知**: 封印解除日の通知（Asia/Tokyo、朝9:00）

## 技術スタック

- Flutter
- Riverpod（状態管理）
- Isar（ローカルデータベース）
- flutter_local_notifications（通知）
- timezone（タイムゾーン管理）
