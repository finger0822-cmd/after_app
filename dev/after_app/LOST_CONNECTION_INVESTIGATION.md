# Lost Connection to Device 調査レポート

## 調査結果サマリー

### ✅ 確認済み（問題なし）
1. **明示的なアプリ終了処理**: `exit()`, `SystemNavigator.pop`, `window.close` などは使用されていない
2. **Windows Runner**: 標準的な実装で、特別な終了処理はない
3. **Isar Inspector**: `openInspector()`は使用されていない（通常のIsar使用のみ）
4. **グローバル例外ハンドラ**: `FlutterError.onError`と`PlatformDispatcher.onError`は既に設定済み

### 🔴 疑わしい箇所（優先順位順）

#### 1. **`calendarControllerProvider.refresh()`の非同期処理完了待ち不足**（最優先）
**場所**: `after_app/lib/features/calendar/now_sheet.dart:936`
```dart
ref.read(calendarControllerProvider.notifier).refresh();
```
**問題**: `refresh()`は`Future<void>`を返すが、`await`していない。Isarのトランザクション完了前に次の処理に進む可能性がある。

**影響**: Windows Debug環境でVM Service接続が不安定になる可能性

#### 2. **`Future.delayed`内の`setState`実行タイミング**（高優先度）
**場所**: `after_app/lib/features/calendar/now_sheet.dart:954-963`
```dart
Future.delayed(const Duration(milliseconds: 1000), () {
  if (!mounted) return;
  setState(() { _showSentLocal = false; });
});
```
**問題**: `mounted`チェックはあるが、`setState`実行直前にWidgetがdisposeされる可能性がある。

**影響**: dispose後の`setState`で例外が発生し、VM Service接続が切れる可能性

#### 3. **`FocusScope.of(context).unfocus()`のWindows固有の問題**（中優先度）
**場所**: `after_app/lib/features/calendar/now_sheet.dart:877`
```dart
FocusScope.of(context).unfocus();
```
**問題**: Windows Desktopでフォーカス操作がVM Serviceに干渉する可能性がある。

**影響**: フォーカス操作がVM Service接続を不安定にする可能性

#### 4. **Isarトランザクションの完了待ち不足**（中優先度）
**場所**: `after_app/lib/features/now/now_controller.dart:88`
```dart
await _repo.create(message);
```
**問題**: `create()`は完了しているが、その後の`refresh()`が非同期で実行され、Isarの内部状態が不安定になる可能性がある。

**影響**: Isarの内部状態とVM Serviceの同期が崩れる可能性

## 追加ログパッチ

### 1. `now_sheet.dart`への追加ログ

```dart
// _handleSubmit内、Windows分岐のrefresh()呼び出し前後
debugPrint('[NowSheet] Windows: BEFORE refresh() call');
try {
  await ref.read(calendarControllerProvider.notifier).refresh();
  debugPrint('[NowSheet] Windows: refresh() COMPLETED');
} catch (e, stack) {
  debugPrint('[NowSheet] Windows: refresh() ERROR: $e');
  debugPrint('[NowSheet] Windows: refresh() STACK: $stack');
}

// Future.delayed内、setState前後
Future.delayed(const Duration(milliseconds: 1000), () {
  debugPrint('[NowSheet] Windows: Future.delayed callback STARTED');
  if (!mounted) {
    debugPrint('[NowSheet] Windows: not mounted before reset');
    return;
  }
  try {
    debugPrint('[NowSheet] Windows: BEFORE setState(_showSentLocal=false)');
    setState(() {
      _showSentLocal = false;
    });
    debugPrint('[NowSheet] Windows: AFTER setState(_showSentLocal=false)');
  } catch (e, stack) {
    debugPrint('[NowSheet] Windows: setState ERROR: $e');
    debugPrint('[NowSheet] Windows: setState STACK: $stack');
  }
  debugPrint('[NowSheet] Windows: reset completed, back to input screen');
});
```

### 2. `_clearComposerAfterSuccess()`への追加ログ

```dart
// FocusScope.of(context).unfocus()前後
if (mounted) {
  try {
    debugPrint('[NowSheet] Windows: BEFORE unfocus()');
    FocusScope.of(context).unfocus();
    debugPrint('[NowSheet] Windows: AFTER unfocus()');
  } catch (e, stack) {
    debugPrint('[NowSheet] Windows: unfocus() ERROR: $e');
    debugPrint('[NowSheet] Windows: unfocus() STACK: $stack');
  }
}
```

### 3. `main.dart`への追加ログ（既存ハンドラ強化）

