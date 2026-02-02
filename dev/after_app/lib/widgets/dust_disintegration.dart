import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/dust_particle.dart';
import '../core/dust_particle_helpers.dart' as dust_helpers;

class DustDisintegration extends StatefulWidget {
  final Offset origin;
  final VoidCallback onCompleted;
  final ValueNotifier<double>? progress;
  final String? text;
  final Rect? textRect;
  final int particleCount;

  const DustDisintegration({
    super.key,
    required this.origin,
    required this.onCompleted,
    this.progress,
    this.text,
    this.textRect,
    this.particleCount = 12000,
  });

  @override
  State<DustDisintegration> createState() => _DustDisintegrationState();
}

class _DustDisintegrationState extends State<DustDisintegration>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<DustParticle> _particles = [];
  bool _didComplete = false;
  bool _didInitParticles = false;
  Duration _lastElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );

    _controller.addListener(() {
      final size = MediaQuery.of(context).size;
      widget.progress?.value = _controller.value;
      final elapsed = _controller.lastElapsedDuration ?? Duration.zero;
      var dt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
      if (dt <= 0) {
        dt = 1.0 / 60.0;
      } else if (dt > 1.0 / 30.0) {
        dt = 1.0 / 30.0;
      }
      _lastElapsed = elapsed;
      for (var p in _particles) {
        p.update(_controller.value, dt, size);
      }
      // 描写の確実性を優先し、途中終了は行わない
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_didComplete) {
        _didComplete = true;
        widget.onCompleted();
      }
    });

  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitParticles) return;
    _didInitParticles = true;
    _initParticles();
  }

  Future<void> _initParticles() async {
    final text = widget.text?.trim() ?? '';
    final textRect = widget.textRect;
    if (text.isNotEmpty &&
        textRect != null &&
        textRect.width > 1 &&
        textRect.height > 1) {
      final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
      final generated =
          await dust_helpers.DustParticleGenerator.generateFromTextRaster(
        text: text,
        textRect: textRect,
        textColor: Colors.white,
        particleCount: widget.particleCount,
        devicePixelRatio: devicePixelRatio,
      );
      if (generated.isNotEmpty) {
        _particles.addAll(generated);
      }
    }

    if (_particles.isEmpty) {
      final rand = math.Random();
      final gridSize = math.sqrt(widget.particleCount).ceil();
      const double spacing = 1.2; // きめ細かい密度
      for (int i = 0; i < widget.particleCount; i++) {
        final col = i % gridSize;
        final row = i ~/ gridSize;
        final baseOffset = Offset(
          (col - gridSize / 2) * spacing,
          (row - gridSize / 2) * spacing,
        );
        final jitter = Offset(
          (rand.nextDouble() - 0.5) * spacing,
          (rand.nextDouble() - 0.5) * spacing,
        );
        final angle = rand.nextDouble() * 2 * math.pi;
        final speed =
            (rand.nextDouble() * rand.nextDouble()) * 750.0; // 0.0-750.0

        _particles.add(
          DustParticle(
            position: widget.origin + baseOffset + jitter,
            velocity: Offset(
              math.cos(angle) * speed * 0.1,
              math.sin(angle) * speed * 0.1,
            ),
            size: (0.06 + rand.nextDouble() * 0.35) * 2.2, // 0.13-0.9
            noiseOffset: rand.nextDouble() * 10000,
          ),
        );
      }
    }

    if (mounted && !_controller.isAnimating) {
      _lastElapsed = Duration.zero;
      _controller.forward();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        size: Size.infinite,
        painter: DustParticlePainter(
          particles: _particles,
          progress: _controller.value,
          repaint: _controller,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class DustParticlePainter extends CustomPainter {
  final List<DustParticle> particles;
  final double progress;
  DustParticlePainter({
    required this.particles,
    required this.progress,
    Listenable? repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..isAntiAlias = true
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    final center = size.center(Offset.zero);
    final holePaint = Paint()
      ..color = Colors.black
      ..isAntiAlias = true;
    // 中央の小さなブラックホール
    canvas.drawCircle(center, 5.0, holePaint);
    canvas.drawCircle(
      center,
      9.0,
      holePaint..color = Colors.black.withOpacity(0.35),
    );

    for (var p in particles) {
      if (p.opacity <= 0) continue;
      final radius = p.size * p.opacity;
      paint.color = Colors.white.withOpacity(p.opacity);
      canvas.drawCircle(p.position, radius, paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter old) => true;
}
