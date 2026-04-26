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

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  Size _screenSize = Size.zero;

  final List<OrbitPlanet> _planets = [];
  final List<RingShot> _shots = [];
  final List<HitParticle> _particles = [];

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
    _shots.clear();
    _particles.clear();
    _score = 0;
    _lives = maxLives;
    _hitStreak = 0;
    _bestCombo = 0;
    _totalHits = 0;
    _targetIndex = 0;
    _flashOpacity = 0;
    _comboPulse = 0;
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
        angle: -pi / 2 + index * 0.9,
        speed: direction * (1.15 + index * 0.22),
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
      _updateShots(dt);
      _updateParticles(dt);
      _flashOpacity = max(0, _flashOpacity - dt / 0.2);
      _comboPulse = max(0, _comboPulse - dt / 0.28);
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

  void _updateShots(double dt) {
    final completed = <RingShot>[];
    for (final shot in _shots) {
      shot.radius += shot.speed * dt;
      shot.life += dt;

      if (shot.targetIndex >= _planets.length || _screenSize == Size.zero) {
        completed.add(shot);
        continue;
      }

      final planet = _planets[shot.targetIndex];
      final orbitRadius = _orbitRadiusFor(planet.index, _screenSize);
      final reachedOrbit = shot.previousRadius < orbitRadius && shot.radius >= orbitRadius;

      if (reachedOrbit) {
        final hit = _angleDistance(shot.firedAngle, planet.angle) <= 0.24;
        hit ? _handleHit(planet) : _handleMiss();
        completed.add(shot);
      } else if (shot.radius > orbitRadius + 40) {
        _handleMiss();
        completed.add(shot);
      }
      shot.previousRadius = shot.radius;
    }
    _shots.removeWhere(completed.contains);
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

  void _shoot() {
    if (_gameEnded || _screenSize == Size.zero || _planets.isEmpty) return;
    final target = _planets[_targetIndex.clamp(0, _planets.length - 1)];
    _shots.add(
      RingShot(
        color: target.color,
        targetIndex: target.index,
        firedAngle: target.angle,
        radius: 22,
        previousRadius: 22,
        speed: 520,
      ),
    );
  }

  void _handleHit(OrbitPlanet planet) {
    _totalHits++;
    _hitStreak++;
    _bestCombo = max(_bestCombo, _hitStreak);
    _score += _hitStreak >= 3 ? 2 : 1;
    _flashColor = Colors.white;
    _flashOpacity = 0.3;
    if (_hitStreak == 3 || _hitStreak % 5 == 0) _comboPulse = 1.0;
    _spawnBurst(planet);

    if (_totalHits % 3 == 0) {
      for (final p in _planets) {
        p.speed *= 1.10;
      }
    }
    if (_totalHits % 5 == 0 && _planets.length < maxPlanets) _addPlanet();

    _targetIndex++;
    if (_targetIndex >= _planets.length) _targetIndex = 0;
  }

  void _handleMiss() {
    _hitStreak = 0;
    _lives--;
    _flashColor = Colors.red;
    _flashOpacity = 0.4;
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

  void _spawnBurst(OrbitPlanet planet) {
    if (_screenSize == Size.zero) return;
    final center = _screenSize.center(Offset.zero);
    final radius = _orbitRadiusFor(planet.index, _screenSize);
    final impact = Offset(center.dx + cos(planet.angle) * radius, center.dy + sin(planet.angle) * radius);
    for (int i = 0; i < 12; i++) {
      final angle = (pi * 2 / 12) * i;
      final double speed = 120.0 + (i % 3) * 35.0;
      _particles.add(HitParticle(position: impact, velocity: Offset(cos(angle), sin(angle)) * speed, color: planet.color, duration: 0.4));
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

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final comboActive = _hitStreak >= 3;
    final comboScale = 1.0 + _comboPulse * 0.22;
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          _screenSize = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _shoot(),
            child: Stack(
              children: [
                CustomPaint(
                  size: Size.infinite,
                  painter: TapOrbitPainter(
                    planets: _planets,
                    shots: _shots,
                    particles: _particles,
                    lives: _lives,
                    flashColor: _flashColor,
                    flashOpacity: _flashOpacity,
                    targetIndex: _targetIndex,
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
                                  color: _planets.isEmpty ? Colors.cyanAccent : _planets[_targetIndex.clamp(0, _planets.length - 1)].color,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2.4,
                                  shadows: [
                                    Shadow(
                                      color: _planets.isEmpty ? Colors.cyanAccent : _planets[_targetIndex.clamp(0, _planets.length - 1)].color,
                                      blurRadius: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
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
  TapOrbitPainter({required this.planets, required this.shots, required this.particles, required this.lives, required this.flashColor, required this.flashOpacity, required this.targetIndex});

  final List<OrbitPlanet> planets;
  final List<RingShot> shots;
  final List<HitParticle> particles;
  final int lives;
  final Color flashColor;
  final double flashOpacity;
  final int targetIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    _paintOrbits(canvas, size, center);
    _paintStar(canvas, center, size);
    _paintShots(canvas, center);
    _paintPlanetTrails(canvas);
    _paintPlanets(canvas, size, center);
    _paintParticles(canvas);
    _paintLives(canvas, size);
    if (flashOpacity > 0) canvas.drawRect(Offset.zero & size, Paint()..color = flashColor.withOpacity(flashOpacity));
  }

  void _paintOrbits(Canvas canvas, Size size, Offset center) {
    for (final planet in planets) {
      final active = planet.index == targetIndex;
      canvas.drawCircle(center, _orbitRadiusFor(planet.index, size), Paint()..style = PaintingStyle.stroke..strokeWidth = active ? 1.4 : 0.8..color = planet.color.withOpacity(active ? 0.28 : 0.12));
    }
  }

  void _paintStar(Canvas canvas, Offset center, Size size) {
    final coreRadius = min(size.width, size.height) * 0.035;
    canvas.drawCircle(center, coreRadius * 3.4, Paint()..color = Colors.white.withOpacity(0.2)..maskFilter = const MaskFilter.blur(BlurStyle.outer, 36));
    canvas.drawCircle(center, coreRadius * 2.4, Paint()..color = const Color(0xFFFFF176).withOpacity(0.45)..maskFilter = const MaskFilter.blur(BlurStyle.outer, 26));
    canvas.drawCircle(center, coreRadius * 1.7, Paint()..color = const Color(0xFFFF8A00).withOpacity(0.55)..maskFilter = const MaskFilter.blur(BlurStyle.outer, 18));
    canvas.drawCircle(center, coreRadius, Paint()..shader = const RadialGradient(colors: [Colors.white, Color(0xFFFFF176), Color(0xFFFF9800)]).createShader(Rect.fromCircle(center: center, radius: coreRadius * 1.2)));
  }

  void _paintShots(Canvas canvas, Offset center) {
    for (final shot in shots) {
      final fade = (1.0 - shot.life / 0.9).clamp(0.0, 1.0);
      canvas.drawCircle(center, shot.radius, Paint()..style = PaintingStyle.stroke..strokeWidth = 8..color = shot.color.withOpacity(0.22 * fade)..maskFilter = const MaskFilter.blur(BlurStyle.outer, 12));
      canvas.drawCircle(center, shot.radius, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = shot.color.withOpacity(0.9 * fade));
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
      final orbitRadius = _orbitRadiusFor(planet.index, size);
      final position = Offset(center.dx + cos(planet.angle) * orbitRadius, center.dy + sin(planet.angle) * orbitRadius);
      canvas.drawCircle(position, 14, Paint()..color = planet.color.withOpacity(0.22)..maskFilter = const MaskFilter.blur(BlurStyle.outer, 18));
      canvas.drawCircle(position, 9, Paint()..color = planet.color.withOpacity(0.45)..maskFilter = const MaskFilter.blur(BlurStyle.outer, 10));
      canvas.drawCircle(position, 6.8, Paint()..color = planet.color);
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

class RingShot {
  RingShot({required this.color, required this.targetIndex, required this.firedAngle, required this.radius, required this.previousRadius, required this.speed});
  final Color color;
  final int targetIndex;
  final double firedAngle;
  double radius;
  double previousRadius;
  final double speed;
  double life = 0;
}

class HitParticle {
  HitParticle({required this.position, required this.velocity, required this.color, required this.duration});
  Offset position;
  final Offset velocity;
  final Color color;
  final double duration;
  double age = 0;
}
