import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/firebase_service.dart';
import '../../core/crash_logger.dart';
import '../../core/models/capsule_model.dart';
import '../../core/models/user_model.dart';
import '../sealed/seal_completed_page.dart';
import '../../core/time.dart';
// Silent void removed; ritual now transitions to the vault screen.

/// 純化されたNowSheet：水平線ベースのシンプルな実装
/// 唯一の機能：今書いたものを、未来の自分が読む
class SimpleNowSheet extends ConsumerStatefulWidget {
  const SimpleNowSheet({super.key});

  @override
  ConsumerState<SimpleNowSheet> createState() => _SimpleNowSheetState();
}

enum SimpleNowSheetState {
  input, // 入力中
  animating, // 封印アニメーション中
}

class _SimpleNowSheetState extends ConsumerState<SimpleNowSheet>
    with SingleTickerProviderStateMixin {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _textFieldKey = GlobalKey();
  final _sendButtonKey = GlobalKey();
  late final AnimationController _inkController;
  bool _isSubmitting = false;
  DateTime _selectedDate = TimeUtils.addDays(TimeUtils.today(), 7);
  SimpleNowSheetState _state = SimpleNowSheetState.input;
  DateTime? _sealedAt;
  Offset? _inkCenter;
  final List<_InkParticle> _inkParticles = [];
  final List<_InkMotion> _inkMotion = [];
  Duration _lastInkTick = Duration.zero;
  Size? _inkSize;
  bool _inkBurstStarted = false;
  bool _submitLocked = false;

  @override
  void initState() {
    super.initState();
    _inkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _inkController.addListener(_onInkTick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _inkController.removeListener(_onInkTick);
    _textController.dispose();
    _focusNode.dispose();
    _inkController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final today = TimeUtils.today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: today,
      lastDate: DateTime(today.year + 10, 12, 31),
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _handleSubmit() async {
    final rawText = _textController.text;
    final text = rawText.trim();
    final submitId = DateTime.now().microsecondsSinceEpoch;
    if (_submitLocked) {
      CrashLogger.logDebug(
        '[SimpleNowSheet] submit:blocked id=$submitId reason=locked',
      );
      return;
    }
    _submitLocked = true;
    CrashLogger.logDebug(
      '[SimpleNowSheet] submit:start id=$submitId rawLen=${rawText.length} trimmedLen=${text.length} state=$_state submitting=$_isSubmitting',
    );
    if (_isSubmitting) {
      _submitLocked = false;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('送信中です。しばらくお待ちください。')));
      CrashLogger.logDebug(
        '[SimpleNowSheet] submit:blocked id=$submitId reason=isSubmitting',
      );
      return;
    }
    if (_state != SimpleNowSheetState.input) {
      _submitLocked = false;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('処理中のため送信できません。')));
      CrashLogger.logDebug(
        '[SimpleNowSheet] submit:blocked id=$submitId reason=state=$_state',
      );
      return;
    }
    if (text.isEmpty) {
      _submitLocked = false;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('メッセージを入力してください')));
      CrashLogger.logDebug(
        '[SimpleNowSheet] submit:blocked id=$submitId reason=empty',
      );
      return;
    }
    // 封印アニメーションと送信処理を並行開始
    setState(() {
      _isSubmitting = true;
      _state = SimpleNowSheetState.animating;
    });
    _startInkOverlay();
    final animationFuture = _inkController.forward(from: 0.0);

    bool success = false;
    Object? failure;
    try {
      CrashLogger.logDebug('[SimpleNowSheet] submit:request id=$submitId');
      await _sendCapsule(text).timeout(const Duration(seconds: 10));
      success = true;
      CrashLogger.logDebug('[SimpleNowSheet] submit:success id=$submitId');
    } on TimeoutException catch (e, stack) {
      failure = e;
      await CrashLogger.logException(
        e,
        stack,
        context: '[SimpleNowSheet] submit timeout id=$submitId',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('送信がタイムアウトしました。通信状態を確認してください。')),
        );
      }
    } catch (e, stack) {
      failure = e;
      await CrashLogger.logException(
        e,
        stack,
        context: '[SimpleNowSheet] submit failure id=$submitId',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存に失敗しました。通信状態を確認してください。')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      } else {
        _isSubmitting = false;
      }
      CrashLogger.logDebug('[SimpleNowSheet] submit:end id=$submitId');
    }

    if (!mounted) return;
    if (success) {
      await animationFuture;
      await _openSealCompleted();
      return;
    }

    await _dismissInkOverlay(failure: failure);
  }

  void _resetForNewEntry() {
    _textController.clear();
    _isSubmitting = false;
    _state = SimpleNowSheetState.input;
    _sealedAt = null;
    _selectedDate = TimeUtils.addDays(TimeUtils.today(), 7);
    _inkCenter = null;
    _inkParticles.clear();
    _inkMotion.clear();
    _inkBurstStarted = false;
    _submitLocked = false;
    _submitLocked = false;
  }

  Future<void> _sendCapsule(String text) async {
    final firebase = FirebaseService.instance;
    var user = firebase.currentUser;
    if (user == null) {
      user = await firebase.signInAnonymously();
    }

    final userModel = UserModel(
      uid: user.uid,
      fcmToken: null,
      isPremium: false,
    );
    await firebase.upsertUser(userModel);

    final now = DateTime.now();
    _sealedAt = now;
    final capsule = CapsuleModel(
      userId: user.uid,
      content: text,
      sealedAt: now,
      unlockAt: _selectedDate,
      isOpened: false,
    );
    await firebase.createCapsule(capsule);
  }

  void _startInkOverlay() {
    if (_inkBurstStarted) return;
    _inkBurstStarted = true;
    _inkCenter = _resolveInkCenter();
    _inkParticles
      ..clear()
      ..addAll(_generateInkParticles());
    _inkMotion
      ..clear()
      ..addAll(
        List.generate(
          _inkParticles.length,
          (_) =>
              _InkMotion(_inkCenter ?? Offset.zero, Offset.zero, PinkNoise1D()),
        ),
      );
    _lastInkTick = Duration.zero;
  }

  Future<void> _dismissInkOverlay({Object? failure}) async {
    if (_inkController.isAnimating) {
      _inkController.stop();
    }
    await _inkController.animateBack(
      0.0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
    if (!mounted) return;
    setState(() {
      _state = SimpleNowSheetState.input;
      _inkCenter = null;
    });
    _inkParticles.clear();
    _inkMotion.clear();
    _inkBurstStarted = false;
    if (failure != null) {
      CrashLogger.logDebug(
        '[SimpleNowSheet] submit:overlay dismissed failure=$failure',
      );
    }
  }

  Future<void> _openSealCompleted() async {
    if (!mounted) return;
    final sealedAt = _sealedAt ?? DateTime.now();
    final result = await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, animation, __) {
          return FadeTransition(
            opacity: animation,
            child: SealCompletedPage(
              sealedAt: sealedAt,
              unlockAt: _selectedDate,
            ),
          );
        },
      ),
    );
    if (!mounted) return;
    setState(() {
      _resetForNewEntry();
    });
    if (result == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  Offset _resolveInkCenter() {
    final ctx = _sendButtonKey.currentContext;
    if (ctx != null) {
      final box = ctx.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        final topLeft = box.localToGlobal(Offset.zero);
        return topLeft + Offset(box.size.width / 2, box.size.height / 2);
      }
    }
    final size = MediaQuery.of(context).size;
    return Offset(size.width / 2, size.height / 2);
  }

  List<_InkParticle> _generateInkParticles() {
    final rand = math.Random();
    final count = 200 + rand.nextInt(50);
    return List.generate(count, (index) {
      final layerRoll = rand.nextDouble();
      final isThread = layerRoll > 0.8;
      final jitter = (rand.nextDouble() * 2 - 1) * (math.pi / 180) * 1.5;
      final angle = (math.pi * 2) * (index / count) + jitter;
      final radiusFactor = 0.55 + rand.nextDouble() * 0.35;
      final radialBias = (rand.nextDouble() * 2 - 1) * 0.30;
      final drift = isThread
          ? 6.0 + rand.nextDouble() * 5.0
          : 4.0 + rand.nextDouble() * 4.0;
      final size = isThread
          ? 1.4 + rand.nextDouble() * 1.0
          : 1.1 + rand.nextDouble() * 0.8;
      final phase = rand.nextDouble() * math.pi * 2;
      final freq = 0.7 + rand.nextDouble() * 0.4;
      final tOffset = ((rand.nextDouble() * 2 - 1) * 0.08) / 2.6;
      final speed = isThread
          ? 0.95 + rand.nextDouble() * 0.15
          : 0.75 + rand.nextDouble() * 0.12;
      final baseAlpha = isThread
          ? 0.26 + rand.nextDouble() * 0.10
          : 0.20 + rand.nextDouble() * 0.08;
      return _InkParticle(
        angle: angle,
        radiusFactor: radiusFactor,
        radialBias: radialBias,
        drift: drift,
        size: size,
        phase: phase,
        freq: freq,
        tOffset: tOffset,
        speed: speed,
        isThread: isThread,
        baseAlpha: baseAlpha,
      );
    });
  }

  double _softsign(double x) {
    return x / (1 + x.abs());
  }

  void _onInkTick() {
    if (_state != SimpleNowSheetState.animating ||
        _inkCenter == null ||
        _inkSize == null ||
        _inkParticles.isEmpty ||
        _inkMotion.length != _inkParticles.length) {
      _lastInkTick = _inkController.lastElapsedDuration ?? Duration.zero;
      return;
    }

    final elapsed = _inkController.lastElapsedDuration ?? Duration.zero;
    final delta = elapsed - _lastInkTick;
    _lastInkTick = elapsed;
    final dt = delta.inMicroseconds / 1000000.0;
    if (dt <= 0) return;

    final t = _inkController.value.clamp(0.0, 1.0);
    final halfDiagonal =
        math.sqrt(
          _inkSize!.width * _inkSize!.width +
              _inkSize!.height * _inkSize!.height,
        ) *
        0.5;
    final maxRadius = halfDiagonal * 0.98;
    final noiseGate = 0.5;
    const baseWobAmp = 0.015;
    const outSpeedUp = 1.2;
    const outEnd = 0.48;
    const blendWindow = 0.06;
    final isExpanding = t <= outEnd;
    final absorbT = ((t - outEnd) / (1.0 - outEnd)).clamp(0.0, 1.0);
    final absorbEase = Curves.easeInOutSine.transform(absorbT);
    for (int i = 0; i < _inkParticles.length; i++) {
      final blob = _inkParticles[i];
      final motion = _inkMotion[i];

      if (isExpanding) {
        final angleNoise = _softsign(motion.noise.next());
        motion.angleVel = (motion.angleVel * 0.88) + angleNoise * 0.01;
        motion.angle = motion.angle + motion.angleVel * dt;
      } else {
        motion.angleVel = 0.0;
      }

      final radial = Offset(
        math.cos(blob.angle + motion.angle),
        math.sin(blob.angle + motion.angle),
      );
      final burstT = (t / (outEnd / outSpeedUp)).clamp(0.0, 1.0);
      // 拡散の終端で速度が0になるカーブ
      final expandEase = Curves.easeOutCubic.transform(burstT);
      final blendT = ((t - outEnd) / blendWindow).clamp(0.0, 1.0);
      final expandFactor = expandEase * (1.0 - blendT);
      final absorbFactor = (1.0 - absorbEase).clamp(0.0, 1.0) * blendT;
      final rFactor = expandFactor + absorbFactor;
      final wobAmp = baseWobAmp * (1.0 - blendT);
      final noise = _softsign(motion.noise.next()) * (1.0 - blendT);
      final distAtten =
          ((motion.position - _inkCenter!).distance / (maxRadius * 0.18)).clamp(
            0.0,
            1.0,
          );
      final noiseBias = noise * wobAmp * noiseGate * distAtten;
      final radius =
          maxRadius *
          blob.radiusFactor *
          rFactor *
          (1 + blob.radialBias + noiseBias);
      final nextPos = _inkCenter! + radial * radius;
      final prevPos = motion.position;
      motion.position = nextPos;
      if (dt > 0) {
        motion.velocity = (nextPos - prevPos) / dt;
      } else {
        motion.velocity = Offset.zero;
      }
    }

    // Repaint is driven by _inkController; avoid setState for performance.
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    _inkSize = screenSize;
    final centerY = screenSize.height / 2;
    final canSubmit =
        _textController.text.trim().isNotEmpty &&
        !_isSubmitting &&
        _state == SimpleNowSheetState.input;

    return Scaffold(
      backgroundColor: Colors.black, // 深淵への回帰：完全な黒
      body: SafeArea(
        child: Stack(
          children: [
            AbsorbPointer(
              absorbing:
                  _isSubmitting || _state == SimpleNowSheetState.animating,
              child: Stack(
                children: [
                  // 上側：未来への干渉（Intervene）領域
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    bottom: centerY,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 64,
                        vertical: 48,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '未来の私へ。',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w100,
                                  letterSpacing: 2.0,
                                  height: 1.8,
                                  color: Colors.white,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 48),
                          Expanded(
                            child: Container(
                              key: _textFieldKey,
                              child: TextField(
                                controller: _textController,
                                focusNode: _focusNode,
                                autofocus: true,
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w200,
                                      letterSpacing: 1.5,
                                      height: 1.8,
                                      color: Colors.white,
                                    ),
                                maxLines: null,
                                expands: true,
                                textAlign: TextAlign.center,
                                textAlignVertical: TextAlignVertical.top,
                                decoration: const InputDecoration(
                                  hintText: '...',
                                  hintStyle: TextStyle(color: Colors.white30),
                                  border: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          InkWell(
                            onTap: () => _selectDate(context),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                FormatUtils.formatDate(_selectedDate),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w200,
                                      letterSpacing: 1.5,
                                      color: Colors.white70,
                                    ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              key: _sendButtonKey,
                              onPressed: () {
                                FocusScope.of(context).unfocus();
                                _handleSubmit();
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                              child: Text(
                                '封印する',
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w200,
                                      letterSpacing: 1.5,
                                      color: canSubmit
                                          ? Colors.white
                                          : Colors.white60,
                                    ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: centerY,
                    bottom: 0,
                    child: const SizedBox.expand(),
                  ),
                ],
              ),
            ),
            if (_state == SimpleNowSheetState.animating)
              Positioned.fill(
                child: InkSealOverlay(
                  animation: _inkController,
                  center:
                      _inkCenter ??
                      Offset(screenSize.width / 2, screenSize.height / 2),
                  particles: _inkParticles,
                  motions: _inkMotion,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class InkSealOverlay extends StatelessWidget {
  final Animation<double> animation;
  final Offset center;
  final List<_InkParticle> particles;
  final List<_InkMotion> motions;

  const InkSealOverlay({
    super.key,
    required this.animation,
    required this.center,
    required this.particles,
    required this.motions,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final fade = Curves.easeInOut.transform(
            animation.value.clamp(0.0, 1.0),
          );
          return Stack(
            children: [
              Positioned.fill(
                child: Container(
                  color: scheme.surface.withOpacity(0.18 + 0.22 * fade),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _InkSealPainter(
                    progress: animation.value,
                    center: center,
                    particles: particles,
                    motions: motions,
                    inkColor: scheme.onSurface,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InkParticle {
  final double angle;
  final double radiusFactor;
  final double radialBias;
  final double drift;
  final double size;
  final double phase;
  final double freq;
  final double tOffset;
  final double speed;
  final bool isThread;
  final double baseAlpha;

  const _InkParticle({
    required this.angle,
    required this.radiusFactor,
    required this.radialBias,
    required this.drift,
    required this.size,
    required this.phase,
    required this.freq,
    required this.tOffset,
    required this.speed,
    required this.isThread,
    required this.baseAlpha,
  });
}

class _InkMotion {
  Offset position;
  Offset velocity;
  final PinkNoise1D noise;
  double angle;
  double angleVel;

  _InkMotion(this.position, this.velocity, this.noise)
    : angle = 0.0,
      angleVel = 0.0;
}

class PinkNoise1D {
  double _b0 = 0.0;
  double _b1 = 0.0;
  double _b2 = 0.0;
  double _b3 = 0.0;
  double _b4 = 0.0;
  double _b5 = 0.0;
  double _b6 = 0.0;
  final math.Random _rand = math.Random();

  double next() {
    final white = _rand.nextDouble() * 2.0 - 1.0;
    _b0 = 0.99886 * _b0 + white * 0.0555179;
    _b1 = 0.99332 * _b1 + white * 0.0750759;
    _b2 = 0.96900 * _b2 + white * 0.1538520;
    _b3 = 0.86650 * _b3 + white * 0.3104856;
    _b4 = 0.55000 * _b4 + white * 0.5329522;
    _b5 = -0.7616 * _b5 - white * 0.0168980;
    final pink = _b0 + _b1 + _b2 + _b3 + _b4 + _b5 + _b6 + white * 0.5362;
    _b6 = white * 0.115926;
    return pink * 0.1;
  }
}

class _InkSealPainter extends CustomPainter {
  final double progress;
  final Offset center;
  final List<_InkParticle> particles;
  final List<_InkMotion> motions;
  final Color inkColor;

  const _InkSealPainter({
    required this.progress,
    required this.center,
    required this.particles,
    required this.motions,
    required this.inkColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final maxRadius = math.min(size.width, size.height) * 0.32;
    final fade =
        1.0 - ((progress.clamp(0.0, 1.0) - 0.55) / 0.45).clamp(0.0, 1.0);
    const converge = 0.0;
    final dustPaint = Paint()
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.srcOver;
    final trailPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.srcOver;
    final threadPaint = Paint()
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.srcOver
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.4);
    const mergeRadius = 10.0;

    for (int i = 0; i < particles.length; i++) {
      final blob = particles[i];
      final motion = i < motions.length
          ? motions[i]
          : _InkMotion(center, Offset.zero, PinkNoise1D());
      final dotSize = blob.size.clamp(0.9, 6.0);
      final pos = motion.position;

      final velocity = motion.velocity;
      final speed = velocity.distance;
      final distanceFactor = (pos - center).distance / maxRadius;
      final clampedDistance = distanceFactor.clamp(0.0, 1.0);
      final outerFade = 1.0 - converge * (0.6 + 0.4 * clampedDistance);
      final innerBoost = 1.0 + (1.0 - clampedDistance) * converge * 0.25;
      final centerBoost = 1.0 + (1.0 - clampedDistance) * 0.28;
      final alpha = (blob.baseAlpha * outerFade * innerBoost * centerBoost)
          .clamp(0.22, 0.55);
      final mergeFade = ((distanceFactor - (mergeRadius / maxRadius)) / 0.15)
          .clamp(0.0, 1.0);
      final particleAlpha = alpha * mergeFade * fade;

      if (blob.isThread && speed > 6.0 && (i % 2 == 0)) {
        final dir = velocity / speed;
        final trailLen = (speed * 0.02).clamp(2.0, 10.0);
        trailPaint
          ..strokeWidth = (dotSize * 0.45).clamp(0.4, 1.2)
          ..color = inkColor.withOpacity(
            (particleAlpha * 0.5).clamp(0.0, 0.18),
          );
        canvas.drawLine(pos, pos - dir * trailLen, trailPaint);
      }

      if (blob.isThread) {
        final stretch = (1.3 + blob.speed * 0.4).clamp(1.3, 1.8);
        final ovalRect = Rect.fromCenter(
          center: pos,
          width: dotSize * 2.0 * stretch,
          height: dotSize * 2.0,
        );
        threadPaint.color = inkColor.withOpacity(
          particleAlpha.clamp(0.0, 0.55),
        );
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(math.atan2(velocity.dy, velocity.dx));
        canvas.translate(-pos.dx, -pos.dy);
        canvas.drawOval(ovalRect, threadPaint);
        threadPaint.color = inkColor.withOpacity(
          (particleAlpha * 0.55).clamp(0.0, 0.35),
        );
        canvas.drawOval(ovalRect, threadPaint);
        canvas.restore();
      } else {
        dustPaint.color = inkColor.withOpacity(particleAlpha.clamp(0.0, 0.45));
        canvas.drawCircle(pos, dotSize, dustPaint);
        dustPaint.color = inkColor.withOpacity(
          (particleAlpha * 0.6).clamp(0.0, 0.34),
        );
        canvas.drawCircle(pos, dotSize, dustPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _InkSealPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.center != center ||
        oldDelegate.particles != particles ||
        oldDelegate.motions != motions ||
        oldDelegate.inkColor != inkColor;
  }
}
