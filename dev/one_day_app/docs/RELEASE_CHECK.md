# Releaseビルドでの注意点

## assertが削除されること

Releaseビルドでは、`assert()`で囲まれたコードは削除されます。

### 影響を受ける処理

以下の処理はReleaseビルドでは実行されません：

- `startHeartbeat()`: assert内で実装されているため、Releaseではタイマーが起動しません
- `startServiceDiagnostics()`: assert内で実装されているため、Releaseではタイマーが起動しません
- `setLogLevel()`: assert内で実装されているため、Releaseではログレベル設定が無効です

### 影響を受けない処理

以下の処理はReleaseビルドでも確実に実行されます：

- `stopAllTimers()`: assert外で実装されているため、Releaseでも確実に実行されます
- `stopHeartbeat()`: assert外で実装されているため、Releaseでも確実に実行されます
- `stopServiceDiagnostics()`: assert外で実装されているため、Releaseでも確実に実行されます

## 契約上の要点

### stopAllTimers()はassert外であるべき

ライフサイクル契約(v2)では、`stopAllTimers()`はassert外で実装されることが契約要件です。これにより、Releaseビルドでもタイマーが確実に停止します。

### 実装確認

`crash_logger.dart`の`stopAllTimers()`メソッドは、assert外で実装されています：

```dart
/// すべてのタイマーを停止（detached/dispose時に呼び出す）
static void stopAllTimers() {
  stopHeartbeat();
  stopServiceDiagnostics();
}
```

この実装により、Releaseビルドでも確実にタイマーが停止します。

## Release前チェックリスト

### 必須確認事項

- [ ] `stopAllTimers()`がassert外で実装されていることを確認
- [ ] `stopHeartbeat()`がassert外で実装されていることを確認
- [ ] `stopServiceDiagnostics()`がassert外で実装されていることを確認
- [ ] Releaseビルドでアプリを起動し、タイマーが起動しないことを確認
- [ ] Releaseビルドでアプリを終了し、ログが完全に停止することを確認

### 推奨確認事項

- [ ] Releaseビルドのログファイルを確認し、`[HEARTBEAT]`や`[SERVICE_CHECK]`が出力されないことを確認
- [ ] アプリ終了後のログ残響がないことを確認

## 検証方法

### Releaseビルドの作成

```bash
flutter build windows --release
```

### 動作確認

1. Releaseビルドでアプリを起動
2. 45秒待機
3. ログファイルを確認し、`[HEARTBEAT]`や`[SERVICE_CHECK]`が出力されないことを確認
4. アプリを終了
5. 終了後30秒待機
6. ログファイルを確認し、ログが完全に停止していることを確認
