# アプリ終了経路の一覧

## 検索結果

### ✅ 終了処理なし（確認済み）
- `exit(0)`, `exitProcess`, `dart:io`の`exit`: **使用されていない**
- `SystemNavigator.pop`: **使用されていない**
- `window_manager` / `bitsdojo_window` / `appWindow.close` / `closeWindow`: **使用されていない**
- `Process.killPid` / `kill` / `terminate` / `taskkill`: **使用されていない**
- `Platform.isWindows`分岐での終了処理: **使用されていない**

### 🔴 終了経路として確認された箇所

#### 1. **Windows Runner: WM_DESTROY → PostQuitMessage(0)**
**ファイル**: `after_app/windows/runner/win32_window.cpp:182-189`

```cpp
case WM_DESTROY:
  window_handle_ = nullptr;
  Destroy();
  if (quit_on_close_) {  // ← main.cppでtrueに設定されている
    PostQuitMessage(0);  // ← これがアプリ終了のトリガー
  }
  return 0;
```

**設定箇所**: `after_app/windows/runner/main.cpp:75`
```cpp
window.SetQuitOnClose(true);  // ← これによりウィンドウ閉じで終了
```

**ログ追加**: ✅ `WM_DESTROY`と`PostQuitMessage`呼び出しをログに記録

#### 2. **Windows Runner: WM_CLOSE**
**ファイル**: `after_app/windows/runner/flutter_window.cpp`（MessageHandler経由）

**流れ**: `WM_CLOSE` → `WM_DESTROY` → `PostQuitMessage(0)`

**ログ追加**: ✅ `WM_CLOSE`をログに記録

#### 3. **FlutterWindow::OnDestroy()**
**ファイル**: `after_app/windows/runner/flutter_window.cpp:42-48`

**問題**: ウィンドウ破棄時に呼ばれるが、直接的な終了処理はない（Win32Window側で`PostQuitMessage`が呼ばれる）

**ログ追加**: ✅ `OnDestroy()`呼び出しをログに記録

## 実装した終了検知機能

### 1. **AppLifecycleObserver** (`after_app/lib/core/app_lifecycle_observer.dart`)
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

