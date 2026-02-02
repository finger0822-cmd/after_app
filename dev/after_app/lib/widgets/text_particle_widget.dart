import 'package:flutter/material.dart';
import '../core/particles/particle.dart';
import '../core/particles/particle_painter.dart';
import '../core/particles/text_particle_effect.dart';

class TextParticleWidget extends StatefulWidget {
  final String text;
  final VoidCallback onCompleted;
  final ValueNotifier<double>? progress;

  const TextParticleWidget({
    super.key,
    required this.text,
    required this.onCompleted,
    this.progress,
  });

  @override
  State<TextParticleWidget> createState() => _TextParticleWidgetState();
}

class _TextParticleWidgetState extends State<TextParticleWidget>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _controller;
  final List<Particle> _particles = [];
  bool _initialized = false;
  Duration _lastElapsed = Duration.zero;
  int _updateOffset = 0;
  Duration _lastLogElapsed = Duration.zero;
  int _frameCounter = 0;
  bool _didLogSeed = false;
  Size _screenSize = Size.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _screenSize = MediaQuery.of(context).size;
      if (!_initialized) {
        _initParticles();
      }
    });
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..addListener(_tick);

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onCompleted();
      }
    });
  }

  Future<void> _initParticles() async {
    final size = MediaQuery.of(context).size;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.4),
      width: size.width * 0.6,
      height: 120,
    );
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final textLen = widget.text.trim().length;
    double factor = 1.0;
    if (textLen > 20) factor *= 0.85;
    if (textLen > 40) factor *= 0.7;
    if (dpr > 1.25) factor *= 0.85;
    if (dpr > 1.5) factor *= 0.75;
    final particleCount = (3200 * factor).round().clamp(1500, 4000);

    final sw = Stopwatch()..start();
    debugPrint('TextParticles START textLen=${widget.text.length}');
    final points = await rasterizeTextToPoints(
      text: widget.text,
      textRect: rect,
      devicePixelRatio: dpr,
      particleCount: particleCount,
    );
    sw.stop();
    debugPrint(
      'TextParticles END elapsedMs=${sw.elapsedMilliseconds} points=${points.length}',
    );

    _particles.addAll(points);
    _initialized = true;
    _lastElapsed = Duration.zero;
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _lastElapsed = Duration.zero;
        _controller.forward(from: 0.0);
      });
    }
  }

  void _tick() {
    if (!_initialized) return;
    final elapsed = _controller.lastElapsedDuration ?? Duration.zero;
    var dt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    if (dt <= 0) {
      dt = 1.0 / 60.0;
    } else if (dt < 1.0 / 120.0) {
      dt = 1.0 / 120.0;
    } else if (dt > 1.0 / 30.0) {
      dt = 1.0 / 30.0;
    }
    _lastElapsed = elapsed;
    const durationSec = 4.0;
    final tSec = elapsed.inMicroseconds / 1000000.0;
    final progress = (tSec / durationSec).clamp(0.0, 1.0);
    widget.progress?.value = progress;

    final size = _screenSize;
    final step = 1;
    for (int i = _updateOffset; i < _particles.length; i += step) {
      _particles[i].update(dt, tSec, size);
    }
    _particles.removeWhere((p) => !p.alive || p.opacity <= 0.0);
    if (elapsed - _lastLogElapsed >= const Duration(seconds: 1)) {
      _lastLogElapsed = elapsed;
      debugPrint(
        'TextParticles TICK tSec=${tSec.toStringAsFixed(3)} '
        'anim=${_controller.isAnimating} status=${_controller.status} '
        'dt=${dt.toStringAsFixed(4)}',
      );
    }
    _frameCounter++;
    if ((_frameCounter % 30) == 0) {
      double sum = 0.0;
      int count = 0;
      final center = Offset(_screenSize.width / 2, _screenSize.height / 2);
      for (final p in _particles) {
        if (!p.alive) continue;
        sum += (p.position - center).distance;
        count++;
      }
      final meanR = count == 0 ? 0.0 : sum / count;
      debugPrint(
        'TextParticles meanR=${meanR.toStringAsFixed(1)} '
        't=${tSec.toStringAsFixed(3)}',
      );
    }
    if (!_didLogSeed && _particles.isNotEmpty) {
      _didLogSeed = true;
      final center = Offset(_screenSize.width / 2, _screenSize.height / 2);
      double sumSpeed = 0.0;
      int count = 0;
      for (final p in _particles) {
        sumSpeed += p.velocity.distance;
        count++;
      }
      final meanV = count == 0 ? 0.0 : sumSpeed / count;
      debugPrint(
        'TextParticles init meanV=${meanV.toStringAsFixed(1)} center=$center',
      );
    }
    _updateOffset = (_updateOffset + 1) % step;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screenSize = MediaQuery.of(context).size;
  }

  @override
  void didUpdateWidget(covariant TextParticleWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller.stop();
      _controller.reset();
      _lastElapsed = Duration.zero;
      _particles.clear();
      _initialized = false;
      _initParticles();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: ParticlePainter(_particles, repaint: _controller),
      size: Size.infinite,
    );
  }

  @override
  void dispose() {
    debugPrint('TextParticles dispose anim=${_controller.isAnimating}');
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }
}
