import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/time.dart';
import '../../core/crash_logger.dart';
import '../now/now_controller.dart';
import 'calendar_controller.dart';

/// NowSheetの送信結果
enum SubmitResult { success, failed }

/// NowSheetのUI状態（状態遷移を単純化）
enum NowSheetUiState {
  input, // 入力中
  submitting, // 送信中
  sent, // 送信成功（Windows用）
}

class NowSheet extends ConsumerStatefulWidget {
  final DateTime initialOpenOn;
  final int sessionId; // 毎回開くたびに新しいIDを生成（状態リセット用）
  final GlobalKey? todayCellKey;
  final Rect? todayCellRect; // ダイアログを開く前に取得した今日セルの座標
  final GlobalKey? targetKey; // 吸い込み先アンカー用のGlobalKey（HomePageから渡される）
  final BuildContext? overlayContext; // CalendarPage側のcontext（Overlay取得用）
  final Future<void> Function()? absorbAnimator; // テスト用：吸い込みアニメーションを注入可能にする
  final Future<void> Function()? fallbackRunner; // テスト用：フォールバックアニメーションをspy可能にする
  final void Function(String heroTag, String previewText)?
  onPrepareAbsorb; // Hero受け皿を準備するコールバック

  const NowSheet({
    super.key,
    required this.initialOpenOn,
    required this.sessionId,
    this.todayCellKey,
    this.todayCellRect,
    this.targetKey,
    this.overlayContext,
    this.absorbAnimator,
    this.fallbackRunner,
    this.onPrepareAbsorb,
  });

  @override
  ConsumerState<NowSheet> createState() => _NowSheetState();
}

