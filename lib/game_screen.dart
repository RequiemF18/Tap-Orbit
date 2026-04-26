import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_over.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  static const int maxLives = 3;
  static const int maxPlanets = 4;
  static const double gateAngle = -pi / 2;
  static const double hitWindow = 0.36;
  static const double perfectWindow = 0.14;

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  Size _screenSize = Size.zero;

  final List<OrbitPlanet> _planets = [];
  final List<HitParticle> _particles = [];
  final List<TapRipple> _ripples = [];

  int _score = 0;
  int _lives = maxLives;
  int _hitStreak = 0;
  int _bestCombo = 0;
  int _personalBest = 0;
  int _totalHits = 0;
  int _targetIndex = 0;

  double _flashOpacity = 0;
  Color _flashColor = Colors.white;
  double _comboPulse = 0;
  double _gatePulse = 0;
  double _hintOpacity = 1;
  double _feedbackAge = 2;
  String _feedbackText = '';
  Color _feedbackColor = Colors.white;
  bool _gameEnded = false;

  final List<Color> _planetColors = const [
    Color(0xFF00E5FF),
    Color(0xFFFF2BD6),
    Color(0xFFB6FF00),
    Color(0xFFFFB300),
  ];

  @override
  void initState() {
    super.initState();
    _loadBest();
    _resetGame();
    _ticker = createTicker(_tick)..start();
  }

  Future<void> _loadBest() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _personalBest = prefs.getInt('tap_orbit_best_score') ?? 0);
  }

  void _resetGame() {
    _planets.clear();
    _particles.clear();
    _ripples.clear();
    _score = 0;
    _lives = maxLives;
    _hitStreak = 0;
    _bestCombo = 0;
    _totalHits = 0;
    _targetIndex = 0;
    _flashOpacity = 0;
    _comboPulse = 0;
    _gatePulse = 0;
    _hintOpacity = 1;
    _feedbackAge = 2;
    _feedbackText = '';
    _gameEnded = false;
    _addPlanet();
  }

  void _addPlanet() {
    if (_planets.length >= maxPlanets) return;
    final index = _planets.length;
    final direction = index.isEven ? 1.0 : -1.0;
    _planets.add(
      OrbitPlanet(
        color: _planetColors[index],
        angle: pi / 2 + index * 0.75,
        speed: direction * (0.95 + index * 0.18),
        index: index,
      ),
    );
  }

  void _tick(Duration elapsed) {
    if (_gameEnded) return;
    final dt = _lastElapsed == Duration.zero ? 0.0 : (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.05) return;

    setState(() {
      _updatePlanets(dt);
      _updateParticles(dt);
      _updateRipples(dt);
      _flashOpacity = max(0, _flashOpacity - dt / 0.2);
      _comboPulse = max(0, _comboPulse - dt / 0.28);
      _gatePulse = max(0, _gatePulse - dt / 0.22);
      _feedbackAge += dt;
      if (_totalHits > 0 || _lives < maxLives) {
        _hintOpacity = max(0, _hintOpacity - dt / 1.3);
      }
    });
  }

  void _updatePlanets(double dt) {
    for (final planet in _planets) {
      planet.angle += planet.speed * dt;
      if (_screenSize != Size.zero) {
        final center = _screenSize.center(Offset.zero);
        final radius = _orbitRadiusFor(planet.index, _screenSize);
        final position = Offset(center.dx + cos(planet.angle) * radius, center.dy + sin(planet.angle) * radius);
        planet.trail.add(position);
        if (planet.trail.length > 8) planet.trail.removeAt(0);
      }
    }
  }

  void _updateParticles(double dt) {
    final dead = <HitParticle>[];
    for (final particle in _particles) {
      particle.age += dt;
      particle.position += particle.velocity * dt;
      if (particle.age >= particle.duration) dead.add(particle);
    }
    _particles.removeWhere(dead.contains);
  }

  void _updateRipples(double dt) {
    final dead = <TapRipple>[];
    for (final ripple in _ripples) {
      ripple.age += dt;
      if (ripple.age >= ripple.duration) dead.add(ripple);
    }
    _ripples.removeWhere(dead.contains);
  }

  void _onTap() {
    if (_gameEnded || _screenSize == Size.zero || _planets.isEmpty) return;

    final target = _planets[_targetIndex.clamp(0, _planets.length - 1)];
    final distance = _angleDistance(target.angle, gateAngle);
    final center = _screenSize.center(Offset.zero);
    final radius = _orbitRadiusFor(target.index, _screenSize);
    final gatePosition = Offset(center.dx + cos(gateAngle) * radius, center.dy + sin(gateAngle) * radius);

    _ripples.add(TapRipple(color: target.color, radius: radius));
    _gatePulse = 1;

    if (distance <= hitWindow) {
      _handleHit(target, distance <= perfectWindow, gatePosition);
    } else {
      final signed = _signedAngleDifference(target.angle, gateAngle);
      _handleMiss(signed < 0 ? 'TOO EARLY' : 'TOO LATE', target.color);
    }
  }

  void _handleHit(OrbitPlanet planet, bool perfect, Offset impact) {
    _totalHits++;
    _hitStreak++;
    _bestCombo = max(_bestCombo, _hitStreak);
    final comboBonus = _hitStreak >= 3 ? 2 : 1;
    _score += perfect ? comboBonus + 1 : comboBonus;

    _flashColor = Colors.white;
    _flashOpacity = perfect ? 0.38 : 0.26;
    _feedbackText = perfect ? 'PERFECT' : 'NICE';
    _feedbackColor = planet.color;
    _feedbackAge = 0;
    if (_hitStreak == 3 || _hitStreak % 5 == 0 || perfect) _comboPulse = 1.0;
    _spawnBurst(impact, planet.color, perfect ? 18 : 12);

    if (_totalHits % 3 == 0) {
      for (final p in _planets) {
        p.speed *= 1.10;
      }
    }
    if (_totalHits % 5 == 0 && _planets.length < maxPlanets) _addPlanet();

    _targetIndex++;
    if (_targetIndex >= _planets.length) _targetIndex = 0;
  }

  void _handleMiss(String message, Color color) {
    _hitStreak = 0;
    _lives--;
    _flashColor = Colors.red;
    _flashOpacity = 0.4;
    _feedbackText = message;
    _feedbackColor = Colors.redAccent;
    _feedbackAge = 0;
    if (_screenSize != Size.zero) {
      final center = _screenSize.center(Offset.zero);
      _spawnBurst(center, color.withOpacity(0.7), 8);
    }
    if (_lives <= 0) _endGame();
  }

  Future<void> _endGame() async {
    if (_gameEnded) return;
    _gameEnded = true;
    _ticker.stop();
    final newBest = max(_personalBest, _score);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tap_orbit_best_score', newBest);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => GameOverScreen(finalScore: _score, bestCombo: _bestCombo, personalBest: newBest)),
    );
  }

  void _spawnBurst(Offset impact, Color color, int count) {
    for (int i = 0; i < count; i++) {
      final angle = (pi * 2 / count) * i;
      final double speed = 125.0 + (i % 4) * 34.0;
      _particles.add(HitParticle(position: impact, velocity: Offset(cos(angle), sin(angle)) * speed, color: color, duration: 0.42));
    }
  }

  double _orbitRadiusFor(int index, Size size) {
    final minSide = min(size.width, size.height);
    return minSide * 0.22 + minSide * 0.105 * index;
  }

  double _angleDistance(double a, double b) {
    var diff = (a - b).abs() % (pi * 2);
    if (diff > pi) diff = pi * 2 - diff;
    return diff;
  }

  double _signedAngleDifference(double angle, double target) {
    var diff = (angle - target) % (pi * 2);
    if (diff > pi) diff -= pi * 2;
    if (diff < -pi) diff += pi * 2;
    return diff;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final comboActive = _hitStreak >= 3;
    final comboScale = 1.0 + _comboPulse * 0.22;
    final feedbackVisible = _feedbackAge < 0.65;
    final activeColor = _planets.isEmpty ? Colors.cyanAccent : _planets[_targetIndex.clamp(0, _planets.length - 1)].color;

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          _screenSize = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _onTap(),
            child: Stack(
              children: [
                CustomPaint(
                  size: Size.infinite,
                  painter: TapOrbitPainter(
                    planets: _planets,
                    particles: _particles,
                    ripples: _ripples,
                    lives: _lives,
                    flashColor: _flashColor,
                    flashOpacity: _flashOpacity,
                    targetIndex: _targetIndex,
                    gateAngle: gateAngle,
                    hitWindow: hitWindow,
                    perfectWindow: perfectWindow,
                    gatePulse: _gatePulse,
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$_score',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 54,
                              fontWeight: FontWeight.w800,
                              height: 1,
                              shadows: [Shadow(color: Colors.white54, blurRadius: 16)],
                            ),
                          ),
                          const SizedBox(height: 8),
                          AnimatedOpacity(
                            opacity: comboActive ? 1 : 0,
                            duration: const Duration(milliseconds: 140),
                            child: Transform.scale(
                              scale: comboScale,
                              child: Text(
                                'COMBO x2  $_hitStreak',
                                style: TextStyle(
                                  color: activeColor,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2.4,
                                  shadows: [Shadow(color: activeColor, blurRadius: 18)],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 88, left: 28, right: 28),
                      child: AnimatedOpacity(
                        opacity: _hintOpacity,
                        duration: const Duration(milliseconds: 250),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'TAP WHEN THE PLANET ENTERS THE GATE',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: activeColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                                shadows: [Shadow(color: activeColor, blurRadius: 18)],
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Hit the glowing arc at the top',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: feedbackVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 80),
                      child: Transform.scale(
                        scale: 1.0 + (1.0 - _feedbackAge.clamp(0, 0.65) / 0.65) * 0.15,
                        child: Text(
                          _feedbackText,
                          style: TextStyle(
                            color: _feedbackColor,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.5,
                            shadows: [Shadow(color: _feedbackColor, blurRadius: 24)],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class TapOrbitPainter extends CustomPainter {
  TapOrbitPainter({
    required this.planets,
    required this.particles,
    required this.ripples,
    required this.lives,
    required this.flashColor,
    required this.flashOpacity,
    required this.targetIndex,
    required this.gateAngle,
    required this.hitWindow,
    required this.perfectWindow,
    required this.gatePulse,
  });

  final List<OrbitPlanet> planets;
  final List<HitParticle> particles;
  final List<TapRipple> ripples;
  final int lives;
  final Color flashColor;
  final double flashOpacity;
  final int targetIndex;
  final double gateAngle;
  final double hitWindow;
  final double perfectWindow;
  final double gatePulse;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    _paintOrbitsAndGates(canvas, size, center);
    _paintStar(canvas, center, size);
    _paintRipples(canvas, center);
    _paintPlanetTrails(canvas);
    _paintPlanets(canvas, size, center);
    _paintParticles(canvas);
    _paintLives(canvas, size);
    if (flashOpacity > 0) canvas.drawRect(Offset.zero & size, Paint()..color = flashColor.withOpacity(flashOpacity));
  }

  void _paintOrbitsAndGates(Canvas canvas, Size size, Offset center) {
    for (final planet in planets) {
      final active = planet.index == targetIndex;
      final radius = _orbitRadiusFor(planet.index, size);
      final color = planet.color;

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = active ? 1.5 : 0.8
          ..color = color.withOpacity(active ? 0.25 : 0.10),
      );

      if (active) {
        final rect = Rect.fromCircle(center: center, radius: radius);
        final pulse = 1.0 + gatePulse * 0.5;
        final gateGlow = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 18 * pulse
          ..color = color.withOpacity(0.16)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 18);
        final gate = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 8 * pulse
          ..color = color.withOpacity(0.95);
        final perfectGate = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 3
          ..color = Colors.white.withOpacity(0.9);

        canvas.drawArc(rect, gateAngle - hitWindow, hitWindow * 2, false, gateGlow);
        canvas.drawArc(rect, gateAngle - hitWindow, hitWindow * 2, false, gate);
        canvas.drawArc(rect, gateAngle - perfectWindow, perfectWindow * 2, false, perfectGate);

        final arrowTip = Offset(center.dx + cos(gateAngle) * (radius + 24), center.dy + sin(gateAngle) * (radius + 24));
        final left = Offset(center.dx + cos(gateAngle - 0.11) * (radius + 8), center.dy + sin(gateAngle - 0.11) * (radius + 8));
        final right = Offset(center.dx + cos(gateAngle + 0.11) * (radius + 8), center.dy + sin(gateAngle + 0.11) * (radius + 8));
        final path = Path()..moveTo(arrowTip.dx, arrowTip.dy)..lineTo(left.dx, left.dy)..lineTo(right.dx, right.dy)..close();
        canvas.drawPath(path, Paint()..color = color.withOpacity(0.9));
      }
    }
  }

  void _paintStar(Canvas canvas, Offset center, Size size) {
    final coreRadius = min(size.width, size.height) * 0.035;
    canvas.drawCircle(center, coreRadius * 3.4, Paint()..color = Colors.white.withOpacity(0.2)..maskFilter = const MaskFilter.blur(BlurStyle.outer, 36));
    canvas.drawCircle(center, coreRadius * 2.4, Paint()..color = const Color(0xFFFFF176).withOpacity(0.45)..maskFilter = const MaskFilter.blur(BlurStyle.outer, 26));
    canvas.drawCircle(center, coreRadius * 1.7, Paint()..color = const Color(0xFFFF8A00).withOpacity(0.55)..maskFilter = const MaskFilter.blur(BlurStyle.outer, 18));
    canvas.drawCircle(center, coreRadius, Paint()..shader = const RadialGradient(colors: [Colors.white, Color(0xFFFFF176), Color(0xFFFF9800)]).createShader(Rect.fromCircle(center: center, radius: coreRadius * 1.2)));
  }

  void _paintRipples(Canvas canvas, Offset center) {
    for (final ripple in ripples) {
      final t = (ripple.age / ripple.duration).clamp(0.0, 1.0);
      final opacity = 1.0 - t;
      canvas.drawCircle(
        center,
        lerpDouble(18, ripple.radius, t) ?? ripple.radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = lerpDouble(7, 2, t) ?? 2
          ..color = ripple.color.withOpacity(opacity * 0.75)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8),
      );
    }
  }

  void _paintPlanetTrails(Canvas canvas) {
    for (final planet in planets) {
      for (int i = 0; i < planet.trail.length; i++) {
        final t = planet.trail.length == 1 ? 1.0 : i / (planet.trail.length - 1);
        canvas.drawCircle(planet.trail[i], lerpDouble(2.2, 6.0, t) ?? 3, Paint()..color = planet.color.withOpacity((lerpDouble(0.1, 1.0, t) ?? 0.1) * 0.32));
      }
    }
  }

  void _paintPlanets(Canvas canvas, Size size, Offset center) {
    for (final planet in planets) {
      final active = planet.index == targetIndex;
      final orbitRadius = _orbitRadiusFor(planet.index, size);
      final position = Offset(center.dx + cos(planet.angle) * orbitRadius, center.dy + sin(planet.angle) * orbitRadius);
      final bodyRadius = active ? 8.0 : 6.2;
      canvas.drawCircle(position, active ? 20 : 14, Paint()..color = planet.color.withOpacity(active ? 0.30 : 0.18)..maskFilter = const MaskFilter.blur(BlurStyle.outer, 18));
      canvas.drawCircle(position, active ? 12 : 9, Paint()..color = planet.color.withOpacity(active ? 0.55 : 0.38)..maskFilter = const MaskFilter.blur(BlurStyle.outer, 10));
      canvas.drawCircle(position, bodyRadius, Paint()..color = planet.color);
      canvas.drawCircle(position + const Offset(-2.4, -2.4), 1.8, Paint()..color = Colors.white.withOpacity(0.82));
    }
  }

  void _paintParticles(Canvas canvas) {
    for (final particle in particles) {
      final t = (particle.age / particle.duration).clamp(0.0, 1.0);
      canvas.drawCircle(particle.position, lerpDouble(4.2, 1.0, t) ?? 2, Paint()..color = particle.color.withOpacity(1.0 - t)..maskFilter = const MaskFilter.blur(BlurStyle.outer, 5));
    }
  }

  void _paintLives(Canvas canvas, Size size) {
    final bottom = size.height - 42;
    final centerX = size.width / 2;
    for (int i = 0; i < 3; i++) {
      final active = i < lives;
      final position = Offset(centerX + (i - 1) * 26, bottom);
      canvas.drawCircle(position, 8, Paint()..color = Colors.white.withOpacity(active ? 0.42 : 0.08)..maskFilter = const MaskFilter.blur(BlurStyle.outer, 10));
      canvas.drawCircle(position, 4.8, Paint()..color = Colors.white.withOpacity(active ? 1.0 : 0.18));
    }
  }

  double _orbitRadiusFor(int index, Size size) => min(size.width, size.height) * 0.22 + min(size.width, size.height) * 0.105 * index;

  @override
  bool shouldRepaint(covariant TapOrbitPainter oldDelegate) => true;
}

class OrbitPlanet {
  OrbitPlanet({required this.color, required this.angle, required this.speed, required this.index});
  final Color color;
  double angle;
  double speed;
  final int index;
  final List<Offset> trail = [];
}

class TapRipple {
  TapRipple({required this.color, required this.radius});
  final Color color;
  final double radius;
  final double duration = 0.28;
  double age = 0;
}

class HitParticle {
  HitParticle({required this.position, required this.velocity, required this.color, required this.duration});
  Offset position;
  final Offset velocity;
  final Color color;
  final double duration;
  double age = 0;
}
