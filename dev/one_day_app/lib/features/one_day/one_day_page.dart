import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../data/one_day_close_repo.dart';

/// 思考のスクラップブック - 午前4時でリセット
class OneDayPage extends StatefulWidget {
  const OneDayPage({super.key});

  @override
  State<OneDayPage> createState() => _OneDayPageState();
}

class _OneDayPageState extends State<OneDayPage> with WidgetsBindingObserver {
  final _repo = OneDayCloseRepo();
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  List<TextPhrase> _phrases = [];
  bool _isExpired = false;
  int _totalCharacterCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // アプリが復帰した時に午前4時をまたいだかチェック
    if (state == AppLifecycleState.resumed) {
      _checkExpiration();
    }
  }

  /// 午前4時をまたいだかチェックして自動的にクリア
  Future<void> _checkExpiration() async {
    final crossed = await _repo.hasCrossed4AM();
    if (crossed && !_isExpired) {
      if (mounted) {
        await _repo.clear();
        setState(() {
          _isExpired = false; // リセット後は即座に入力可能に
          _phrases = [];
          _totalCharacterCount = 0;
        });
        // リセット後、新しい入力ができる状態にする
        await _loadPhrases();
      }
    } else {
      // まだ有効ならフレーズを再読み込み
      await _loadPhrases();
    }
  }

  /// 初期化
  Future<void> _init() async {
    await _checkExpiration();
    if (!_isExpired) {
      await _loadPhrases();
    }
  }

  /// フレーズを読み込む
  Future<void> _loadPhrases() async {
    final phrases = await _repo.loadPhrases();
    final totalCount = await _repo.getTotalCharacterCount();
    if (kDebugMode) {
      debugPrint(
        '[OneDayPage] _loadPhrases: phrases=${phrases.length}, totalCount=$totalCount',
      );
    }
    if (mounted) {
      setState(() {
        _phrases = phrases;
        _totalCharacterCount = totalCount;
        _isExpired = false;
      });
      if (kDebugMode) {
        debugPrint(
          '[OneDayPage] _loadPhrases: setState完了。_totalCharacterCount=$_totalCharacterCount, remainingChars=${30 - _totalCharacterCount}',
        );
      }
    }
  }

  /// テキストのRectを計算（回転を考慮）
  Rect _calculateTextRect(
    String text,
    double fontSize,
    double rotation,
    Offset center,
    double circleRadius,
  ) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontWeight: FontWeight.w200, fontSize: fontSize), // 極細
      ),
      textDirection: TextDirection.ltr,
      maxLines: null, // 改行を許可
    );
    textPainter.layout();

    // 回転を考慮したバウンディングボックス
    final width = textPainter.width;
    final height = textPainter.height;

    // 回転後のバウンディングボックスを計算
    final cosR = cos(rotation);
    final sinR = sin(rotation);
    final rotatedWidth = (width * cosR.abs() + height * sinR.abs());
    final rotatedHeight = (width * sinR.abs() + height * cosR.abs());

    return Rect.fromCenter(
      center: center,
      width: rotatedWidth,
      height: rotatedHeight,
    );
  }

  /// 文字数に応じたフォントサイズを計算（動的スケーリング）
  /// 文章の長さに応じてより積極的にフォントサイズを調整
  double _calculateFontSize(String text, double baseFontSize) {
    final length = text.length;
    // より細かく段階的にフォントサイズを調整（全体的に+2px大きく）
    if (length <= 5) {
      return baseFontSize; // 20px
    } else if (length <= 10) {
      return baseFontSize - 1; // 19px
    } else if (length <= 15) {
      return baseFontSize - 2; // 18px
    } else if (length <= 20) {
      return baseFontSize - 4; // 16px
    } else if (length <= 25) {
      return baseFontSize - 6; // 14px
    } else {
      return baseFontSize - 8; // 12px
    }
  }

  /// 長い文字列の最大幅を計算（改行を防ぐため、非常に大きな値を返す）
  double? _calculateMaxWidth(String text, double radius) {
    // 改行を防ぐため、非常に大きな値を返す（実質的に改行なし）
    return double.infinity;
  }

  /// 既存のフレーズと重ならない座標を探索（動的スケーリング対応）
  Offset _findNonOverlappingPosition(
    String text,
    double baseFontSize,
    double rotation,
    double circleSize,
    List<TextPhrase> existingPhrases,
  ) {
    final center = Offset(circleSize / 2, circleSize / 2);
    final radius = circleSize / 2 - 2;
    final random = Random();
    double currentFontSize = _calculateFontSize(text, baseFontSize);

    // 最大試行回数を増やし、段階的に条件を緩める（5段階に拡大）
    for (int retryStep = 0; retryStep < 5; retryStep++) {
      // step 0-1: 厳格な判定
      // step 2-3: フォントサイズを下げて再試行
      // step 4: 重なり判定を無視して境界内だけに収める

      for (int attempt = 0; attempt < 100; attempt++) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontWeight: FontWeight.w300, // 少し太く（w200→w300）
              fontSize: currentFontSize,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        // 改行を防ぐため、maxWidthをnullにする（改行なし）
        textPainter.layout();

        final W = textPainter.width;
        final H = textPainter.height;

        // 配置範囲を計算（円の内側に収まるランダム座標）
        // 安全なマージン（半径の90%）を考慮して配置範囲を計算
        final safeRadius = radius * 0.9;
        final angle = random.nextDouble() * 2 * pi;
        final maxAllowedDist = safeRadius - (max(W, H) / 2);
        if (maxAllowedDist <= 0) {
          // テキストが大きすぎる場合は、フォントサイズを下げて再試行
          currentFontSize = max(8.0, currentFontSize - 1);
          continue;
        }
        final dist = random.nextDouble() * maxAllowedDist;
        final candidateCenter = Offset(
          center.dx + cos(angle) * dist,
          center.dy + sin(angle) * dist,
        );

        // 包含判定（四隅チェック）：円の境界を厳格にチェック
        // 安全なマージン（半径の90%）以内に収まるようにする
        bool isWithin = true;
        final corners = [
          Offset(candidateCenter.dx - W / 2, candidateCenter.dy - H / 2),
          Offset(candidateCenter.dx + W / 2, candidateCenter.dy - H / 2),
          Offset(candidateCenter.dx - W / 2, candidateCenter.dy + H / 2),
          Offset(candidateCenter.dx + W / 2, candidateCenter.dy + H / 2),
        ];
        for (var corner in corners) {
          final d = (corner - center).distance;
          if (d > safeRadius) {
            isWithin = false;
            break;
          }
        }
        if (!isWithin) continue;

        // 重なり判定：常に実行（円の中の文字は重ならないようにする）
        bool overlaps = false;
        final candidateRect = Rect.fromCenter(
          center: candidateCenter,
          width: W,
          height: H,
        );

        // 安全なマージンを考慮して既存のテキストの位置を計算（safeRadiusは既に定義済み）
        for (var p in existingPhrases) {
          final pCenter = Offset(
            center.dx + p.x * safeRadius,
            center.dy + p.y * safeRadius,
          );

          // 既存のテキストの矩形を計算
          final existingTextPainter = TextPainter(
            text: TextSpan(
              text: p.text,
              style: TextStyle(
                fontWeight: FontWeight.w300, // 少し太く（w200→w300）
                fontSize: p.fontSize,
              ),
            ),
            textDirection: TextDirection.ltr,
          );
          // 改行を防ぐため、maxWidthをnullにする（改行なし）
          existingTextPainter.layout();

          final existingRect = Rect.fromCenter(
            center: pCenter,
            width: existingTextPainter.width,
            height: existingTextPainter.height,
          );

          // 重なり判定を厳格化：矩形の実際の幅と高さを使用
          final distBetweenCenters = (candidateCenter - pCenter).distance;

          // 矩形の実際の幅と高さを使用して、より正確な重なり判定を行う
          final candidateWidth = W;
          final candidateHeight = H;
          final existingWidth = existingTextPainter.width;
          final existingHeight = existingTextPainter.height;

          // 最小距離：両方の矩形の対角線の合計にマージンを追加
          final candidateDiagonal = sqrt(
            candidateWidth * candidateWidth + candidateHeight * candidateHeight,
          );
          final existingDiagonal = sqrt(
            existingWidth * existingWidth + existingHeight * existingHeight,
          );
          final minDistance =
              (candidateDiagonal + existingDiagonal) / 2 +
              20; // 20pxのマージンを追加（重なりを確実に防ぐ）

          // 矩形の重なりをチェック（より厳格な判定）
          // 矩形が重なる、または中心間の距離が最小距離より小さい場合は重なりとみなす
          if (candidateRect.overlaps(existingRect) ||
              distBetweenCenters < minDistance) {
            overlaps = true;
            break;
          }

          // 追加の重なりチェック：矩形の各辺が重なっていないか確認
          final candidateLeft = candidateCenter.dx - candidateWidth / 2;
          final candidateRight = candidateCenter.dx + candidateWidth / 2;
          final candidateTop = candidateCenter.dy - candidateHeight / 2;
          final candidateBottom = candidateCenter.dy + candidateHeight / 2;

          final existingLeft = pCenter.dx - existingWidth / 2;
          final existingRight = pCenter.dx + existingWidth / 2;
          final existingTop = pCenter.dy - existingHeight / 2;
          final existingBottom = pCenter.dy + existingHeight / 2;

          // 矩形が重なっているかチェック（マージン付き）
          final margin = 8.0; // 8pxのマージン
          if (!(candidateRight + margin < existingLeft ||
              candidateLeft - margin > existingRight ||
              candidateBottom + margin < existingTop ||
              candidateTop - margin > existingBottom)) {
            overlaps = true;
            break;
          }
        }
        if (overlaps) continue;

        // 成功：正規化して返す
        return Offset(
          (candidateCenter.dx - center.dx) / radius,
          (candidateCenter.dy - center.dy) / radius,
        );
      }
      // 次のステップへ（サイズを小さくする、ペースを早める）
      currentFontSize = max(8.0, currentFontSize - 2);
    }

    // 最終防衛線：5段階試しても場所が見つからない場合
    // フォントサイズを8pxに固定し、重なりを無視して強制配置
    final finalFontSize = 8.0;
    final finalMaxWidth =
        _calculateMaxWidth(text, radius) ?? (radius * 2 * 0.9);
    final finalTextPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontWeight: FontWeight.w300,
          fontSize: finalFontSize,
        ), // 少し太く（w200→w300）
      ),
      textDirection: TextDirection.ltr,
    );
    finalTextPainter.layout(maxWidth: finalMaxWidth);

    final finalW = finalTextPainter.width;
    final finalH = finalTextPainter.height;

    // 円の中心付近の空いている場所を探索（最大50回）
    for (int finalAttempt = 0; finalAttempt < 50; finalAttempt++) {
      final finalAngle = random.nextDouble() * 2 * pi;
      final finalMaxAllowedDist = radius * 0.8 - (max(finalW, finalH) / 2);
      if (finalMaxAllowedDist <= 0) {
        // それでも入らない場合は、さらに小さくする
        break;
      }
      final finalDist = random.nextDouble() * finalMaxAllowedDist;
      final finalCandidateCenter = Offset(
        center.dx + cos(finalAngle) * finalDist,
        center.dy + sin(finalAngle) * finalDist,
      );

      // 包含判定のみ（重なりは無視）
      bool finalIsWithin = true;
      final finalCorners = [
        Offset(
          finalCandidateCenter.dx - finalW / 2,
          finalCandidateCenter.dy - finalH / 2,
        ),
        Offset(
          finalCandidateCenter.dx + finalW / 2,
          finalCandidateCenter.dy - finalH / 2,
        ),
        Offset(
          finalCandidateCenter.dx - finalW / 2,
          finalCandidateCenter.dy + finalH / 2,
        ),
        Offset(
          finalCandidateCenter.dx + finalW / 2,
          finalCandidateCenter.dy + finalH / 2,
        ),
      ];
      for (var finalCorner in finalCorners) {
        final finalD = (finalCorner - center).distance;
        if (finalD > radius) {
          finalIsWithin = false;
          break;
        }
      }
      if (finalIsWithin) {
        // 成功：正規化して返す
        return Offset(
          (finalCandidateCenter.dx - center.dx) / radius,
          (finalCandidateCenter.dy - center.dy) / radius,
        );
      }
    }

    // それでも見つからない場合は、中央付近に強制配置
    return Offset(
      (random.nextDouble() - 0.5) * 0.2,
      (random.nextDouble() - 0.5) * 0.2,
    );
  }

  /// テキストを確定してランダム配置
  Future<void> _submitText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    // 30文字制限を撤廃：円の中に物理的に収まる限り入力可能

    // ランダムな角度を生成
    final random = Random();
    final baseFontSize = 20.0; // ベースフォントサイズ（+2px大きく）
    final rotation = (random.nextDouble() * 30 - 15) * (pi / 180); // -15度〜+15度

    // 円のサイズを取得
    final mediaQuery = MediaQuery.of(context);
    final circleSize = mediaQuery.size.shortestSide * 0.5;

    // デバッグ情報：配置前の状態
    if (kDebugMode) {
      debugPrint(
        '[OneDayPage] _submitText: 配置開始。text="$text" (${text.length}文字), existingPhrases=${_phrases.length}, totalChars=$_totalCharacterCount, circleSize=$circleSize',
      );
    }

    // 衝突判定を行い、重ならない座標を探索（動的スケーリング対応）
    final position = _findNonOverlappingPosition(
      text,
      baseFontSize,
      rotation,
      circleSize,
      _phrases,
    );

    // デバッグ情報：配置後の状態
    if (kDebugMode) {
      debugPrint(
        '[OneDayPage] _submitText: 配置成功。position=(${position.dx.toStringAsFixed(3)}, ${position.dy.toStringAsFixed(3)}), fontSize=${_calculateFontSize(text, baseFontSize)}',
      );
    }

    final phrase = TextPhrase(
      text: text,
      x: position.dx,
      y: position.dy,
      rotation: rotation,
      fontSize: _calculateFontSize(text, baseFontSize),
    );

    await _repo.addPhrase(phrase);
    await _loadPhrases();

    // デバッグ情報：読み込み後の状態
    if (kDebugMode) {
      debugPrint(
        '[OneDayPage] _submitText: 読み込み完了。_totalCharacterCount=$_totalCharacterCount, remainingChars=${30 - _totalCharacterCount}',
      );
    }

    _textController.clear();
    // 確実に入力欄にフォーカスを戻す
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final shortestSide = mediaQuery.size.shortestSide;
    final circleSize = shortestSide * 0.5;

    // 30文字制限を撤廃：円の中に物理的に収まる限り入力可能
    // remainingCharsの計算を削除（制限なし）

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF), // 純白
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Stack(
          children: [
            // 背景タップでフォーカス
            GestureDetector(
              onTap: () {
                _focusNode.requestFocus();
              },
              behavior: HitTestBehavior.translucent,
              child: Container(
                color: Colors.transparent,
                width: double.infinity,
                height: double.infinity,
              ),
            ),

            // 中央の円とフレーズ
            Center(
              child: GestureDetector(
                onTap: () {
                  _focusNode.requestFocus();
                },
                child: SizedBox(
                  width: circleSize,
                  height: circleSize,
                  child: Stack(
                    children: [
                      // 円（輪郭線のみ）
                      CustomPaint(
                        size: Size(circleSize, circleSize),
                        painter: _CirclePainter(strokeWidth: 1.2),
                      ),

                      // フレーズをランダム配置
                      ..._phrases.map((phrase) {
                        return _buildPhraseWidget(phrase, circleSize);
                      }),
                    ],
                  ),
                ),
              ),
            ),

            // 入力欄（画面最下部に固定配置）
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 20,
                    right: 20,
                    bottom: 60, // キーボードに隠れない位置に完全に固定
                  ),
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    enabled: true, // 常に有効（円の中に収まる限り入力可能）
                    maxLength: null, // 文字数制限なし（円の中に物理的に収まる限り入力可能）
                    buildCounter:
                        (
                          context, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => const SizedBox.shrink(),
                    textAlign: TextAlign.center,
                    autofocus: true,
                    cursorWidth: 3.0, // カーソルの存在感を強める
                    style: const TextStyle(
                      fontWeight: FontWeight.w300, // w300に変更（細く）
                      fontSize: 18,
                      color: Colors.black, // 入力の確かな手応えを感じられる濃さ
                    ),
                    decoration: InputDecoration(
                      hintText: '...', // 究極にシンプルに
                      hintStyle: const TextStyle(
                        color: Colors.black45, // 視認性向上（さらに濃く）
                        fontWeight: FontWeight.w200,
                        fontSize: 18,
                      ),
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 20,
                      ),
                    ),
                    onSubmitted: (_) => _submitText(),
                  ),
                ),
              ),
            ),

            // DEBUG: デバッグ用リセットボタン（画面右下）
            Positioned(
              bottom: 20,
              right: 20,
              child: GestureDetector(
                onTap: () async {
                  // DEBUG: リセットボタン - 本番リリース時には削除
                  await _repo.clear();
                  if (mounted) {
                    setState(() {
                      _phrases = [];
                      _totalCharacterCount = 0;
                      _isExpired = false;
                      _textController.clear();
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black12, width: 1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Reset',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w300,
                      color: Colors.black54,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// フレーズウィジェットを構築
  Widget _buildPhraseWidget(TextPhrase phrase, double circleSize) {
    final center = circleSize / 2;
    final radius = circleSize / 2 - 1; // 境界線から1px内側
    final safeRadius = radius * 0.9; // 安全なマージン（半径の90%）

    // 円の中心からの相対座標を絶対座標に変換（安全なマージンを考慮）
    final x = center + phrase.x * safeRadius;
    final y = center + phrase.y * safeRadius;

    // テキストのサイズを計算（改行を防ぐ）
    final textPainter = TextPainter(
      text: TextSpan(
        text: phrase.text,
        style: TextStyle(
          fontWeight: FontWeight.w300, // 少し太く（w200→w300）
          fontSize: phrase.fontSize,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1, // 改行を禁止（1行のみ）
    );
    textPainter.layout(); // 改行なしでレイアウト

    return Positioned(
      // テキストの幅に合わせて配置を補正
      left: x - (textPainter.width / 2),
      top: y - (textPainter.height / 2),
      child: Transform.rotate(
        angle: phrase.rotation,
        child: SizedBox(
          width: textPainter.width, // maxWidthではなく実際の幅に
          child: Text(
            phrase.text,
            style: TextStyle(
              fontWeight: FontWeight.w300, // 少し太く（w200→w300）
              fontSize: phrase.fontSize,
              color: Colors.black87, // 墨色に近い濃さで視認性向上
            ),
            textAlign: TextAlign.center,
            softWrap: false, // 改行を禁止
            overflow: TextOverflow.visible, // はみ出しても表示
          ),
        ),
      ),
    );
  }
}

/// 円を描画するCustomPainter（輪郭線のみ）
class _CirclePainter extends CustomPainter {
  final double strokeWidth;

  _CirclePainter({required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeWidth / 2;

    // 円の輪郭を描画（塗りつぶしなし）
    final strokePaint = Paint()
      ..color =
          const Color(0xFF1A1A1A) // 墨色
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, strokePaint);
  }

  @override
  bool shouldRepaint(_CirclePainter oldDelegate) {
    return oldDelegate.strokeWidth != strokeWidth;
  }
}
