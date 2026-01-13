# アプリ終了経路の分析レポート

## 検索結果サマリー

### ✅ 確認済み（終了処理なし）
1. **明示的な終了処理**: `exit()`, `exitProcess`, `dart:io`の`exit`は使用されていない
2. **SystemNavigator.pop**: 使用されていない
3. **window_manager / bitsdojo_window**: 使用されていない
4. **Process.killPid / kill / terminate**: 使用されていない
5. **Platform.isWindows分岐での終了処理**: 使用されていない

### 🔴 終了経路として確認された箇所

#### 1. **Windows Runner側: WM_DESTROY → PostQuitMessage(0)**（最優先）
**場所**: `after_app/windows/runner/win32_window.cpp:182-188`

```cpp
case WM_DESTROY:
  window_handle_ = nullptr;
  Destroy();
  if (quit_on_close_) {
    PostQuitMessage(0);  // ← これがアプリ終了のトリガー
  }
  return 0;
```

**問題**: `main.cpp`で`window.SetQuitOnClose(true)`が設定されているため、ウィンドウが閉じられると`PostQuitMessage(0)`が呼ばれ、アプリが終了する。

**ログ追加**: `WM_DESTROY`と`PostQuitMessage`呼び出しをログに記録するように修正済み。

#### 2. **Windows Runner側: WM_CLOSE**
**場所**: `after_app/windows/runner/win32_window.cpp`（Win32WindowのMessageHandler）

**問題**: ウィンドウが閉じられると`WM_CLOSE`が送信され、最終的に`WM_DESTROY`に至る。

**ログ追加**: `WM_CLOSE`をログに記録するように修正済み。

#### 3. **FlutterWindow::OnDestroy()**
**場所**: `after_app/windows/runner/flutter_window.cpp:42-48`

**問題**: ウィンドウ破棄時に呼ばれるが、直接的な終了処理はない。

**ログ追加**: `OnDestroy()`呼び出しをログに記録するように修正済み。

## 実装した終了検知機能

### 1. **AppLifecycleObserver** (`after_app/lib/core/app_lifecycle_observer.dart` - 新規)
- `WidgetsBindingObserver`を実装
- `didChangeAppLifecycleState`: ライフサイクル状態変更をログに記録
- `didHaveMemoryPressure`: メモリ圧迫をログに記録
- `Isolate.current.addOnExitListener`: Isolate終了を検知

### 2. **Windows Runner側のログ強化**
- `WM_CLOSE`, `WM_DESTROY`, `WM_QUIT`をログに記録
- `PostQuitMessage(0)`呼び出しをログに記録
- `FlutterWindow::OnDestroy()`呼び出しをログに記録

### 3. **main.dartでの初期化**
- `AppLifecycleObserver.initialize()`を呼び出し

## 終了イベントのログ出力例

### Dart側（AppLifecycleObserver）
```
[LifecycleObserver] App lifecycle changed: AppLifecycleState.paused
[LifecycleObserver] App is being paused/detached - this may lead to termination
[LifecycleObserver] Isolate exit listener triggered: isolate_exit
```

### Windows Runner側
```
[Windows Runner] === WINDOW MESSAGE ===
[Windows Runner] Message: WM_CLOSE (window close requested)
[Windows Runner] =====================
[Windows Runner] === OnDestroy() CALLED ===
[Windows Runner] FlutterWindow is being destroyed
[Windows Runner] ===========================
[Windows Runner] === WM_DESTROY HANDLED ===
[Windows Runner] quit_on_close_: true
[Windows Runner] PostQuitMessage(0) called - app will terminate
[Windows Runner] =========================
```

## タイマーによる自己終了の確認

### 確認済み
- `CrashLogger.startHeartbeat()`: タイマーはキャンセル可能で、自己終了しない
- `Timer.periodic`（Service diagnostics）: タイマーはキャンセル可能で、自己終了しない
- `runZonedGuarded`: 正常終了しない（エラー時のみ終了）

### 問題なし
- タイマーによる自己終了は発生しない

## 次のステップ

1. アプリを再起動して動作確認
2. 「Lost connection」発生時にログファイルを確認
3. `WM_CLOSE` / `WM_DESTROY` / `PostQuitMessage`のログを確認
4. `AppLifecycleObserver`のログを確認
5. ウィンドウが意図せず閉じられていないか確認

## 推奨される追加調査

### 1. ウィンドウが自動的に閉じられる原因
- システムの自動終了（メモリ不足など）
- 他のプロセスからの終了要求
- Windows Updateやセキュリティソフトによる終了

### 2. ログファイルの確認ポイント
- `WM_CLOSE`が出力されているか
- `PostQuitMessage(0)`が呼ばれているか
- `AppLifecycleObserver`のライフサイクル変更が記録されているか
- ハートビートが継続しているか（アプリが生きているか）

