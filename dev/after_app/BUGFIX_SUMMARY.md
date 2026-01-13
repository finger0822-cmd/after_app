# 不具合修正サマリー

## 修正した不具合

### A. 「まだ届いていない」記録の下部一覧が更新されない問題

**原因**: A2（下部一覧のクエリ/フィルタがopenOn基準になっていない）
- `CalendarController.loadMessagesForDay()`は`getOpenedMessages()`のみを取得していた
- `getOpenedMessages()`は`openedAtIsNotNull()`でフィルタしているため、まだ届いていないメッセージ（`openedAt == null`）は取得されない
- 下部一覧は`openedMessages`のみを表示していたため、まだ届いていないメッセージは表示されない

**修正内容**:
1. `MessageRepo`に`getMessagesByOpenOn(DateTime openOn)`メソッドを追加
   - 開封済み/未開封問わず、指定日の`openOn`に一致するメッセージを取得
2. `CalendarController.loadMessagesForDay()`を修正
   - `getOpenedMessages()`の代わりに`getMessagesByOpenOn()`を使用
3. 下部一覧の表示を修正
   - `openedAt == null`の場合は「まだ届いていない」と表示
   - 本文は「（本文は届くまで表示されません）」と表示

### B. 送信成功時の「今日セルへ吸い込み」アニメが発生しない問題

**原因**: B2（Overlay取得の問題）とB4（失敗して握りつぶされている）
- `Overlay.maybeOf(context)`がnullの場合に`return`していた
- `targetRect`や`originBox`が取得できない場合に`return`していた
- フォールバックがなく、何も起きない状態になっていた

**修正内容**:
1. `Overlay.of(context, rootOverlay: true)`を使用
   - `rootOverlay: true`で確実にOverlayを取得
2. フォールバックアニメーションを追加
   - `_playFallbackAnimation()`メソッドを追加
   - 座標取得ができない場合は、フェード+スケールアニメーションで閉じる
3. エラーハンドリングを強化
   - `try/catch`でエラーを捕捉し、フォールバックを実行
   - アニメーション失敗時も必ず`Navigator.pop(true)`で閉じる

## 変更ファイル

1. **lib/data/message_repo.dart**
   - `getMessagesByOpenOn(DateTime openOn)`メソッドを追加

2. **lib/features/calendar/calendar_controller.dart**
   - `loadMessagesForDay()`を修正（`getMessagesByOpenOn()`を使用）

3. **lib/features/calendar/calendar_page.dart**
   - 下部一覧の表示を修正（まだ届いていないメッセージも表示）

4. **lib/features/calendar/now_sheet.dart**
   - `_playAbsorbToTodayCell()`を修正（`rootOverlay: true`を使用）
   - `_playFallbackAnimation()`メソッドを追加

## 禁止語彙チェック

以下の禁止語彙がコード/文言/変数名/コメントに含まれていないことを確認：
- 未来から / 未来の自分 / 鍵 / 封印 / ロック / 解禁 / 🔒

**結果**: ✅ 禁止語彙は検出されませんでした（「未来日」というコメントは残っていますが、これは「未来の日付」という意味で、禁止語彙とは異なります）

## テスト

```bash
cd after_app
flutter test
```

すべてのテストが通ることを確認しました。





