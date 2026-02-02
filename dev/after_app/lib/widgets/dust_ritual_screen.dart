import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/dust_particle.dart';
import '../core/dust_particle_helpers.dart';
import 'sever_line.dart';
import 'silent_void.dart';

/// 塵の儀式（Dust Ritual）画面
/// 水平線を軸に、過去を浄化する演出を実装
class DustRitualScreen extends StatefulWidget {
  final void Function(BuildContext)? onComplete;

  const DustRitualScreen({super.key, this.onComplete});

  @override
  State<DustRitualScreen> createState() => _DustRitualScreenState();
}

enum DustRitualState {
  input, // 入力中
  decomposing, // 分解中（3.0秒）
  voidState, // 空白の強制（1.5秒）
  complete, // 完了
}

class _DustRitualScreenState extends State<DustRitualScreen>
    with TickerProviderStateMixin {
  final _dustInputController = TextEditingController();
  final _dustInputFocusNode = FocusNode();
  DustRitualState _state = DustRitualState.input;
  List<DustParticle> _particles = [];
  late AnimationController _decomposeController;
  Rect? _textRect;
  Duration _lastElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _decomposeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000), // 3.0秒
    );

    _decomposeController.addListener(_updateParticles);
    _decomposeController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _startVoid();
      }
    });

    // フォーカスを設定
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dustInputFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _decomposeController.dispose();
    _dustInputController.dispose();
    _dustInputFocusNode.dispose();
    super.dispose();
  }

  void _startDecomposition() {
    final text = _dustInputController.text.trim();
    if (text.isEmpty) return;

    // ハプティックフィードバック：砂が崩れるような微細な振動
    HapticFeedback.mediumImpact();

    setState(() {
      _state = DustRitualState.decomposing;
    });

    // テキストの位置を取得してパーティクルを生成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _generateParticles(text);
      _decomposeController.forward();
    });
  }

  void _generateParticles(String text) {
    if (_textRect == null) return;

    // テキストの長さに応じてパーティクル数を決定（1000-3000個）
    final particleCount = math.min(3000, math.max(1000, text.length * 50));

    // 背景よりわずかに濃いグレー
    final dustColor = const Color(0xFF9CA3AF); // ノイズのような質感

    _particles = DustParticleGenerator.generateFromText(
      text: text,
      textRect: _textRect!,
      textColor: dustColor,
      particleCount: particleCount,
    );
  }

  void _updateParticles() {
    if (!mounted || _state != DustRitualState.decomposing) return;

    setState(() {
      final screenSize = MediaQuery.of(context).size;
      final elapsed = _decomposeController.lastElapsedDuration ?? Duration.zero;
      var dt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
      if (dt <= 0) {
        dt = 1.0 / 60.0;
      } else if (dt > 1.0 / 30.0) {
        dt = 1.0 / 30.0;
      }
      _lastElapsed = elapsed;
      for (final p in _particles) {
        p.update(_decomposeController.value, dt, screenSize);
      }
      _particles = _particles
          .where(
            (p) => p.opacity > 0.01 && p.position.dy < screenSize.height + 100,
          )
          .toList();
    });
  }

  void _startVoid() {
    setState(() {
      _state = DustRitualState.voidState;
    });
  }

  void _onVoidComplete() {
    setState(() {
      _state = DustRitualState.complete;
    });
    // 少し待ってから完了コールバックを呼ぶ（未来への入力エリアを表示）
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && widget.onComplete != null) {
        widget.onComplete!(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final centerY = screenSize.height / 2;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Stack(
          children: [
            // 水平線（Sever Line）- 常に絶対的な境界として存在
            Positioned(
              left: 0,
              right: 0,
              top: centerY - 0.5,
              child: const SeverLine(thickness: 1.0, color: Colors.black),
            ),
            // 下側：塵（Dust）へと還る過去の領域
            Positioned(
              left: 0,
              right: 0,
              top: centerY,
              bottom: 0,
              child: _buildDustArea(centerY),
            ),
            // 上側：未来への干渉（Intervene）領域
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: centerY,
              child: _buildFutureArea(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDustArea(double centerY) {
    switch (_state) {
      case DustRitualState.input:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '今捨てたいしがらみ・言い訳',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w200,
                  letterSpacing: 1.5,
                  color: Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _dustInputController,
                focusNode: _dustInputFocusNode,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w200,
                  letterSpacing: 1.5,
                  color: Colors.black87,
                ),
                maxLines: null,
                decoration: const InputDecoration(
                  hintText: '...',
                  hintStyle: TextStyle(color: Colors.black26),
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(height: 32),
              TextButton(
                onPressed: _startDecomposition,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
                child: Text(
                  '送信',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w200,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
        );
      case DustRitualState.decomposing:
        return LayoutBuilder(
          builder: (context, constraints) {
            // テキストの位置を測定（入力時の位置を保持）
            if (_textRect == null && _dustInputController.text.isNotEmpty) {
              final textPainter = TextPainter(
                text: TextSpan(
                  text: _dustInputController.text,
                  style: TextStyle(
                    color: const Color(0xFF9CA3AF),
                    fontSize: 18,
                    fontWeight: FontWeight.w200,
                  ),
                ),
                textDirection: TextDirection.ltr,
              );
              textPainter.layout(maxWidth: constraints.maxWidth - 128);
              _textRect = Rect.fromLTWH(
                (constraints.maxWidth - textPainter.width) / 2,
                constraints.maxHeight * 0.3,
                textPainter.width,
                textPainter.height,
              );
            }

            return CustomPaint(
              painter: DustParticlePainter(particles: _particles),
              size: Size(constraints.maxWidth, constraints.maxHeight),
            );
          },
        );
      case DustRitualState.voidState:
        return AbsorbPointer(child: SilentVoid(onComplete: _onVoidComplete));
      case DustRitualState.complete:
        return const SizedBox.expand();
    }
  }

  Widget _buildFutureArea() {
    if (_state == DustRitualState.complete) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '未来の私へ',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w100,
                letterSpacing: 2.0,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            // ここに未来への入力エリアを追加（NowSheetの既存実装と統合）
            Text(
              '期待を書き込む',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w200,
                letterSpacing: 1.5,
                color: Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return const SizedBox.expand();
  }
}
