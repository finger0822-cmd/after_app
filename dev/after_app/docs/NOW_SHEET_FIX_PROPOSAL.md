# NowSheet修正案（潜在的問題の対処）

## 発見された潜在的問題

### 問題1: `addPostFrameCallback`がキャンセルできない
**箇所**: 1049行目
- `_onSentResetTimer`内で`addPostFrameCallback`を登録しているが、これはキャンセルできない
- dispose後に`addPostFrameCallback`が実行される可能性がある

### 問題2: `setState`の安全性
**箇所**: 1078行目
- `_updateUiState`内で`mounted`チェック後に`setState`を呼んでいるが、その間にdisposeされる可能性がある
- try-catchで囲むべき

### 問題3: `_isSubmitting`のリセット安全性
**箇所**: 973行目
- `finally`内で`mounted`チェックはしているが、より安全にするためにtry-catchを追加すべき

---

## 修正案

### 修正1: `addPostFrameCallback`をキャンセル可能にする

```dart
// 修正前（1040-1052行目）
void _onSentResetTimer({required int sessionId}) {
  CrashLogger.logDebug('[NowSheet] Windows: _onSentResetTimer STARTED sessionId=$sessionId');
  
  if (!mounted) {
    CrashLogger.logInfo('[NowSheet] Windows: _onSentResetTimer called after dispose sessionId=$sessionId');
    return;
  }
  
  // 次のフレームで実行することで、Widgetの状態を確実に確認
  SchedulerBinding.instance.addPostFrameCallback((_) {
    _onSentResetTimerPostFrame(sessionId: sessionId);
  });
}
```

```dart
// 修正後
void _onSentResetTimer({required int sessionId}) {
  CrashLogger.logDebug('[NowSheet] Windows: _onSentResetTimer STARTED sessionId=$sessionId');
  
  if (!mounted) {
    CrashLogger.logInfo('[NowSheet] Windows: _onSentResetTimer called after dispose sessionId=$sessionId');
    return;
  }
  
  // 次のフレームで実行することで、Widgetの状態を確実に確認
  // mountedチェックをコールバック内でも行う（二重チェック）
  SchedulerBinding.instance.addPostFrameCallback((_) {
    // コールバック実行時にもmountedチェック（dispose後の実行を防ぐ）
    if (!mounted) {
      CrashLogger.logInfo('[NowSheet] Windows: _onSentResetTimer postFrameCallback called after dispose sessionId=$sessionId');
      return;
    }
    _onSentResetTimerPostFrame(sessionId: sessionId);
  });
}
```

### 修正2: `_updateUiState`にtry-catchを追加

```dart
// 修正前（1072-1082行目）
void _updateUiState(NowSheetUiState newState, {required int sessionId}) {
  if (!mounted) {
    CrashLogger.logInfo('[NowSheet] _updateUiState: not mounted, skipping state=$newState sessionId=$sessionId');
    return;
  }
  
  setState(() {
    _uiState = newState;
  });
  CrashLogger.logDebug('[NowSheet] _updateUiState: state=$newState sessionId=$sessionId');
}
```

```dart
// 修正後
void _updateUiState(NowSheetUiState newState, {required int sessionId}) {
  if (!mounted) {
    CrashLogger.logInfo('[NowSheet] _updateUiState: not mounted, skipping state=$newState sessionId=$sessionId');
    return;
  }
  
  try {
    setState(() {
      _uiState = newState;
    });
    CrashLogger.logDebug('[NowSheet] _updateUiState: state=$newState sessionId=$sessionId');
  } catch (e, stack) {
    // setState中にdisposeされた場合のエラーをキャッチ
    CrashLogger.logException(e, stack, context: 'NowSheet _updateUiState setState error state=$newState sessionId=$sessionId');
  }
}
```

### 修正3: `_isSubmitting`のリセットにtry-catchを追加

```dart
// 修正前（970-978行目）
} finally {
  // 送信完了：ロックを解除（mountedチェック必須）
  if (mounted) {
    _isSubmitting = false;
    CrashLogger.logDebug('[NowSheet] _handleSubmit: _isSubmitting reset to false sessionId=$submitSessionId');
  } else {
    CrashLogger.logInfo('[NowSheet] _handleSubmit: not mounted in finally, skipping _isSubmitting reset sessionId=$submitSessionId');
  }
}
```

```dart
// 修正後
} finally {
  // 送信完了：ロックを解除（mountedチェック必須）
  try {
    if (mounted) {
      _isSubmitting = false;
      CrashLogger.logDebug('[NowSheet] _handleSubmit: _isSubmitting reset to false sessionId=$submitSessionId');
    } else {
      CrashLogger.logInfo('[NowSheet] _handleSubmit: not mounted in finally, skipping _isSubmitting reset sessionId=$submitSessionId');
    }
  } catch (e, stack) {
    // mountedチェック中にdisposeされた場合のエラーをキャッチ
    CrashLogger.logException(e, stack, context: 'NowSheet _handleSubmit finally error sessionId=$submitSessionId');
    // エラーが発生してもロックは解除する（デッドロック防止）
    _isSubmitting = false;
  }
}
```

---

## 修正の優先度

1. **高**: 修正2（`_updateUiState`のtry-catch）- dispose後setState防止の最終防御
2. **中**: 修正1（`addPostFrameCallback`の二重チェック）- より安全な実装
3. **低**: 修正3（`_isSubmitting`のtry-catch）- 念のための防御

---

## 実装後の検証項目

1. dispose後setStateエラーが出ないことを確認
2. ログで`called after dispose`が適切に記録されることを確認
3. 二重送信防止が正常に機能することを確認