```dart
FlutterError.onError = (FlutterErrorDetails details) {
  debugPrint('[main] === FlutterError ===');
  debugPrint('[main] Time: ${DateTime.now().toIso8601String()}');
  debugPrint('[main] Exception: ${details.exceptionAsString()}');
  debugPrint('[main] Stack: ${details.stack.toString()}');
  debugPrint('[main] Library: ${details.library}');
  debugPrint('[main] Context: ${details.context}');
  debugPrint('[main] ===================');
  FlutterError.presentError(details);
};

PlatformDispatcher.instance.onError = (error, stack) {
  debugPrint('[main] === PlatformDispatcher Error ===');
  debugPrint('[main] Time: ${DateTime.now().toIso8601String()}');
  debugPrint('[main] Error: $error');
  debugPrint('[main] Stack: $stack');
  debugPrint('[main] Error Type: ${error.runtimeType}');
  debugPrint('[main] ================================');
  return true; // エラーを処理したことを示す
};
```

## 根本対策の提案

### 対策A: `refresh()`を`await`する（推奨）

**変更箇所**: `after_app/lib/features/calendar/now_sheet.dart:936`

```dart
// 変更前
ref.read(calendarControllerProvider.notifier).refresh();

// 変更後
try {
  await ref.read(calendarControllerProvider.notifier).refresh();
  debugPrint('[NowSheet] Windows: refresh completed');
} catch (e, stack) {
  debugPrint('[NowSheet] Windows: refresh error: $e');
  debugPrint('[NowSheet] Windows: refresh stack: $stack');
}
```

**理由**: Isarのトランザクション完了を待つことで、VM Service接続の安定性が向上する可能性がある。

### 対策B: `Future.delayed`内の`setState`を`SchedulerBinding.instance.addPostFrameCallback`に変更

**変更箇所**: `after_app/lib/features/calendar/now_sheet.dart:954-963`

```dart
// 変更前
Future.delayed(const Duration(milliseconds: 1000), () {
  if (!mounted) return;
  setState(() { _showSentLocal = false; });
});

// 変更後
Future.delayed(const Duration(milliseconds: 1000), () {
  if (!mounted) {
    debugPrint('[NowSheet] Windows: not mounted before reset');
    return;
  }
  // 次のフレームで実行することで、Widgetの状態を確実に確認
  SchedulerBinding.instance.addPostFrameCallback((_) {
    if (!mounted) {
      debugPrint('[NowSheet] Windows: not mounted in postFrameCallback');
      return;
    }
    try {
      setState(() {
        _showSentLocal = false;
      });
    } catch (e, stack) {
      debugPrint('[NowSheet] Windows: setState error in postFrameCallback: $e');
      debugPrint('[NowSheet] Windows: setState stack: $stack');
    }
  });
});
```

**理由**: `addPostFrameCallback`を使うことで、Widgetの状態をより確実に確認できる。

### 対策C: `unfocus()`をtry-catchで囲む（既に実装済みだが、ログを追加）

**変更箇所**: `after_app/lib/features/calendar/now_sheet.dart:876-879`

```dart
// 変更前
if (mounted) {
  FocusScope.of(context).unfocus();
}

// 変更後
if (mounted) {
  try {
    FocusScope.of(context).unfocus();
    debugPrint('[NowSheet] _clearComposerAfterSuccess: focus unfocused');
  } catch (e, stack) {
    debugPrint('[NowSheet] _clearComposerAfterSuccess: unfocus error: $e');
    debugPrint('[NowSheet] _clearComposerAfterSuccess: unfocus stack: $stack');
  }
}
```

**理由**: Windows固有の問題を捕捉し、VM Service接続への影響を最小化する。

### 対策D: Debug限定の回避策（Releaseで再現しない場合）

**変更箇所**: `after_app/lib/features/calendar/now_sheet.dart:931`

```dart
if (Platform.isWindows) {
  // Debugモードでのみ追加の待機時間を入れる
  if (kDebugMode) {
    await Future.delayed(const Duration(milliseconds: 100));
  }
  // ... 既存の処理
}
```

**理由**: Debug環境でのVM Service接続の不安定性を回避する。

## 実装優先順位

1. **最優先**: 対策A（`refresh()`を`await`する）
2. **高優先度**: 追加ログパッチ（原因特定のため）
3. **中優先度**: 対策B（`Future.delayed`内の`setState`を`addPostFrameCallback`に変更）
4. **低優先度**: 対策C（`unfocus()`のtry-catch強化、既に実装済み）
5. **最後の手段**: 対策D（Debug限定の回避策）

## 次のステップ

1. 追加ログパッチを適用して再現させる
2. ログから原因箇所を特定
3. 対策Aを適用して効果を確認
4. 必要に応じて対策B、C、Dを適用

