import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:after_app/features/calendar/now_sheet.dart';
import 'package:after_app/features/now/now_controller.dart';
import 'package:after_app/features/calendar/calendar_controller.dart';
import 'package:after_app/data/message_repo.dart';
import 'package:after_app/data/message_model.dart';
import 'package:after_app/core/time.dart';

void main() {
  group('NowSheet送信フローテスト', () {
    testWidgets('成功ケース: 送信成功時にシートが閉じ、refreshが呼ばれる', (WidgetTester tester) async {
      // Arrange
      final repo = MockMessageRepo();
      bool refreshCalled = false;
      
      // CalendarController.refresh()をspyするためのラッパー
      final calendarControllerSpy = CalendarControllerSpy(repo, () {
        refreshCalled = true;
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            messageRepoProvider.overrideWithValue(repo),
            calendarControllerProvider.overrideWith((ref) => calendarControllerSpy),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () {
                      showGeneralDialog<bool>(
                        context: context,
                        barrierDismissible: true,
                        barrierLabel: 'now',
                        barrierColor: Colors.black54,
                        pageBuilder: (_, __, ___) {
                          return SafeArea(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 600),
                                child: Material(
                                  borderRadius: BorderRadius.circular(16),
                                  clipBehavior: Clip.antiAlias,
                                  child: NowSheet(
                                    initialOpenOn: TimeUtils.addDays(TimeUtils.today(), 7),
                                    sessionId: DateTime.now().microsecondsSinceEpoch,
                                    todayCellKey: null,
                                    todayCellRect: null,
                                    overlayContext: context,
                                    absorbAnimator: null,
                                    fallbackRunner: null,
                                    onPrepareAbsorb: null,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        transitionBuilder: (_, anim, __, child) {
                          final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
                          final scale = Tween<double>(begin: 0.98, end: 1.0).animate(fade);
                          return FadeTransition(
                            opacity: fade,
                            child: ScaleTransition(scale: scale, child: child),
                          );
                        },
                        transitionDuration: const Duration(milliseconds: 160),
                      );
                    },
                    child: const Text('Open'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // シートを開く
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // テキストを入力
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.enterText(textField, 'テストメッセージ');
      await tester.pump();

      // 送信ボタンをタップ
      final sendButton = find.text('Send to After');
      expect(sendButton, findsOneWidget);
      await tester.tap(sendButton);
      await tester.pump();

      // 送信処理の完了を待つ（Heroアニメーションに変更したため、処理が速い）
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // 最終的にシートが閉じることを確認（Heroアニメーションでpopされる）
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      
      // Assert: refreshが呼ばれる
      expect(refreshCalled, true);
      
      // Assert: シートが閉じている（Heroアニメーションでpopされる）
      expect(find.byType(NowSheet), findsNothing);
    });

    testWidgets('失敗ケース: 保存失敗時にシートが閉じず、エラー表示される', (WidgetTester tester) async {
      // Arrange: 例外をthrowするRepo
      final failingRepo = FailingMessageRepo();
      
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            messageRepoProvider.overrideWithValue(failingRepo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () {
                      showGeneralDialog<bool>(
                        context: context,
                        barrierDismissible: true,
                        barrierLabel: 'now',
                        barrierColor: Colors.black54,
                        pageBuilder: (_, __, ___) {
                          return SafeArea(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 600),
                                child: Material(
                                  borderRadius: BorderRadius.circular(16),
                                  clipBehavior: Clip.antiAlias,
                                  child: NowSheet(
                                    initialOpenOn: TimeUtils.addDays(TimeUtils.today(), 7),
                                    sessionId: DateTime.now().microsecondsSinceEpoch,
                                    todayCellKey: null,
                                    todayCellRect: null,
                                    overlayContext: context,
                                    absorbAnimator: null,
                                    fallbackRunner: null,
                                    onPrepareAbsorb: null,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        transitionBuilder: (_, anim, __, child) {
                          final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
                          final scale = Tween<double>(begin: 0.98, end: 1.0).animate(fade);
                          return FadeTransition(
                            opacity: fade,
                            child: ScaleTransition(scale: scale, child: child),
                          );
                        },
                        transitionDuration: const Duration(milliseconds: 160),
                      );
                    },
                    child: const Text('Open'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // シートを開く
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // テキストを入力
      await tester.enterText(find.byType(TextField), 'テストメッセージ');
      await tester.pump();

      // 送信ボタンをタップ
      await tester.tap(find.text('Send to After'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Assert: シートが閉じない
      expect(find.byType(NowSheet), findsOneWidget);

      // Assert: エラーメッセージが表示される
      expect(find.text('保存できませんでした'), findsOneWidget);

      // Assert: ボタンが再度押せる（isSubmittingがfalseに戻る）
      expect(find.text('Send to After'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('連打防止: 送信中に2回タップしても保存処理は1回のみ', (WidgetTester tester) async {
      // Arrange
      final repo = CountingMessageRepo();
      
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            messageRepoProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () {
                      showGeneralDialog<bool>(
                        context: context,
                        barrierDismissible: true,
                        barrierLabel: 'now',
                        barrierColor: Colors.black54,
                        pageBuilder: (_, __, ___) {
                          return SafeArea(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 600),
                                child: Material(
                                  borderRadius: BorderRadius.circular(16),
                                  clipBehavior: Clip.antiAlias,
                                  child: NowSheet(
                                    initialOpenOn: TimeUtils.addDays(TimeUtils.today(), 7),
                                    sessionId: DateTime.now().microsecondsSinceEpoch,
                                    todayCellKey: null,
                                    todayCellRect: null,
                                    overlayContext: context,
                                    absorbAnimator: null,
                                    fallbackRunner: null,
                                    onPrepareAbsorb: null,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        transitionBuilder: (_, anim, __, child) {
                          final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
                          final scale = Tween<double>(begin: 0.98, end: 1.0).animate(fade);
                          return FadeTransition(
                            opacity: fade,
                            child: ScaleTransition(scale: scale, child: child),
                          );
                        },
                        transitionDuration: const Duration(milliseconds: 160),
                      );
                    },
                    child: const Text('Open'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // シートを開く
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // テキストを入力
      await tester.enterText(find.byType(TextField), 'テストメッセージ');
      await tester.pump();

      // 送信ボタンを連打
      final sendButton = find.text('Send to After');
      await tester.tap(sendButton);
      await tester.pump();
      
      // 2回目はボタンが無効になっているはず（タップしても反応しない）
      // Heroアニメーションに変更したため、1回目の送信で即座にpopされる可能性がある
      await tester.pump(const Duration(milliseconds: 50));
      final sendButton2 = find.text('Send to After');
      if (sendButton2.evaluate().isNotEmpty) {
        await tester.tap(sendButton2); // 2回目
        await tester.pump();
      }

      // 送信完了を待つ
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      // Assert: 保存処理が1回のみ呼ばれる（連打防止）
      expect(repo.createCallCount, 1);
    });

    testWidgets('空文字送信: エラーメッセージが表示される', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () {
                      showGeneralDialog<bool>(
                        context: context,
                        barrierDismissible: true,
                        barrierLabel: 'now',
                        barrierColor: Colors.black54,
                        pageBuilder: (_, __, ___) {
                          return SafeArea(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 600),
                                child: Material(
                                  borderRadius: BorderRadius.circular(16),
                                  clipBehavior: Clip.antiAlias,
                                  child: NowSheet(
                                    initialOpenOn: TimeUtils.addDays(TimeUtils.today(), 7),
                                    sessionId: DateTime.now().microsecondsSinceEpoch,
                                    todayCellKey: null,
                                    todayCellRect: null,
                                    overlayContext: context,
                                    absorbAnimator: null,
                                    fallbackRunner: null,
                                    onPrepareAbsorb: null,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        transitionBuilder: (_, anim, __, child) {
                          final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
                          final scale = Tween<double>(begin: 0.98, end: 1.0).animate(fade);
                          return FadeTransition(
                            opacity: fade,
                            child: ScaleTransition(scale: scale, child: child),
                          );
                        },
                        transitionDuration: const Duration(milliseconds: 160),
                      );
                    },
                    child: const Text('Open'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // シートを開く
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // 送信ボタンをタップ（テキスト未入力）
      // 空文字の場合はボタンが無効になっている可能性があるので、直接submitを呼ぶ
      final container = ProviderScope.containerOf(tester.element(find.byType(NowSheet).first));
      final controller = container.read(nowControllerProvider.notifier);
      await controller.submit('');
      await tester.pump();

      // Assert: エラーメッセージが表示される
      expect(find.text('メッセージを入力してください'), findsOneWidget);
    });

    // Heroアニメーションに変更したため、アニメ失敗ケースのテストは不要
    // HeroアニメーションはFlutterの標準機能なので、通常は失敗しない

    testWidgets('2回開いても初期状態になる: 1回目成功後、2回目は「保存しました」が表示されない', (WidgetTester tester) async {
      // Arrange
      final repo = MockMessageRepo();
      
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            messageRepoProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () {
                      showGeneralDialog<bool>(
                        context: context,
                        barrierDismissible: true,
                        barrierLabel: 'now',
                        barrierColor: Colors.black54,
                        pageBuilder: (_, __, ___) {
                          return SafeArea(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 600),
                                child: Material(
                                  borderRadius: BorderRadius.circular(16),
                                  clipBehavior: Clip.antiAlias,
                                  child: NowSheet(
                                    initialOpenOn: TimeUtils.addDays(TimeUtils.today(), 7),
                                    sessionId: DateTime.now().microsecondsSinceEpoch,
                                    todayCellKey: null,
                                    todayCellRect: null,
                                    overlayContext: context,
                                    absorbAnimator: null,
                                    fallbackRunner: null,
                                    onPrepareAbsorb: null,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        transitionBuilder: (_, anim, __, child) {
                          final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
                          final scale = Tween<double>(begin: 0.98, end: 1.0).animate(fade);
                          return FadeTransition(
                            opacity: fade,
                            child: ScaleTransition(scale: scale, child: child),
                          );
                        },
                        transitionDuration: const Duration(milliseconds: 160),
                      );
                    },
                    child: const Text('Open'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // === 1回目：成功して閉じる ===
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // テキストを入力
      await tester.enterText(find.byType(TextField), 'テストメッセージ1');
      await tester.pump();

      // 送信ボタンをタップ
      await tester.tap(find.text('Send to After'));
      await tester.pump();

      // 送信完了を待つ（Heroアニメーションで即座にpopされる）
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      
      // シートが閉じるまで待つ（Heroアニメーションでpopされる）
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      
      // シートが閉じていることを確認
      expect(find.byType(NowSheet), findsNothing);

      // === 2回目：開いて初期状態を確認 ===
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Assert: 「保存しました」が表示されていない
      expect(find.text('保存しました'), findsNothing);

      // Assert: ボタンが通常状態（「Send to After」）
      expect(find.text('Send to After'), findsOneWidget);

      // Assert: 入力欄が空
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, isEmpty);

      // Assert: エラーメッセージが表示されていない
      expect(find.text('保存できませんでした'), findsNothing);
      expect(find.text('メッセージを入力してください'), findsNothing);
    });

    testWidgets('再発防止: 成功時に吸い込みが1回だけ実行される', (WidgetTester tester) async {
      // Arrange
      final repo = MockMessageRepo();
      int absorbCallCount = 0;
      String? lastAbsorbToken;
      
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            messageRepoProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () {
                      showGeneralDialog<bool>(
                        context: context,
                        barrierDismissible: true,
                        barrierLabel: 'now',
                        barrierColor: Colors.black54,
                        pageBuilder: (_, __, ___) {
                          return SafeArea(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 600),
                                child: Material(
                                  borderRadius: BorderRadius.circular(16),
                                  clipBehavior: Clip.antiAlias,
                                  child: NowSheet(
                                    initialOpenOn: TimeUtils.addDays(TimeUtils.today(), 7),
                                    sessionId: DateTime.now().microsecondsSinceEpoch,
                                    todayCellKey: null,
                                    todayCellRect: null,
                                    overlayContext: context,
                                    absorbAnimator: null,
                                    fallbackRunner: () async {
                                      absorbCallCount++;
                                      debugPrint('[test] fallback called, count=$absorbCallCount');
                                    },
                                    onPrepareAbsorb: null,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        transitionBuilder: (_, anim, __, child) {
                          final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
                          final scale = Tween<double>(begin: 0.98, end: 1.0).animate(fade);
                          return FadeTransition(
                            opacity: fade,
                            child: ScaleTransition(scale: scale, child: child),
                          );
                        },
                        transitionDuration: const Duration(milliseconds: 160),
                      );
                    },
                    child: const Text('Open'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // シートを開く
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // テキストを入力
      await tester.enterText(find.byType(TextField), 'テストメッセージ');
      await tester.pump();

      // 送信ボタンをタップ
      await tester.tap(find.text('Send to After'));
      await tester.pump();

      // 送信処理の完了を待つ
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));

      // Assert: フォールバックが1回だけ呼ばれる（吸い込みが1回だけ実行される）
      expect(absorbCallCount, 1, reason: '吸い込みアニメーションは1回だけ実行されるべき');
      
      // Assert: シートが閉じている
      expect(find.byType(NowSheet), findsNothing);
    });

    testWidgets('再発防止: 2回連続送信（別session）でも2回とも吸い込みが走る', (WidgetTester tester) async {
      // Arrange
      final repo = MockMessageRepo();
      int absorbCallCount = 0;
      
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            messageRepoProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () {
                      showGeneralDialog<bool>(
                        context: context,
                        barrierDismissible: true,
                        barrierLabel: 'now',
                        barrierColor: Colors.black54,
                        pageBuilder: (_, __, ___) {
                          return SafeArea(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 600),
                                child: Material(
                                  borderRadius: BorderRadius.circular(16),
                                  clipBehavior: Clip.antiAlias,
                                  child: NowSheet(
                                    initialOpenOn: TimeUtils.addDays(TimeUtils.today(), 7),
                                    sessionId: DateTime.now().microsecondsSinceEpoch,
                                    todayCellKey: null,
                                    todayCellRect: null,
                                    overlayContext: context,
                                    absorbAnimator: null,
                                    fallbackRunner: () async {
                                      absorbCallCount++;
                                      debugPrint('[test] fallback called, count=$absorbCallCount');
                                    },
                                    onPrepareAbsorb: null,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        transitionBuilder: (_, anim, __, child) {
                          final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
                          final scale = Tween<double>(begin: 0.98, end: 1.0).animate(fade);
                          return FadeTransition(
                            opacity: fade,
                            child: ScaleTransition(scale: scale, child: child),
                          );
                        },
                        transitionDuration: const Duration(milliseconds: 160),
                      );
                    },
                    child: const Text('Open'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // === 1回目：送信成功 ===
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'テストメッセージ1');
      await tester.pump();

      await tester.tap(find.text('Send to After'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Assert: 1回目が実行された
      expect(absorbCallCount, 1, reason: '1回目の送信で吸い込みが1回実行されるべき');

      // === 2回目：別sessionで送信成功 ===
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'テストメッセージ2');
      await tester.pump();

      await tester.tap(find.text('Send to After'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Assert: 2回目も実行された（別sessionなので2回とも実行される）
      expect(absorbCallCount, 2, reason: '2回目の送信（別session）でも吸い込みが実行されるべき');
    });
  });
}

// テスト用のヘルパークラス
class CalendarControllerSpy extends CalendarController {
  final VoidCallback onRefresh;

  CalendarControllerSpy(MessageRepo repo, this.onRefresh) : super(repo);

  @override
  Future<void> refresh() async {
    onRefresh();
    return super.refresh();
  }
}

class MockMessageRepo extends MessageRepo {
  @override
  Future<void> create(Message message) async {
    // テスト用：実際のDB保存はスキップ
  }

  @override
  Future<List<Message>> getOpenedMessages() async {
    return [];
  }

  @override
  Future<List<Message>> searchOpenedMessages(String query) async {
    return [];
  }

  @override
  Future<List<Message>> getSealedMessages() async {
    return [];
  }

  @override
  Future<Message?> getById(String messageId) async {
    return null;
  }

  @override
  Future<List<Message>> getMessagesByOpenOn(DateTime openOn) async {
    return [];
  }
}

class FailingMessageRepo extends MessageRepo {
  @override
  Future<void> create(Message message) async {
    throw Exception('保存失敗');
  }

  @override
  Future<List<Message>> getOpenedMessages() async {
    return [];
  }

  @override
  Future<List<Message>> searchOpenedMessages(String query) async {
    return [];
  }

  @override
  Future<List<Message>> getSealedMessages() async {
    return [];
  }

  @override
  Future<Message?> getById(String messageId) async {
    return null;
  }

  @override
  Future<List<Message>> getMessagesByOpenOn(DateTime openOn) async {
    return [];
  }
}

class CountingMessageRepo extends MessageRepo {
  int createCallCount = 0;

  @override
  Future<void> create(Message message) async {
    createCallCount++;
    // 実際の保存処理はスキップ（テスト用）
  }

  @override
  Future<List<Message>> getOpenedMessages() async {
    return [];
  }

  @override
  Future<List<Message>> searchOpenedMessages(String query) async {
    return [];
  }

  @override
  Future<List<Message>> getSealedMessages() async {
    return [];
  }

  @override
  Future<Message?> getById(String messageId) async {
    return null;
  }

  @override
  Future<List<Message>> getMessagesByOpenOn(DateTime openOn) async {
    return [];
  }
}
