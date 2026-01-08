# 責務分界・保証範囲・非保証範囲

## 保証すること

### タイマー一元管理

- デバッグ用タイマー（Heartbeat/Service diagnostics）は`CrashLogger`クラスで一元管理されます
- タイマーの生成は`crash_logger.dart`のみで行われます
- 多重起動は発生しません（冪等性保証）

### 停止保証

- アプリ終了時（`AppLifecycleState.detached`、`dispose()`、`isolate exit`）にタイマーが確実に停止します
- `stopAllTimers()`はassert外で実装されており、Releaseビルドでも確実に実行されます
- アプリ終了後のログ残響は発生しません

### ログレベル契約

- デフォルト（`kEnableTraceLogs=false`）では、詳細ログ（Heartbeat/Service alive）は出力されません
- Traceログは明示的に有効化（`kEnableTraceLogs=true`）した場合のみ出力されます
- ログレベル判定は`messageLevel.index >= _currentLevel.index`で行われます

## 保証しないこと

### 端末固有のバグ

- OS固有の不具合や制限
- ハードウェア固有の問題
- ドライバー関連の不具合

### OS側制限

- Windows/Android/iOSのシステム制限
- メモリ不足時の動作
- バッテリー節約モード時の動作制限

### 外部SDK

- Flutter SDKのバグ
- 依存パッケージ（Isar、Riverpod等）の不具合
- プラットフォーム固有プラグインの制約

### 設定変更の影響

- `kEnableTraceLogs`フラグの変更による動作変化
- ログレベルの手動変更による予期しない動作
- コード改変による契約違反

## 利用者側の責務

### ログ保管

- ログファイルは適切に保管してください
- ログファイル名は`crash_YYYY-MM-DDTHH-mm-ss.log`形式です（実装に従う）
- ログファイルの場所は実装に従います：
  - Windows: `%LOCALAPPDATA%\after_app\logs\`（実装: `crash_logger.dart`の`initialize()`メソッド）
  - その他: `getApplicationDocumentsDirectory()/after_app/logs/`（実装: `crash_logger.dart`の`initialize()`メソッド）

### 設定変更の手順遵守

- `kEnableTraceLogs`フラグを変更する場合は、[運用ドキュメント](OPERATIONS.md)の手順に従ってください
- 設定変更後は動作確認を行ってください

### 変更時の再検証

- ライフサイクル契約(v2)に影響する改変を行った場合は、再検証が必須です
- 影響する改変の例：
  - `CrashLogger`クラスの変更
  - タイマー管理ロジックの変更
  - ライフサイクルイベント処理の変更
  - `stopAllTimers()`の実装変更

再検証は[検証ドキュメント](../LIFECYCLE_CONTRACT_V2_VERIFICATION.md)に従って実施してください。

## 変更時の再検証要件

契約(v2)に影響する改変は、以下のテストを再実施する必要があります：

1. **テスト1**: `kEnableTraceLogs=false`で起動し、45秒待機。`[HEARTBEAT]`と`[SERVICE_CHECK] VM Service is alive`が0件であることを確認
2. **テスト2**: `kEnableTraceLogs=true`で起動し、45秒待機。`[HEARTBEAT]`が4件以上、`[SERVICE_CHECK] VM Service is alive`が1件以上であることを確認
3. **テスト3**: アプリ終了後、30秒待機。ログが完全に停止（0件）であることを確認

詳細は[検証ドキュメント](../LIFECYCLE_CONTRACT_V2_VERIFICATION.md)を参照してください。