class _NowSheetState extends ConsumerState<NowSheet>
    with TickerProviderStateMixin {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _composerKey = GlobalKey();
  // _previewKeyは削除（動的キーに変更してTextFieldの再生成を確実にする）
  String? _previewText; // プレビュー用のテキスト
  AnimationController? _absorbAnimationController; // 吸い込みアニメーション用
  OverlayEntry? _currentOverlayEntry; // 現在のOverlayEntryを保持（重複防止用）
  String? _absorbingToken; // 吸い込み実行中のtoken（同一成功イベントでの二重起動防止用）
  bool _hideOriginalMessage = false; // 元UIを非表示にするフラグ（吸い込み開始時にtrue）
  bool _isAbsorbingLocal = false; // 吸い込み中のローカルフラグ（入力UI/previewを完全に非表示）
  int? _lastResetSessionId; // resetUI呼び出しごとのセッションID（ログ用）
  int? _lastResetWidgetSessionId; // 最後にresetUIを実行したwidget.sessionId（多重実行防止用）
  bool _didInit = false; // initStateで1回だけ実行するためのガード
  int _textFieldKey = 0; // TextFieldの再生成用キー（送信成功後にインクリメント）
  bool _isSubmitting = false; // 二重送信防止用フラグ
  Timer? _sentResetTimer; // Windows用：送信成功後のリセットタイマー（disposeでキャンセル可能）
  NowSheetUiState _uiState = NowSheetUiState.input; // UI状態（状態遷移を単純化）

  /// 安全なsetState（mountedチェック付き、例外は握りつぶさない）
  void safeSetState(VoidCallback fn) {
    if (!mounted) {
      return;
    }
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    // ビルド完了後にリセット（provider変更を避けるため）
    // initStateで1回だけ実行するようにboolガードを追加
    if (!_didInit) {
      _didInit = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _lastResetWidgetSessionId != widget.sessionId) {
          debugPrint('[NowSheet] initState: calling resetUI (first time only)');
          _resetUI();
        }
      });
    }
  }

  @override
  void didUpdateWidget(NowSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // sessionIdが変わったら状態をリセット（ビルド完了後に実行）
    // 多重実行を防ぐため、最後に実行したsessionIdと比較
    if (oldWidget.sessionId != widget.sessionId &&
        _lastResetWidgetSessionId != widget.sessionId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _lastResetWidgetSessionId != widget.sessionId) {
          _resetUI();
        }
      });
    }
  }

  @override
  void dispose() {
    // タイマーをキャンセル（dispose後setState防止）
    _sentResetTimer?.cancel();
    _sentResetTimer = null;
    CrashLogger.logDebug('[NowSheet] dispose: _sentResetTimer cancelled');

    // OverlayEntryが残っている場合は削除
    _currentOverlayEntry?.remove();
    _currentOverlayEntry = null;
    _absorbAnimationController?.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// UI状態を完全にリセット（開くたびに呼ばれる）
  void _resetUI() {
    // 多重実行を防ぐため、既に同じwidget.sessionIdで実行済みの場合はスキップ
    if (_lastResetWidgetSessionId == widget.sessionId) {
      debugPrint(
        '[NowSheet] resetUI: skipped (already reset for sessionId=${widget.sessionId})',
      );
      return;
    }

    // resetUI呼び出しごとに新しいsessionIdを生成（ログ用）
    _lastResetSessionId = DateTime.now().microsecondsSinceEpoch;
    _lastResetWidgetSessionId = widget.sessionId; // 実行済みsessionIdを記録
    debugPrint(
      '[NowSheet] resetUI: START sessionId=$_lastResetSessionId (widget.sessionId=${widget.sessionId})',
    );
    debugPrint(
      '[NowSheet] resetUI: process alive check - ${DateTime.now().toIso8601String()}',
    );

    try {
      // 既存のOverlayEntryを削除
      if (_currentOverlayEntry != null) {
        try {
          _currentOverlayEntry!.remove();
        } catch (e) {
          debugPrint('[NowSheet] error removing overlay entry in resetUI: $e');
        }
        _currentOverlayEntry = null;
      }

      // アニメーションフラグをリセット
      _absorbingToken = null;
      _hideOriginalMessage = false;
      _isAbsorbingLocal = false;
      _uiState = NowSheetUiState.input;

      // テキスト入力を空にする
      _textController.clear();

      // プレビューをリセット
      _previewText = null;

      // TextFieldを再生成するためにkeyをリセット
      _textFieldKey = 0;

      // NowControllerの状態をリセット
      ref.read(nowControllerProvider.notifier).resetStatus();

      // 日付を初期値に戻す（今日+7日）
      final today = TimeUtils.today();
      final defaultOpenOn = TimeUtils.addDays(today, 7);
      final initialDate = widget.initialOpenOn.isBefore(today)
          ? defaultOpenOn
          : widget.initialOpenOn;
      ref
          .read(nowControllerProvider.notifier)
          .updateDate(TimeUtils.toDateOnly(initialDate));

      // フォーカスを設定
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });

      debugPrint(
        '[NowSheet] resetUI: COMPLETED sessionId=$_lastResetSessionId',
      );
      debugPrint(
        '[NowSheet] resetUI: process still alive - ${DateTime.now().toIso8601String()}',
      );
    } catch (e, stack) {
      debugPrint('[NowSheet] resetUI: ERROR - $e');
      debugPrint('[NowSheet] resetUI: ERROR stack - $stack');
      rethrow;
    }
  }

  /// 座標を取得する
  Rect? _globalRectOf(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    return topLeft & box.size;
  }

  /// targetRect取得リトライヘルパー（最大5回、mountedチェックあり）
  Future<Rect?> _getTargetRectWithRetry({int maxRetries = 5}) async {
    // 優先順位: targetKey > todayCellRect > todayCellKey
    if (widget.targetKey != null) {
      for (int i = 0; i < maxRetries; i++) {
        if (!mounted) return null;
        await SchedulerBinding.instance.endOfFrame;
        await Future.delayed(const Duration(milliseconds: 50));
        final rect = _globalRectOf(widget.targetKey!);
        if (rect != null && rect.width > 0 && rect.height > 0) {
          debugPrint(
            '[absorb] targetRect obtained from targetKey (attempt ${i + 1}): $rect',
          );
          return rect;
        }
      }
    }

    // 既に取得済みのRectがあれば使用
    if (widget.todayCellRect != null &&
        widget.todayCellRect!.width > 0 &&
        widget.todayCellRect!.height > 0) {
      debugPrint(
        '[absorb] targetRect from todayCellRect: ${widget.todayCellRect}',
      );
      return widget.todayCellRect;
    }

    // todayCellKeyから取得を試みる
    if (widget.todayCellKey != null) {
      for (int i = 0; i < maxRetries; i++) {
        if (!mounted) return null;
        await SchedulerBinding.instance.endOfFrame;
        await Future.delayed(const Duration(milliseconds: 50));
        final rect = _globalRectOf(widget.todayCellKey!);
        if (rect != null && rect.width > 0 && rect.height > 0) {
          debugPrint(
            '[absorb] targetRect obtained from todayCellKey (attempt ${i + 1}): $rect',
          );
          return rect;
        }
      }
    }

    return null;
  }

  /// OverlayEntryを使った吸い込みアニメーション
  /// 戻り値: 成功した場合はtrue、失敗した場合はfalse
  Future<bool> _playAbsorbAnimation({
    required String previewText,
    required Rect originRect,
    required String token,
  }) async {
    // tokenは_runAbsorbAndCloseで既に設定済み（ここではチェック不要）
    debugPrint('[absorb] start, token=$token');

    // 既存のOverlayEntryを確実に削除
    if (_currentOverlayEntry != null) {
      try {
        _currentOverlayEntry!.remove();
        debugPrint('[absorb] removed existing overlay entry');
      } catch (e) {
        debugPrint('[absorb] error removing existing entry: $e');
      }
      _currentOverlayEntry = null;
    }

    // Overlayを取得
    OverlayState? overlay;
    debugPrint('[absorb] getting overlay, mounted=$mounted');
    if (!mounted) {
      debugPrint('[absorb] not mounted, cannot get overlay');
      return false;
    }
    try {
      final overlayCtx = widget.overlayContext ?? context;
      debugPrint('[absorb] calling Overlay.of');
      overlay = Overlay.of(overlayCtx, rootOverlay: true);
      debugPrint('[absorb] Overlay.of succeeded, overlay=$overlay');
    } catch (e, stack) {
      debugPrint('[absorb] overlay error: $e');
      debugPrint('[absorb] overlay error stack: $stack');
    }

    if (overlay == null) {
      debugPrint('[absorb] fallback: overlay is null');
      // フォールバックは呼び出し元で処理（ここではfalseを返す）
      return false;
    }

    // Overlayのサイズを取得
    final screenSize = MediaQuery.of(context).size;
    debugPrint('[absorb] overlaySize: $screenSize');

    // targetRect取得（リトライヘルパーを使用）
    final targetRect = await _getTargetRectWithRetry(maxRetries: 5);

    debugPrint('[absorb] originRect: $originRect');

    Rect resolvedTargetRect =
        targetRect ??
        Rect.fromCenter(
          center: Offset(screenSize.width / 2, screenSize.height / 2),
          width: 1,
          height: 1,
        );
    if (resolvedTargetRect.width == 0 || resolvedTargetRect.height == 0) {
      debugPrint('[absorb] fallback: targetRect invalid, using screen center');
      resolvedTargetRect = Rect.fromCenter(
        center: Offset(screenSize.width / 2, screenSize.height / 2),
        width: 1,
        height: 1,
      );
    }

    debugPrint('[absorb] targetRect: $resolvedTargetRect');

    // rootOverlay: trueを使っている場合、global座標をそのまま使用
    // OverlayEntryのPositionedは、OverlayのStack内での相対座標を使用する
    // originRectとtargetRectはglobal座標なので、そのまま使用
    // ただし、targetRectの中心ではなく、targetRectの左上隅から中心へのオフセットを計算
    final originCenter = originRect.center;
    final emitCenter = Offset(
      originCenter.dx.clamp(0.0, screenSize.width),
      originCenter.dy.clamp(0.0, screenSize.height),
    );
    final targetCenter = resolvedTargetRect.center;

    debugPrint('[absorb] originRect: $originRect (global)');
    debugPrint('[absorb] targetRect: $resolvedTargetRect (global)');
    debugPrint('[absorb] originCenter: $originCenter (global)');
    debugPrint('[absorb] targetCenter: $targetCenter (global)');
    debugPrint(
      '[absorb] originWidth: ${originRect.width}, originHeight: ${originRect.height}',
    );
    debugPrint(
      '[absorb] targetWidth: ${resolvedTargetRect.width}, targetHeight: ${resolvedTargetRect.height}',
    );
    debugPrint(
      '[absorb] startLeft: ${originRect.left}, startTop: ${originRect.top}',
    );
    debugPrint(
      '[absorb] endLeft: ${resolvedTargetRect.left}, endTop: ${resolvedTargetRect.top}',
    );

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    final curve = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOutCubic,
    );
    // 中心座標ではなく、左上隅の座標でアニメーション
    final originTopLeft = Offset(originRect.left, originRect.top);
    final targetTopLeft = Offset(
      resolvedTargetRect.left,
      resolvedTargetRect.top,
    );
    final pos = AlwaysStoppedAnimation<Offset>(originTopLeft);
    final fade = Tween<double>(begin: 1.0, end: 0.0).animate(curve);

    final cleanupCompleter = Completer<void>();
    var cleanupScheduled = false;

    late OverlayEntry entry;
    entry = OverlayEntry(
      opaque: false,
      builder: (_) {
        // Overlay内はStack + Positionedで配置し、clipBehavior: Clip.noneを明示
        return SizedBox.expand(
          child: Stack(
            clipBehavior: Clip.none, // clip回避
            children: [
              AnimatedBuilder(
                animation: controller,
                builder: (_, __) {
                  // pos.valueは左上隅の座標なので、そのまま使用
                  // ただし、スケール時に中心を基準にするため、中心座標を計算
                  final currentLeft = pos.value.dx;
                  final currentTop = pos.value.dy;

                  // デバッグ用ログ（最初と中間、最後のフレーム）
                  if (controller.value == 0.0) {
                    debugPrint(
                      '[absorb] first frame: pos=${pos.value}, left=$currentLeft, top=$currentTop, opacity=${fade.value}',
                    );
                  } else if (controller.value == 0.5) {
                    debugPrint(
                      '[absorb] mid frame: pos=${pos.value}, left=$currentLeft, top=$currentTop, opacity=${fade.value}',
                    );
                  } else if (controller.value == 1.0) {
                    debugPrint(
                      '[absorb] last frame: pos=${pos.value}, left=$currentLeft, top=$currentTop, opacity=${fade.value}',
                    );
                  }

                  return Positioned(
                    left: currentLeft,
                    top: currentTop,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: fade.value,
                        child: _buildOverlayWidget(previewText),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );

    controller.addStatusListener((status) async {
      if (status == AnimationStatus.completed && !cleanupScheduled) {
        cleanupScheduled = true;
        await Future.delayed(const Duration(seconds: 1));
        debugPrint('[absorb] animation status: completed');
        try {
          entry.remove();
        } catch (e) {
          debugPrint('[absorb] error removing entry on completed: $e');
        }
        _currentOverlayEntry = null;
        _absorbingToken = null;
        // CalendarPage側のisAbsorbingを解除
        try {
          ref.read(calendarControllerProvider.notifier).stopAbsorbing();
          debugPrint('[absorb] CalendarPage: isAbsorbing set to false');
        } catch (e) {
          debugPrint('[absorb] error clearing isAbsorbing: $e');
        }
        if (!cleanupCompleter.isCompleted) {
          cleanupCompleter.complete();
        }
        // アニメーション完了時はpopされるので、_hideOriginalMessageはそのまま（pop後にリセット）
      }
    });

    _currentOverlayEntry = entry;
    debugPrint('[absorb] inserting overlay entry, mounted=$mounted');
    if (!mounted) {
      debugPrint('[absorb] not mounted, cannot insert overlay');
      return false;
    }
    try {
      overlay.insert(entry);
      debugPrint('[absorb] overlay entry inserted');
    } catch (e, stack) {
      debugPrint('[absorb] overlay insert error: $e');
      debugPrint('[absorb] overlay insert error stack: $stack');
      return false;
    }

    debugPrint('[absorb] starting animation forward, mounted=$mounted');
    if (!mounted) {
      debugPrint('[absorb] not mounted, cannot start animation');
      return false;
    }
    try {
      await controller.forward();
      if (!cleanupCompleter.isCompleted) {
        await cleanupCompleter.future;
      }
      debugPrint('[absorb] animation completed');
      return true;
    } catch (e, stack) {
      debugPrint('[absorb] animation error: $e');
      debugPrint('[absorb] animation error stack: $stack');
      if (!cleanupCompleter.isCompleted) {
        cleanupCompleter.complete();
      }
      return false;
    } finally {
      // finallyで必ずtokenをリセット（例外でも戻す）
      _absorbingToken = null;
      if (controller.status != AnimationStatus.completed) {
        try {
          entry.remove();
        } catch (e) {
          debugPrint('[absorb] error removing entry in finally: $e');
        }
        _currentOverlayEntry = null;
        // CalendarPage側のisAbsorbingを解除
        try {
          ref.read(calendarControllerProvider.notifier).stopAbsorbing();
          debugPrint(
            '[absorb] CalendarPage: isAbsorbing set to false (in finally)',
          );
        } catch (e) {
          debugPrint('[absorb] error clearing isAbsorbing in finally: $e');
        }
        // アニメーションが完了しなかった場合は、UIフラグもリセット
        if (mounted) {
          setState(() {
            _hideOriginalMessage = false;
          });
        }
      }
      controller.dispose();
      debugPrint('[absorb] cleanup done');
    }
  }

  /// フォールバックアニメーション（フェードのみ）
  Future<void> _playFallbackAnimation() async {
    debugPrint('[absorb] fallback start');

    // テスト用のfallbackRunnerが注入されている場合はそれを使用
    if (widget.fallbackRunner != null) {
      await widget.fallbackRunner!();
      return;
    }

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );

    try {
      await controller.forward();
      debugPrint('[absorb] fallback completed');
    } catch (e) {
      debugPrint('[absorb] fallback error: $e');
    } finally {
      controller.dispose();
    }
  }

  /// プレビューWidgetを構築（Overlayとプレビュー表示で共通）
  Widget _buildPreviewWidget(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, color: Colors.white),
      ),
    );
  }

  /// Windows用：送信成功UIを構築（Navigator操作なし）
  Widget _buildSentLocalWidget() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'この気持ちは、',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.8),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '未来のあなたに預けられました。',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.8),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Text(
            '次に開けるまで、',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade600,
              height: 1.8,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'ここには表示されません。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade600,
              height: 1.8,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Overlay用のWidgetを構築（デバッグモード：必ず見える形）
  Widget _buildOverlayWidget(String text) {
    return const SizedBox.shrink();
  }

  /// 吸い込み処理を1箇所に集約（成功時に呼ばれる）
  Future<void> _runAbsorbAndClose(
    String previewText, {
    bool allowPop = true,
  }) async {
    // 同一成功イベントでの二重起動を防止するためのtokenを生成
    final token =
        '${DateTime.now().microsecondsSinceEpoch}_${widget.sessionId}';

    // 既に同じtokenで実行中の場合はスキップ
    if (_absorbingToken == token) {
      debugPrint('[absorb] already running with same token, skipping');
      return;
    }

    debugPrint('[absorb] willStart, token=$token');

    // カレンダーを更新（アニメーション前に実行）
    try {
      ref.read(calendarControllerProvider.notifier).refresh();
      debugPrint('[NowSheet] refresh called before animation');
    } catch (e) {
      debugPrint('[NowSheet] refresh error: $e');
    }

    // TextFieldをクリアしてプレビューに切り替え
    _textController.clear();
    if (mounted) {
      setState(() {
        _previewText = previewText;
      });
      debugPrint('[NowSheet] showing preview');
    }

    // 現在のフレームが完了するまで待つ（プレビュー表示を確実にする）
    await SchedulerBinding.instance.endOfFrame;

    if (!mounted) return;

    // originRectを取得（元UIを消す前）
    // _previewKeyは動的キーに変更したため、_composerKeyから取得する
    final screenSize = MediaQuery.of(context).size;
    Rect originRect =
        _globalRectOf(_composerKey) ??
        Rect.fromLTWH(
          (screenSize.width - 280) / 2,
          screenSize.height * 0.3,
          280,
          56,
        );

    if (originRect.width == 0 || originRect.height == 0) {
      // フォールバック：画面中央付近に固定の矩形
      debugPrint('[absorb] originRect invalid, using fallback');
      originRect = Rect.fromLTWH(
        (screenSize.width - 280) / 2,
        screenSize.height * 0.3,
        280,
        56,
      );
      debugPrint('[absorb] originRect fallback: $originRect');
    } else {
      debugPrint('[absorb] originRect: $originRect');
    }

    // Phase 2: ガードを確認してからoriginal UI hidden（吸い込み開始が確定してから）
    // 既に実行中の場合はスキップ（同一成功イベントでの二重起動防止）
    if (_absorbingToken != null) {
      debugPrint(
        '[absorb] already absorbing with token=$_absorbingToken, skipping',
      );
      // スキップ時はフォールバックを実行
      await _runFallbackAndClose();
      return;
    }

    // ガード確定：tokenを設定（吸い込み開始が確定）
    _absorbingToken = token;

    // CalendarPage側の当日セル表示を抑止
    try {
      ref.read(calendarControllerProvider.notifier).startAbsorbing();
      debugPrint('[absorb] CalendarPage: isAbsorbing set to true');
    } catch (e) {
      debugPrint('[absorb] error setting isAbsorbing: $e');
    }

    // Phase 2.5: originRect取得後・Overlay挿入前に元UIを完全に非表示
    // 1. Focusを外す（TextFieldの再描画/カーソル点滅を止める）
    if (mounted) {
      FocusScope.of(context).unfocus();
      debugPrint('[absorb] focus unfocused');
    }

    // 2. setStateでisAbsorbingLocalをtrueに設定（必ずNowSheetState内で実行）
    if (mounted) {
      setState(() {
        _hideOriginalMessage = true;
        _isAbsorbingLocal = true;
      });
      // setState直後に値を確認
      debugPrint(
        '[absorb] isAbsorbingLocal set to true (current value: $_isAbsorbingLocal)',
      );
      debugPrint('[absorb] original UI hidden (before overlay insertion)');
    }

    // 3. フレームが完了するまで待つ（UIが完全に非表示になるまで）
    // 安全のため2フレーム待つ
    await SchedulerBinding.instance.endOfFrame;
    await SchedulerBinding.instance.endOfFrame;
    debugPrint('[absorb] 2 frames completed after hiding UI');

    // フレーム待機後に_isAbsorbingLocalがtrueであることを確認
    if (mounted) {
      debugPrint(
        '[absorb] after frames: _isAbsorbingLocal=$_isAbsorbingLocal (should be true)',
      );
    }

    // Phase 3: Overlayアニメーションを開始
    if (!mounted) {
      // mountedでない場合はフラグを戻して終了
      _absorbingToken = null;
      if (mounted) {
        setState(() {
          _hideOriginalMessage = false;
          _isAbsorbingLocal = false;
        });
      }
      try {
        ref.read(calendarControllerProvider.notifier).stopAbsorbing();
      } catch (e) {
        debugPrint('[absorb] error clearing isAbsorbing: $e');
      }
      return;
    }

    try {
      debugPrint('[absorb] overlay insertion starting');

      // 4. overlayをinsertしてアニメーション開始
      final success = await _playAbsorbAnimation(
        previewText: previewText,
        originRect: originRect,
        token: token,
      );

      debugPrint('[absorb] animation completed, success=$success');

      // 5. アニメーションが失敗した場合はフォールバック
      if (!success) {
        await _runFallbackAndClose();
        if (!mounted) return;
        await SchedulerBinding.instance.endOfFrame;
        if (!mounted) {
          debugPrint('[absorb] not mounted after endOfFrame (fallback)');
          return;
        }
        try {
          // pop直前にUIフラグをfalseに戻してUI復帰を先に行う
          if (!mounted) {
            debugPrint('[absorb] not mounted before setState (fallback)');
            return;
          }
          setState(() {
            _hideOriginalMessage = false;
            _isAbsorbingLocal = false;
          });
          setState(() {
            _hideOriginalMessage = false;
            _isAbsorbingLocal = false;
          });

          if (allowPop) {
            if (!mounted) return;
            Navigator.of(context).pop(SubmitResult.failed);
          }
        } catch (e, stack) {
          debugPrint('[NowSheet] pop error: $e');
          debugPrint('[NowSheet] pop error stack: $stack');
        }
        return;
      }

      // 6. overlay cleanup完了後にpop（フレーム競合を避ける）
      await SchedulerBinding.instance.endOfFrame;

      // 7. popで結果を返す（遷移は呼び出し元で処理）
      if (!mounted) return;
      try {
        // pop直前にUIフラグをfalseに戻してUI復帰を先に行う
        if (!mounted) {
          debugPrint('[absorb] not mounted before setState (success)');
          return;
        }
        setState(() {
          _hideOriginalMessage = false;
          _isAbsorbingLocal = false;
        });
        setState(() {
          _hideOriginalMessage = false;
          _isAbsorbingLocal = false;
        });

        if (allowPop) {
          if (!mounted) return;
          Navigator.of(context).pop(SubmitResult.success);
        }
      } catch (e, stack) {
        debugPrint('[NowSheet] pop error: $e');
        debugPrint('[NowSheet] pop error stack: $stack');
      }
    } catch (e) {
      debugPrint('[NowSheet] absorb animation error: $e');
      // エラー時もフォールバックを実行
      await _runFallbackAndClose();
      if (!mounted) {
        debugPrint('[absorb] not mounted before pop (error fallback path)');
        return;
      }
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;
      try {
        // pop直前にUIフラグをfalseに戻してUI復帰を先に行う
        if (!mounted) return;
        setState(() {
          _hideOriginalMessage = false;
          _isAbsorbingLocal = false;
        });

        if (allowPop) {
          if (!mounted) return;
          Navigator.of(context).pop(SubmitResult.failed);
        }
      } catch (e2, stack) {
        debugPrint('[NowSheet] pop error: $e2');
        debugPrint('[NowSheet] pop error stack: $stack');
      }
    } finally {
      // finallyで必ずUIフラグを戻す（成功・失敗に関わらず）
      debugPrint('[absorb] entering finally block, mounted=$mounted');
      _absorbingToken = null;
      if (!mounted) {
        debugPrint('[absorb] not mounted in finally, skipping setState');
      } else {
        try {
          setState(() {
            _hideOriginalMessage = false;
            _isAbsorbingLocal = false;
          });
          debugPrint('[absorb] UI flags reset in finally');
        } catch (e, stack) {
          debugPrint('[absorb] setState error in finally: $e');
          debugPrint('[absorb] setState error stack in finally: $stack');
        }
      }
      // CalendarPage側のisAbsorbingも解除
      try {
        ref.read(calendarControllerProvider.notifier).stopAbsorbing();
        debugPrint(
          '[absorb] CalendarPage: isAbsorbing set to false (in finally)',
        );
      } catch (e, stack) {
        debugPrint('[absorb] error clearing isAbsorbing in finally: $e');
        debugPrint(
          '[absorb] error clearing isAbsorbing stack in finally: $stack',
        );
      }
      debugPrint('[absorb] finally block completed');
    }
  }

  /// フォールバックアニメーションを実行してからpop
  Future<void> _runFallbackAndClose() async {
    try {
      // 元UIを非表示にする（まだ表示されている場合）
      if (mounted && !_isAbsorbingLocal) {
        setState(() {
          _hideOriginalMessage = true;
          _isAbsorbingLocal = true;
        });
        await SchedulerBinding.instance.endOfFrame;
      }

      // フォールバックアニメーションを実行（150-220ms）
      await _playFallbackAnimation();

      // cleanup完了後にpop
      await SchedulerBinding.instance.endOfFrame;
    } catch (e) {
      debugPrint('[NowSheet] fallback animation error: $e');
    } finally {
      // finallyで必ずtokenとUIフラグをリセット
      _absorbingToken = null;
      if (mounted) {
        setState(() {
          _hideOriginalMessage = false;
          _isAbsorbingLocal = false;
        });
        debugPrint('[absorb] UI flags reset in fallback finally');
      }
      // CalendarPage側のisAbsorbingを解除
      try {
        ref.read(calendarControllerProvider.notifier).stopAbsorbing();
        debugPrint(
          '[absorb] CalendarPage: isAbsorbing set to false (fallback)',
        );
      } catch (e) {
        debugPrint('[absorb] error clearing isAbsorbing in fallback: $e');
      }
    }
  }

  /// 送信成功後に入力欄・プレビュー・ドラフト状態をクリアする（Navigator操作に依存しない）
  void _clearComposerAfterSuccess() {
    final sessionId = DateTime.now().microsecondsSinceEpoch;
    CrashLogger.logDebug(
      '[NowSheet] _clearComposerAfterSuccess: START sessionId=$sessionId',
    );

    // 1. controller.clear() を実行
    _textController.clear();
    CrashLogger.logDebug(
      '[NowSheet] _clearComposerAfterSuccess: textController cleared sessionId=$sessionId',
    );

    // 2. preview / draft state を null にする
    // 3. setState で再描画（TextFieldのkeyを変更して再生成を強制）
    if (mounted) {
      setState(() {
        _previewText = null;
        _hideOriginalMessage = false;
        _isAbsorbingLocal = false;
        // _uiStateは呼び出し元で管理（Windowsの場合はsent、Androidの場合はabsorb処理）
        _textFieldKey++; // TextFieldを再生成するためにkeyを変更
      });
      CrashLogger.logDebug(
        '[NowSheet] _clearComposerAfterSuccess: preview state cleared, textFieldKey=$_textFieldKey sessionId=$sessionId',
      );
    } else {
      CrashLogger.logInfo(
        '[NowSheet] _clearComposerAfterSuccess: not mounted, skipping setState sessionId=$sessionId',
      );
    }

    // 4. キーボードを閉じる
    if (mounted) {
      try {
        CrashLogger.logDebug(
          '[NowSheet] _clearComposerAfterSuccess: BEFORE unfocus() sessionId=$sessionId',
        );
        FocusScope.of(context).unfocus();
        CrashLogger.logDebug(
          '[NowSheet] _clearComposerAfterSuccess: AFTER unfocus() sessionId=$sessionId',
        );
      } catch (e, stack) {
        CrashLogger.logException(
          e,
          stack,
          context:
              'NowSheet _clearComposerAfterSuccess unfocus error sessionId=$sessionId',
        );
      }
    }

    CrashLogger.logDebug(
      '[NowSheet] _clearComposerAfterSuccess: COMPLETED sessionId=$sessionId',
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final controller = ref.read(nowControllerProvider.notifier);
    final currentDate = ref.read(nowControllerProvider).selectedDate;
    final today = TimeUtils.today();
    final firstDate = today;
    final lastDate = DateTime(today.year + 10, 12, 31);

    // initialDateがfirstDateより前の場合は、firstDateを使用
    final initialDate = currentDate.isBefore(firstDate)
        ? firstDate
        : currentDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );

    if (picked != null) {
      controller.updateDate(picked);
    }
  }

  Future<void> _handleSubmit({String source = 'unknown'}) async {
    // 監査用: unique sessionIdとtimestampを生成
    final submitSessionId = DateTime.now().microsecondsSinceEpoch;
    final submitTimestamp = DateTime.now().toIso8601String();

    // 二重送信ガード（早期リターン）
    if (_isSubmitting) {
      CrashLogger.logDebug(
        '[NowSheet] _handleSubmit: BLOCKED (already submitting) source=$source sessionId=$submitSessionId',
      );
      return;
    }

    // 空テキストガード（早期リターン、stackTraceは出さない）
    final text = _textController.text;
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      // ノイズ削減のため、stackTraceを出さず簡潔なログのみ
      CrashLogger.logDebug(
        '[NowSheet] _handleSubmit: BLOCKED (empty text) source=$source sessionId=$submitSessionId len=${text.length} trimLen=${trimmedText.length}',
      );
      return;
    }

    // 正常な送信開始時のみ詳細ログ（状態ログ＋StackTrace）
    final stackTrace = StackTrace.current;
    final stackLines = stackTrace.toString().split('\n').take(10).join('\n');
    CrashLogger.logDebug(
      '[NowSheet] _handleSubmit called source=$source sessionId=$submitSessionId timestamp=$submitTimestamp',
    );
    CrashLogger.logDebug(
      '[NowSheet] _handleSubmit stackTrace (first 10 lines):\n$stackLines',
    );
    CrashLogger.logDebug(
      '[NowSheet] _handleSubmit state: _isSubmitting=$_isSubmitting mounted=$mounted uiState=$_uiState',
    );

    // エラー表示をリセット
    ref.read(nowControllerProvider.notifier).resetStatus();

    // 送信開始：ロックを設定
    _isSubmitting = true;
    _updateUiState(NowSheetUiState.submitting, sessionId: submitSessionId);
    CrashLogger.logDebug(
      '[NowSheet] _handleSubmit: START submitting source=$source sessionId=$submitSessionId',
    );

    try {
      final controller = ref.read(nowControllerProvider.notifier);
      await controller.submit(text, sessionId: submitSessionId);
      CrashLogger.logDebug(
        '[NowSheet] _handleSubmit: submit() completed sessionId=$submitSessionId',
      );
    } catch (e, stack) {
      CrashLogger.logException(
        e,
        stack,
        context:
            'NowSheet _handleSubmit submit error sessionId=$submitSessionId',
      );
      _isSubmitting = false;
      CrashLogger.logDebug(
        '[NowSheet] _handleSubmit: submit error, _isSubmitting reset sessionId=$submitSessionId',
      );
      rethrow;
    }

    // 状態を確認
    final state = ref.read(nowControllerProvider);

    CrashLogger.logDebug(
      '[NowSheet] _handleSubmit: submitStatus=${state.submitStatus} sessionId=$submitSessionId',
    );

    if (state.submitStatus == SubmitStatus.success && mounted) {
      CrashLogger.logDebug(
        '[NowSheet] _handleSubmit: SUCCESS sessionId=$submitSessionId',
      );

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('送信しました'),
          duration: Duration(seconds: 2),
        ),
      );

      // submit成功直後に共通クリア処理を実行（Navigator操作に依存しない位置）
      _clearComposerAfterSuccess();

      // 吸い込み演出は全プラットフォームで必ず実行
      final allowPop = !Platform.isWindows;
      await _runAbsorbAndClose(text.trim(), allowPop: allowPop);
      if (allowPop) {
        _isSubmitting = false;
        CrashLogger.logDebug(
          '[NowSheet] _handleSubmit: absorb done, _isSubmitting reset sessionId=$submitSessionId',
        );
        return;
      }

      CrashLogger.logDebug(
        '[NowSheet] Windows: Navigator operations disabled, using local state transition sessionId=$submitSessionId',
      );

      // 送信成功UIを表示（Navigator操作は一切行わない）
      if (!mounted) {
        CrashLogger.logInfo(
          '[NowSheet] Windows: not mounted before showing sent UI sessionId=$submitSessionId',
        );
        return;
      }

      _updateUiState(NowSheetUiState.sent, sessionId: submitSessionId);
      CrashLogger.logDebug(
        '[NowSheet] Windows: sent UI shown sessionId=$submitSessionId',
      );

      // 既存のタイマーをキャンセル（二重起動防止）
      _sentResetTimer?.cancel();
      _sentResetTimer = null;
      CrashLogger.logDebug(
        '[NowSheet] Windows: existing timer cancelled (if any) sessionId=$submitSessionId',
      );

      // 2.5秒後に自動的にリセットして入力画面へ戻す（思考が「手放した」ことを認識するのに必要な時間）
      _sentResetTimer = Timer(const Duration(milliseconds: 2500), () {
        _onSentResetTimer(sessionId: submitSessionId);
      });
      CrashLogger.logDebug(
        '[NowSheet] Windows: _sentResetTimer started (2500ms) sessionId=$submitSessionId',
      );
      _isSubmitting = false;
      CrashLogger.logDebug(
        '[NowSheet] _handleSubmit: Windows sent UI shown, _isSubmitting reset sessionId=$submitSessionId',
      );
      return;
    } else if (state.submitStatus == SubmitStatus.failure) {
      CrashLogger.logDebug(
        '[NowSheet] _handleSubmit: FAILURE sessionId=$submitSessionId',
      );
      // 失敗時はUIにエラーメッセージが表示される（何もしない）
      if (mounted) {
        _updateUiState(NowSheetUiState.input, sessionId: submitSessionId);
      }
      _isSubmitting = false;
      CrashLogger.logDebug(
        '[NowSheet] _handleSubmit: failure, _isSubmitting reset sessionId=$submitSessionId',
      );
    }
  }

  /// Windows用：送信成功後のリセットタイマーコールバック（dispose後setState防止）
  void _onSentResetTimer({required int sessionId}) {
    final timerStartTime = DateTime.now();
    CrashLogger.logDebug(
      '[NowSheet] Windows: _onSentResetTimer STARTED sessionId=$sessionId timestamp=${timerStartTime.toIso8601String()}',
    );

    if (!mounted) {
      CrashLogger.logInfo(
        '[NowSheet] Windows: _onSentResetTimer called after dispose sessionId=$sessionId',
      );
      return;
    }

    // addPostFrameCallbackを削除し、Timer発火後に即状態更新（フレーム停止による遅延を回避）
    // Future(() {})で次のmicrotaskへ送る（軽量で確実な実行）
    Future(() {
      final futureStartTime = DateTime.now();
      final timerDelay = futureStartTime
          .difference(timerStartTime)
          .inMilliseconds;
      CrashLogger.logDebug(
        '[NowSheet] Windows: _onSentResetTimer Future callback STARTED sessionId=$sessionId timerDelay=${timerDelay}ms timestamp=${futureStartTime.toIso8601String()}',
      );

      if (!mounted) {
        CrashLogger.logInfo(
          '[NowSheet] Windows: _onSentResetTimer Future callback called after dispose sessionId=$sessionId',
        );
        return;
      }

      // mountedチェック済みで即状態更新（addPostFrameCallbackによる遅延を回避）
      _updateUiState(NowSheetUiState.input, sessionId: sessionId);
      final updateEndTime = DateTime.now();
      final updateDelay = updateEndTime
          .difference(futureStartTime)
          .inMilliseconds;
      final totalDelay = updateEndTime
          .difference(timerStartTime)
          .inMilliseconds;
      CrashLogger.logDebug(
        '[NowSheet] Windows: reset completed, back to input screen sessionId=$sessionId totalDelay=${totalDelay}ms updateDelay=${updateDelay}ms timestamp=${updateEndTime.toIso8601String()}',
      );
    });
  }

  /// UI状態を更新（単一の更新関数で分岐を減らす）
  /// safeSetState経由でUI更新（例外は握りつぶさない）
  void _updateUiState(NowSheetUiState newState, {required int sessionId}) {
    if (!mounted) {
      CrashLogger.logInfo(
        '[NowSheet] _updateUiState: not mounted, skipping state=$newState sessionId=$sessionId',
      );
      return;
    }

    // safeSetState経由でUI更新（mountedチェック済み、例外は握りつぶさない）
    safeSetState(() {
      _uiState = newState;
    });
    CrashLogger.logDebug(
      '[NowSheet] _updateUiState: state=$newState sessionId=$sessionId',
    );
  }

  @override
  Widget build(BuildContext context) {
    // デバッグログ：buildの先頭で必ず状態を確認
    CrashLogger.logTrace(
      '[NowSheet] build: _isAbsorbingLocal=$_isAbsorbingLocal, _hideOriginalMessage=$_hideOriginalMessage, _uiState=$_uiState, _isSubmitting=$_isSubmitting',
    );

    final state = ref.watch(nowControllerProvider);
    final selectedDate = state.selectedDate;

    // 送信可能かどうかを判定（保守性向上のため条件を集約）
    final canSubmit =
        mounted &&
        !_isSubmitting &&
        _uiState == NowSheetUiState.input &&
        state.submitStatus != SubmitStatus.submitting &&
        _textController.text.trim().isNotEmpty;

    return AbsorbPointer(
      // 送信中はすべての入力を受け付けない（二重送信防止）
      absorbing: _isSubmitting || _uiState == NowSheetUiState.submitting,
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            key: _composerKey,
            padding: const EdgeInsets.all(24),
            color: Colors.black,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Windows用：送信成功UIを表示（Navigator操作なし）
                if (_uiState == NowSheetUiState.sent && Platform.isWindows)
                  _buildSentLocalWidget()
                // 吸い込み中は元UIを完全に非表示（残像を防ぐ）
                // _isAbsorbingLocalがtrueの場合は完全にツリーから外す（SizedBox.shrink）
                // Opacity/AnimatedOpacity/Visibility(maintainState:true)は禁止
                else if (_isAbsorbingLocal)
                  Builder(
                    builder: (context) {
                      CrashLogger.logTrace(
                        '[NowSheet] build: inputUI/preview layer SKIPPED (isAbsorbingLocal=true)',
                      );
                      return const SizedBox.shrink();
                    },
                  )
                else
                  // 通常時はVisibilityで制御
                  // maintainState: false にして、送信成功後にTextFieldを確実に再生成する
                  Visibility(
                    visible: !_hideOriginalMessage,
                    maintainState: false, // 送信成功後に状態を維持しない
                    maintainAnimation: false,
                    maintainSize: false,
                    child: Builder(
                      builder: (context) {
                        CrashLogger.logTrace(
                          '[NowSheet] build: inputUI/preview layer rendered, isAbsorbingLocal=$_isAbsorbingLocal, hideOriginalMessage=$_hideOriginalMessage, controller.text="${_textController.text}", textFieldKey=$_textFieldKey',
                        );
                        // Containerのkeyも動的に変更して、確実に再生成されるようにする
                        return Container(
                          key: ValueKey('previewContainer_$_textFieldKey'),
                          child: _previewText != null
                              ? _buildPreviewWidget(_previewText!)
                              : TextField(
                                  key: ValueKey(
                                    'textField_$_textFieldKey',
                                  ), // 送信成功後に再生成されるようにkeyを動的に変更
                                  controller: _textController,
                                  focusNode: _focusNode,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w300,
                                    fontSize: 18,
                                    height: 1.8,
                                    color: Colors.white,
                                  ),
                                  maxLines: null,
                                  maxLength: 140,
                                  // カウンター（0/140）を物理的に消去
                                  buildCounter:
                                      (
                                        context, {
                                        required currentLength,
                                        required isFocused,
                                        maxLength,
                                      }) => null,
                                  enabled:
                                      !_isSubmitting &&
                                      _uiState !=
                                          NowSheetUiState.submitting, // 送信中は無効化
                                  decoration: const InputDecoration(
                                    // 命令的な言葉を消し、余白として機能させる
                                    hintText: '...',
                                    hintStyle: TextStyle(color: Colors.white54),
                                    // 枠線を完全に排除
                                    border: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  onChanged: (_) {
                                    // テキスト変更時に送信ボタンの状態を更新するためsetStateを呼ぶ
                                    if (mounted) {
                                      setState(() {});
                                    }
                                  },
                                  // submit is handled by the button only
                                ),
                        );
                      },
                    ),
                  ),
                // Windowsで送信成功UI表示中は日付選択とボタンを非表示
                if (!(_uiState == NowSheetUiState.sent &&
                    Platform.isWindows)) ...[
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => _selectDate(context),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white54),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          const Text('届く日 ', style: TextStyle(color: Colors.white)),
                          Text(
                            FormatUtils.formatDate(selectedDate),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.calendar_today, size: 20, color: Colors.white),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          // 送信ボタンの有効/無効は canSubmit で判定（保守性向上）
                          onPressed: canSubmit
                              ? () => _handleSubmit(source: 'button')
                              : null,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.white12,
                            foregroundColor: Colors.white,
                          ),
                          child:
                              (_isSubmitting ||
                                  state.submitStatus ==
                                      SubmitStatus.submitting ||
                                  _uiState == NowSheetUiState.submitting)
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : state.submitStatus == SubmitStatus.success
                              ? const Text('保存しました')
                              : const Text('Send to After'),
                        ),
                      ),
                      if (state.submitStatus == SubmitStatus.failure &&
                          state.errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            state.errorMessage!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
