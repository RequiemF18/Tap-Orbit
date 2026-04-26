import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_service.dart';
import 'game_over.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  static const int maxLives = 3;
  static const int maxPlanets = 4;
  static const double gateAngle = -pi / 2;
  static const double hitWindow = 0.34;
  static const double perfectWindow = 0.12;
  static const int warmupHitsToSecondOrbit = 3;
  static const int hitsPerAdditionalOrbit = 5;
  static const double firstOrbitWarmupLead = 1.55;
  static const double firstOrbitWarmupBoost = 1.28;

  late final Ticker _ticker;
  final Random _random = Random(42);

  Duration _lastElapsed = Duration.zero;
  Size _screenSize = Size.zero;
  Size _backgroundSize = Size.zero;

  final List<OrbitPlanet> _planets = [];
  final List<HitParticle> _particles = [];
  final List<TapRipple> _ripples = [];
  final List<BackgroundStar> _stars = [];
  final List<BackgroundPlanet> _backgroundPlanets = [];
  final List<SpaceDustParticle> _spaceDust = [];
  final List<CometTrail> _comets = [];

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
  double _clock = 0;
  double _hintOpacity = 1;
  double _feedbackAge = 1;
  double _cometCooldown = 4;
  String _feedbackText = '';
  Color _feedbackColor = Colors.white;
  bool _gameEnded = false;

  final List<PlanetStyle> _planetStyles = const [
    PlanetStyle(
      base: Color(0xFF56E7FF),
      shadow: Color(0xFF0F3F7E),
      light: Color(0xFFDBFFFF),
      accent: Color(0xFF26B7FF),
      outline: Color(0xFFE8FFFF),
      ringColor: Color(0xFFAAEEFF),
      moonColor: Color(0xFFEBFFFF),
      pattern: PlanetPattern.bands,
      hasRing: true,
    ),
    PlanetStyle(
      base: Color(0xFFFF5AD6),
      shadow: Color(0xFF66135F),
      light: Color(0xFFFFC4F2),
      accent: Color(0xFFFF8B5C),
      outline: Color(0xFFFFE4FA),
      ringColor: Color(0xFFFFB0EB),
      moonColor: Color(0xFFFFD9E8),
      pattern: PlanetPattern.core,
      hasMoon: true,
    ),
    PlanetStyle(
      base: Color(0xFFBFFF4D),
      shadow: Color(0xFF456B07),
      light: Color(0xFFF1FFC4),
      accent: Color(0xFF5EE86C),
      outline: Color(0xFFF5FFDF),
      ringColor: Color(0xFFB6FFB0),
      moonColor: Color(0xFFE8FFC2),
      pattern: PlanetPattern.craters,
      hasMoon: true,
    ),
    PlanetStyle(
      base: Color(0xFFFFC14D),
      shadow: Color(0xFF8C4300),
      light: Color(0xFFFFF0B0),
      accent: Color(0xFFFF7547),
      outline: Color(0xFFFFF3D6),
      ringColor: Color(0xFFFFDE92),
      moonColor: Color(0xFFFFE1B0),
      pattern: PlanetPattern.storm,
      hasRing: true,
    ),
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
    _clock = 0;
    _hintOpacity = 1;
    _feedbackAge = 1;
    _feedbackText = '';
    _feedbackColor = Colors.white;
    _gameEnded = false;
    _addPlanet();
  }

  void _generateBackground(Size size) {
    _backgroundSize = size;
    _stars.clear();
    _backgroundPlanets.clear();
    _spaceDust.clear();
    _comets.clear();

    for (int i = 0; i < 155; i++) {
      final layer = _random.nextInt(3);
      _stars.add(
        BackgroundStar(
          position: Offset(
            _random.nextDouble() * size.width,
            _random.nextDouble() * size.height,
          ),
          size: layer == 0 ? 1.2 : (layer == 1 ? 2.1 : 3.0),
          baseOpacity: layer == 0 ? 0.20 : (layer == 1 ? 0.38 : 0.62),
          phase: _random.nextDouble() * pi * 2,
          twinkleSpeed: 0.7 + _random.nextDouble() * 2.2,
          cross: _random.nextDouble() > 0.88,
          driftPhase: _random.nextDouble() * pi * 2,
          driftSpeed: 0.12 + _random.nextDouble() * 0.35,
          driftAmplitude: layer == 2 ? 1.2 : 0.6,
        ),
      );
    }

    for (int i = 0; i < 95; i++) {
      final layer = _random.nextInt(3);
      _spaceDust.add(
        SpaceDustParticle(
          position: Offset(
            _random.nextDouble() * size.width,
            _random.nextDouble() * size.height,
          ),
          velocity: Offset(
            (_random.nextDouble() - 0.5) * 3,
            4 + _random.nextDouble() * (layer == 0 ? 6 : 12),
          ),
          size: layer == 0 ? 1.4 : (layer == 1 ? 2.2 : 3.0),
          opacity: layer == 0 ? 0.06 : (layer == 1 ? 0.10 : 0.16),
          phase: _random.nextDouble() * pi * 2,
        ),
      );
    }

    final s = min(size.width, size.height);
    _backgroundPlanets.addAll([
      BackgroundPlanet(
        center: Offset(size.width * 0.15, size.height * 0.18),
        radius: s * 0.08,
        base: const Color(0xFF3856FF),
        shadow: const Color(0xFF17205E),
        light: const Color(0xFFA6B6FF),
        accent: const Color(0xFF6EE7FF),
        outline: const Color(0xFFE4F6FF),
        pixelSize: 4,
        ring: true,
        ringColor: const Color(0xFF9ACBFF),
        moonColor: const Color(0xFFD9F8FF),
        pattern: PlanetPattern.bands,
        ringTilt: -0.28,
        phase: _random.nextDouble() * pi * 2,
        pulseSpeed: 0.8,
        motes: _createPlanetMotes(7),
      ),
      BackgroundPlanet(
        center: Offset(size.width * 0.88, size.height * 0.28),
        radius: s * 0.11,
        base: const Color(0xFF7F2AFF),
        shadow: const Color(0xFF310C6A),
        light: const Color(0xFFC9A5FF),
        accent: const Color(0xFFFF6AD6),
        outline: const Color(0xFFF4D8FF),
        pixelSize: 5,
        ring: false,
        moonColor: const Color(0xFFFFC4F2),
        pattern: PlanetPattern.core,
        hasMoon: true,
        phase: _random.nextDouble() * pi * 2,
        pulseSpeed: 0.65,
        motes: _createPlanetMotes(9),
      ),
      BackgroundPlanet(
        center: Offset(size.width * 0.84, size.height * 0.82),
        radius: s * 0.09,
        base: const Color(0xFFFFA531),
        shadow: const Color(0xFF8A4B00),
        light: const Color(0xFFFFD388),
        accent: const Color(0xFFFF7045),
        outline: const Color(0xFFFFEDC2),
        pixelSize: 4,
        ring: true,
        ringColor: const Color(0xFFFFE4B5),
        moonColor: const Color(0xFFFFE9C7),
        pattern: PlanetPattern.storm,
        ringTilt: -0.48,
        phase: _random.nextDouble() * pi * 2,
        pulseSpeed: 0.72,
        motes: _createPlanetMotes(8),
      ),
      BackgroundPlanet(
        center: Offset(size.width * 0.51, size.height * 0.12),
        radius: s * 0.045,
        base: const Color(0xFF81FF68),
        shadow: const Color(0xFF2C6A1C),
        light: const Color(0xFFE6FFB2),
        accent: const Color(0xFFB7FF74),
        outline: const Color(0xFFF5FFD9),
        pixelSize: 3,
        ring: false,
        moonColor: const Color(0xFFE6FFC6),
        pattern: PlanetPattern.craters,
        hasMoon: true,
        phase: _random.nextDouble() * pi * 2,
        pulseSpeed: 0.92,
        motes: _createPlanetMotes(5),
      ),
      BackgroundPlanet(
        center: Offset(size.width * 0.09, size.height * 0.78),
        radius: s * 0.055,
        base: const Color(0xFFFF6D74),
        shadow: const Color(0xFF7A1E33),
        light: const Color(0xFFFFC5D0),
        accent: const Color(0xFFFFA85D),
        outline: const Color(0xFFFFE0E5),
        pixelSize: 3.5,
        ring: true,
        ringColor: const Color(0xFFFFC7A0),
        moonColor: const Color(0xFFFFE5D0),
        pattern: PlanetPattern.core,
        ringTilt: -0.16,
        phase: _random.nextDouble() * pi * 2,
        pulseSpeed: 0.58,
        motes: _createPlanetMotes(6),
      ),
    ]);

    _cometCooldown = 1.8 + _random.nextDouble() * 3.2;
  }

  List<PlanetMote> _createPlanetMotes(int count) {
    return List.generate(
      count,
      (_) => PlanetMote(
        angle: _random.nextDouble() * pi * 2,
        speed: 0.3 + _random.nextDouble() * 0.8,
        distance: 10 + _random.nextDouble() * 12,
        size: _random.nextDouble() > 0.6 ? 2.5 : 1.8,
        phase: _random.nextDouble() * pi * 2,
      ),
    );
  }

  void _addPlanet() {
    if (_planets.length >= maxPlanets) return;
    final index = _planets.length;
    final direction = index.isEven ? 1.0 : -1.0;
    _planets.add(
      OrbitPlanet(
        color: _planetStyles[index].base,
        style: _planetStyles[index],
        angle: _initialAngleForPlanet(index),
        speed: direction * (0.95 + index * 0.18),
        index: index,
      ),
    );
  }

  double _initialAngleForPlanet(int index) {
    if (index == 0) {
      return gateAngle + (pi * 2) - firstOrbitWarmupLead;
    }
    return pi / 2 + index * 0.75;
  }

  int _hitsNeededForNextOrbit() {
    if (_planets.length >= maxPlanets) return 1 << 30;
    if (_planets.length <= 1) return warmupHitsToSecondOrbit;
    return warmupHitsToSecondOrbit +
        (_planets.length - 1) * hitsPerAdditionalOrbit;
  }

  double _orbitSpeedMultiplierFor(OrbitPlanet planet) {
    if (planet.index != 0 || _planets.length != 1) return 1.0;

    final hitProgress = (_totalHits / warmupHitsToSecondOrbit).clamp(0.0, 1.0);
    final timeProgress = (_clock / 12.0).clamp(0.0, 1.0);
    final progress = max(hitProgress, timeProgress);
    return lerpDouble(firstOrbitWarmupBoost, 1.0, progress) ?? 1.0;
  }

  void _tick(Duration elapsed) {
    if (_gameEnded) return;
    final dt = _lastElapsed == Duration.zero
        ? 0.0
        : (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.05) return;

    setState(() {
      _clock += dt;
      _updateAmbient(dt);
      _updatePlanets(dt);
      _updateParticles(dt);
      _updateRipples(dt);
      _flashOpacity = max(0, _flashOpacity - dt / 0.20);
      _comboPulse = max(0, _comboPulse - dt / 0.28);
      _gatePulse = max(0, _gatePulse - dt / 0.22);
      _feedbackAge += dt;
      if (_totalHits > 0 || _lives < maxLives) {
        _hintOpacity = max(0, _hintOpacity - dt / 1.4);
      }
    });
  }

  void _updateAmbient(double dt) {
    for (final star in _stars) {
      star.phase += dt * star.twinkleSpeed;
      star.driftPhase += dt * star.driftSpeed;
    }

    for (final dust in _spaceDust) {
      dust.phase += dt * 0.8;
      dust.position += dust.velocity * dt;
      if (_screenSize != Size.zero) {
        if (dust.position.dy > _screenSize.height + 8) {
          dust.position = Offset(_random.nextDouble() * _screenSize.width, -8);
        }
        if (dust.position.dx < -8) {
          dust.position = Offset(_screenSize.width + 8, dust.position.dy);
        } else if (dust.position.dx > _screenSize.width + 8) {
          dust.position = Offset(-8, dust.position.dy);
        }
      }
    }

    for (final planet in _backgroundPlanets) {
      planet.phase += dt * planet.pulseSpeed;
      for (final mote in planet.motes) {
        mote.angle += dt * mote.speed;
        mote.phase += dt * 1.2;
      }
    }

    _cometCooldown -= dt;
    if (_cometCooldown <= 0 && _screenSize != Size.zero) {
      _spawnComet();
      _cometCooldown = 2.2 + _random.nextDouble() * 4.2;
    }

    final dead = <CometTrail>[];
    for (final comet in _comets) {
      comet.age += dt;
      comet.position += comet.velocity * dt;
      if (comet.age >= comet.duration) dead.add(comet);
    }
    _comets.removeWhere(dead.contains);
  }

  void _spawnComet() {
    final w = _screenSize.width;
    final h = _screenSize.height;
    final side = _random.nextInt(4);

    late Offset start;
    late Offset end;

    switch (side) {
      case 0:
        start = Offset(-24, _random.nextDouble() * h);
        end = Offset(w + 80, _random.nextDouble() * h);
        break;
      case 1:
        start = Offset(w + 24, _random.nextDouble() * h);
        end = Offset(-80, _random.nextDouble() * h);
        break;
      case 2:
        start = Offset(_random.nextDouble() * w, -24);
        end = Offset(_random.nextDouble() * w, h + 80);
        break;
      default:
        start = Offset(_random.nextDouble() * w, h + 24);
        end = Offset(_random.nextDouble() * w, -80);
        break;
    }

    final rawDirection = end - start;
    final distance = rawDirection.distance == 0 ? 1.0 : rawDirection.distance;
    final direction = rawDirection / distance;
    final speed = 420 + _random.nextDouble() * 240;

    _comets.add(
      CometTrail(
        position: start,
        velocity: direction * speed,
        duration: 0.9 + _random.nextDouble() * 0.35,
        size: 3.0 + _random.nextDouble() * 1.8,
        tailLength: 12 + _random.nextInt(9),
        color: _random.nextDouble() > 0.45
            ? Colors.white
            : const Color(0xFF9EEBFF),
      ),
    );
  }

  void _updatePlanets(double dt) {
    for (final planet in _planets) {
      final speedMultiplier = _orbitSpeedMultiplierFor(planet);
      planet.angle += planet.speed * speedMultiplier * dt;
      planet.spin += dt *
          (planet.speed.isNegative ? -0.9 : 0.9) *
          speedMultiplier *
          (0.85 + planet.index * 0.14);
      if (_screenSize != Size.zero) {
        final center = _screenSize.center(Offset.zero);
        final radius = _orbitRadiusFor(planet.index, _screenSize);
        final position = Offset(
          center.dx + cos(planet.angle) * radius,
          center.dy + sin(planet.angle) * radius,
        );
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
    AudioService.playTap();

    final target = _planets[_targetIndex.clamp(0, _planets.length - 1)];
    final distance = _angleDistance(target.angle, gateAngle);
    final center = _screenSize.center(Offset.zero);
    final radius = _orbitRadiusFor(target.index, _screenSize);
    final gatePosition = Offset(
      center.dx + cos(gateAngle) * radius,
      center.dy + sin(gateAngle) * radius,
    );

    _ripples.add(TapRipple(color: target.color, radius: radius));
    _gatePulse = 1.0;

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

    if (perfect) {
      AudioService.playPerfect();
    } else {
      AudioService.playHit();
    }
    if (_hitStreak == 3 || _hitStreak % 5 == 0) {
      AudioService.playCombo();
    }

    _flashColor = Colors.white;
    _flashOpacity = perfect ? 0.38 : 0.26;
    _feedbackText = perfect ? 'PERFECT' : 'NICE';
    _feedbackColor = planet.color;
    _feedbackAge = 0;
    if (_hitStreak == 3 || _hitStreak % 5 == 0 || perfect) _comboPulse = 1.0;
    _spawnBurst(
      impact,
      planet.color,
      perfect ? 30 : 20,
      outwardPower: perfect ? 190 : 145,
    );

    if (_totalHits % 3 == 0) {
      for (final p in _planets) {
        p.speed *= 1.10;
      }
    }
    if (_totalHits >= _hitsNeededForNextOrbit()) _addPlanet();

    _targetIndex++;
    if (_targetIndex >= _planets.length) _targetIndex = 0;
  }

  void _handleMiss(String message, Color color) {
    AudioService.playMiss();
    _hitStreak = 0;
    _lives--;
    _flashColor = Colors.red;
    _flashOpacity = 0.40;
    _feedbackText = message;
    _feedbackColor = Colors.redAccent;
    _feedbackAge = 0;
    if (_screenSize != Size.zero) {
      _spawnBurst(
        _screenSize.center(Offset.zero),
        color.withOpacity(0.8),
        12,
        outwardPower: 105,
      );
    }
    if (_lives <= 0) _endGame();
  }

  Future<void> _endGame() async {
    if (_gameEnded) return;
    AudioService.playGameOver();
    _gameEnded = true;
    _ticker.stop();

    final newBest = max(_personalBest, _score);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tap_orbit_best_score', newBest);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GameOverScreen(
          finalScore: _score,
          bestCombo: _bestCombo,
          personalBest: newBest,
        ),
      ),
    );
  }

  void _spawnBurst(
    Offset impact,
    Color color,
    int count, {
    required double outwardPower,
  }) {
    for (int i = 0; i < count; i++) {
      final angle = (pi * 2 / count) * i;
      final speed = outwardPower + (i % 4) * 28.0;
      _particles.add(
        HitParticle(
          position: impact,
          velocity: Offset(cos(angle), sin(angle)) * speed,
          color: color,
          duration: 0.45,
          size: (i % 3 == 0) ? 4.0 : 3.0,
        ),
      );
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
    final activeColor = _planets.isEmpty
        ? Colors.cyanAccent
        : _planets[_targetIndex.clamp(0, _planets.length - 1)].color;

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final newSize = Size(constraints.maxWidth, constraints.maxHeight);
          _screenSize = newSize;
          if (_backgroundSize != newSize || _stars.isEmpty)
            _generateBackground(newSize);

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
                    stars: _stars,
                    backgroundPlanets: _backgroundPlanets,
                    spaceDust: _spaceDust,
                    comets: _comets,
                    lives: _lives,
                    flashColor: _flashColor,
                    flashOpacity: _flashOpacity,
                    targetIndex: _targetIndex,
                    gateAngle: gateAngle,
                    hitWindow: hitWindow,
                    perfectWindow: perfectWindow,
                    gatePulse: _gatePulse,
                    time: _clock,
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: 12,
                      left: 16,
                      right: 16,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _PixelPanel(
                              borderColor: activeColor,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'SCORE',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$_score',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 34,
                                      fontWeight: FontWeight.w900,
                                      height: 1,
                                      shadows: [
                                        Shadow(
                                          color: Colors.white54,
                                          blurRadius: 12,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            _PixelPanel(
                              borderColor: Colors.white54,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text(
                                    'BEST',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$_personalBest',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      height: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        AnimatedOpacity(
                          opacity: comboActive ? 1 : 0,
                          duration: const Duration(milliseconds: 140),
                          child: Transform.scale(
                            scale: comboScale,
                            child: _PixelPanel(
                              borderColor: activeColor,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              child: Text(
                                'COMBO x2  $_hitStreak',
                                style: TextStyle(
                                  color: activeColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.8,
                                  shadows: [
                                    Shadow(color: activeColor, blurRadius: 16),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IgnorePointer(
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: feedbackVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 80),
                      child: Transform.scale(
                        scale: 1.0 +
                            (1.0 - _feedbackAge.clamp(0.0, 0.65) / 0.65) * 0.14,
                        child: Text(
                          _feedbackText,
                          style: TextStyle(
                            color: _feedbackColor,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.4,
                            shadows: [
                              Shadow(color: _feedbackColor, blurRadius: 24),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        bottom: 78,
                      ),
                      child: AnimatedOpacity(
                        opacity: _hintOpacity,
                        duration: const Duration(milliseconds: 250),
                        child: _PixelPanel(
                          borderColor: activeColor,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'TAP WHEN THE PLANET ENTERS THE GATE',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: activeColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.1,
                                  shadows: [
                                    Shadow(color: activeColor, blurRadius: 14),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 5),
                              const Text(
                                'Hit the glowing arc at the top',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
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
    required this.stars,
    required this.backgroundPlanets,
    required this.spaceDust,
    required this.comets,
    required this.lives,
    required this.flashColor,
    required this.flashOpacity,
    required this.targetIndex,
    required this.gateAngle,
    required this.hitWindow,
    required this.perfectWindow,
    required this.gatePulse,
    required this.time,
  });

  final List<OrbitPlanet> planets;
  final List<HitParticle> particles;
  final List<TapRipple> ripples;
  final List<BackgroundStar> stars;
  final List<BackgroundPlanet> backgroundPlanets;
  final List<SpaceDustParticle> spaceDust;
  final List<CometTrail> comets;
  final int lives;
  final Color flashColor;
  final double flashOpacity;
  final int targetIndex;
  final double gateAngle;
  final double hitWindow;
  final double perfectWindow;
  final double gatePulse;
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    _paintBackground(canvas, size);
    _paintSpaceDust(canvas);
    _paintBackgroundPlanets(canvas);
    _paintStars(canvas);
    _paintComets(canvas);
    _paintOrbitGates(canvas, size, center);
    _paintCenterStar(canvas, center, size);
    _paintRipples(canvas, center);
    _paintPlanetTrails(canvas);
    _paintPlanets(canvas, size, center);
    _paintParticles(canvas);
    _paintLives(canvas, size);

    if (flashOpacity > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = flashColor.withOpacity(flashOpacity),
      );
    }
  }

  void _paintBackground(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF03040A),
    );
    canvas.drawCircle(
      Offset(size.width * 0.2, size.height * 0.22),
      95,
      Paint()
        ..color = const Color(0xFF233B8F).withOpacity(0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 70),
    );
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.74),
      115,
      Paint()
        ..color = const Color(0xFF7B2F8F).withOpacity(0.09)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 85),
    );
  }

  void _paintSpaceDust(Canvas canvas) {
    for (final dust in spaceDust) {
      final pulse = 0.7 + (sin(dust.phase) * 0.5 + 0.5) * 0.4;
      canvas.drawRect(
        Rect.fromCenter(
          center: dust.position,
          width: dust.size,
          height: dust.size,
        ),
        Paint()
          ..color = Colors.white.withOpacity(dust.opacity * pulse)
          ..isAntiAlias = false,
      );
    }
  }

  void _paintStars(Canvas canvas) {
    for (final star in stars) {
      final twinkle = 0.7 + (sin(star.phase) * 0.5 + 0.5) * 0.6;
      final breath = 1.0 + sin(star.phase * 0.8) * 0.12;
      final pos = star.position +
          Offset(
            cos(star.driftPhase) * star.driftAmplitude,
            sin(star.driftPhase * 0.85) * star.driftAmplitude,
          );
      final size = star.size * breath;
      final opacity = (star.baseOpacity * twinkle).clamp(0.0, 1.0);

      if (star.baseOpacity > 0.4) {
        canvas.drawCircle(
          pos,
          size * 2.4,
          Paint()
            ..color = Colors.white.withOpacity(opacity * 0.08)
            ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6),
        );
      }

      final paint = Paint()
        ..color = Colors.white.withOpacity(opacity)
        ..isAntiAlias = false;

      canvas.drawRect(
        Rect.fromCenter(center: pos, width: size, height: size),
        paint,
      );
      if (star.cross) {
        canvas.drawRect(
          Rect.fromCenter(center: pos, width: size * 3, height: size),
          paint,
        );
        canvas.drawRect(
          Rect.fromCenter(center: pos, width: size, height: size * 3),
          paint,
        );
      }
    }
  }

  void _paintBackgroundPlanets(Canvas canvas) {
    for (final planet in backgroundPlanets) {
      final pulse = 0.5 + (sin(planet.phase) * 0.5 + 0.5) * 0.5;
      final floatOffset = Offset(
        sin(planet.phase * 0.55 + time * 0.18) * (planet.radius * 0.08),
        cos(planet.phase * 0.42 - time * 0.12) * (planet.radius * 0.05),
      );
      final center = planet.center + floatOffset;
      final style = PlanetStyle(
        base: planet.base.withOpacity(0.94),
        shadow: planet.shadow.withOpacity(0.96),
        light: planet.light.withOpacity(0.96),
        accent: planet.accent.withOpacity(0.92),
        outline: planet.outline.withOpacity(0.96),
        ringColor: (planet.ringColor ?? planet.outline).withOpacity(0.92),
        moonColor: planet.moonColor,
        pattern: planet.pattern,
        hasRing: planet.ring,
        hasMoon: planet.hasMoon,
      );

      canvas.drawCircle(
        center,
        planet.radius + 16 + pulse * 6,
        Paint()
          ..color = planet.accent.withOpacity(0.08 + pulse * 0.08)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 24),
      );

      if (planet.ring) {
        _drawTiltedPixelRing(
          canvas,
          center: center,
          radiusX: planet.radius + 12,
          radiusY: planet.radius * 0.52 + 2,
          rotation: planet.ringTilt,
          color: style.ringColor.withOpacity(0.30),
          pixel: max(2.0, planet.pixelSize * 0.60),
          front: false,
        );
      }

      _drawPlanetSprite(
        canvas,
        center: center,
        radius: planet.radius,
        style: style,
        pixel: planet.pixelSize,
        spin: planet.phase * 0.45 + time * 0.10,
        active: pulse > 0.70,
      );

      if (planet.hasMoon) {
        _drawOrbitMoon(
          canvas,
          center: center,
          radius: planet.radius,
          angle: planet.phase + time * 0.15,
          color: planet.moonColor,
          active: false,
        );
      }

      if (planet.ring) {
        _drawTiltedPixelRing(
          canvas,
          center: center,
          radiusX: planet.radius + 12,
          radiusY: planet.radius * 0.52 + 2,
          rotation: planet.ringTilt,
          color: style.outline.withOpacity(0.48),
          pixel: max(2.0, planet.pixelSize * 0.60),
          front: true,
        );
      }

      if (planet.radius > 28) {
        _drawPlanetSparkles(
          canvas,
          center: center,
          radius: planet.radius + 8,
          spin: planet.phase * 0.5,
          color: planet.outline.withOpacity(0.65),
        );
      }

      for (final mote in planet.motes) {
        final dist = planet.radius + mote.distance + sin(mote.phase) * 1.5;
        final pos = center +
            Offset(cos(mote.angle) * dist, sin(mote.angle) * dist * 0.72);
        final alpha = 0.18 + (sin(mote.phase) * 0.5 + 0.5) * 0.34;

        canvas.drawRect(
          Rect.fromCenter(center: pos, width: mote.size, height: mote.size),
          Paint()
            ..color = planet.outline.withOpacity(alpha)
            ..isAntiAlias = false,
        );
      }
    }
  }

  void _paintComets(Canvas canvas) {
    for (final comet in comets) {
      final t = (comet.age / comet.duration).clamp(0.0, 1.0);
      final alpha = 1.0 - t;
      final velocityLength = comet.velocity.distance;
      if (velocityLength == 0) continue;
      final direction = comet.velocity / velocityLength;

      for (int i = 0; i < comet.tailLength; i++) {
        final tailT = i / comet.tailLength;
        final point = comet.position - direction * (i * 5.0);
        final size = comet.size * (1.0 - tailT * 0.75);
        final opacity = alpha * (1.0 - tailT);

        canvas.drawRect(
          Rect.fromCenter(center: point, width: size, height: size),
          Paint()
            ..color = comet.color.withOpacity(opacity)
            ..isAntiAlias = false,
        );
      }

      canvas.drawCircle(
        comet.position,
        comet.size * 2.2,
        Paint()
          ..color = comet.color.withOpacity(alpha * 0.10)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6),
      );
    }
  }

  void _paintOrbitGates(Canvas canvas, Size size, Offset center) {
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
          ..color = color.withOpacity(active ? 0.20 : 0.08),
      );

      if (!active) continue;

      var rawDistance = (planet.angle - gateAngle).abs() % (pi * 2);
      if (rawDistance > pi) rawDistance = pi * 2 - rawDistance;
      final approach = (1.0 - (rawDistance / 0.9)).clamp(0.0, 1.0);
      final eased = approach * approach * (3 - 2 * approach);
      final markerFade = (1.0 - approach * 1.4).clamp(0.0, 1.0);

      final rect = Rect.fromCircle(center: center, radius: radius);

      canvas.drawArc(
        rect,
        gateAngle - hitWindow,
        hitWindow * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 12 + gatePulse * 6
          ..color = color.withOpacity(0.10 + eased * 0.10 + gatePulse * 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 14),
      );

      canvas.drawArc(
        rect,
        gateAngle - hitWindow,
        hitWindow * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 4.5
          ..color = color.withOpacity(0.55 + eased * 0.30),
      );

      canvas.drawArc(
        rect,
        gateAngle - perfectWindow,
        perfectWindow * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2.2
          ..color = Colors.white.withOpacity(0.85),
      );

      _drawBoundaryTick(canvas, center, radius, gateAngle - hitWindow, color);
      _drawBoundaryTick(canvas, center, radius, gateAngle + hitWindow, color);

      if (markerFade > 0.05)
        _drawPerfectPip(canvas, center, radius, color, markerFade);
    }
  }

  void _drawBoundaryTick(
    Canvas canvas,
    Offset center,
    double radius,
    double angle,
    Color color,
  ) {
    final inner = Offset(
      center.dx + cos(angle) * (radius - 5),
      center.dy + sin(angle) * (radius - 5),
    );
    final outer = Offset(
      center.dx + cos(angle) * (radius + 5),
      center.dy + sin(angle) * (radius + 5),
    );
    canvas.drawLine(
      inner,
      outer,
      Paint()
        ..color = color.withOpacity(0.65)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.square,
    );
  }

  void _drawPerfectPip(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double fade,
  ) {
    final pipCenter = Offset(
      center.dx + cos(gateAngle) * (radius + 14),
      center.dy + sin(gateAngle) * (radius + 14),
    );
    final size = 2.5;
    final path = Path()
      ..moveTo(pipCenter.dx, pipCenter.dy - size)
      ..lineTo(pipCenter.dx + size, pipCenter.dy)
      ..lineTo(pipCenter.dx, pipCenter.dy + size)
      ..lineTo(pipCenter.dx - size, pipCenter.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withOpacity(0.85 * fade));
  }

  void _paintCenterStar(Canvas canvas, Offset center, Size size) {
    final coreRadius = min(size.width, size.height) * 0.04;
    canvas.drawCircle(
      center,
      coreRadius * 3.6,
      Paint()
        ..color = Colors.white.withOpacity(0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 24),
    );
    canvas.drawCircle(
      center,
      coreRadius * 2.3,
      Paint()
        ..color = const Color(0xFFFFCB47).withOpacity(0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 18),
    );
    _drawPixelPlanet(
      canvas,
      center: center,
      radius: coreRadius,
      base: const Color(0xFFFFB347),
      shadow: const Color(0xFFCC6A00),
      light: const Color(0xFFFFF1A8),
      pixel: 3,
    );
  }

  void _paintRipples(Canvas canvas, Offset center) {
    for (final ripple in ripples) {
      final t = (ripple.age / ripple.duration).clamp(0.0, 1.0);
      final radius = lerpDouble(18, ripple.radius, t) ?? ripple.radius;
      final opacity = 1.0 - t;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = lerpDouble(10, 3, t) ?? 3
          ..color = ripple.color.withOpacity(opacity * 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 10),
      );
      _drawPixelRing(
        canvas,
        center: center,
        radius: radius,
        color: ripple.color.withOpacity(opacity * 0.9),
        pixel: 3,
      );
    }
  }

  void _paintPlanetTrails(Canvas canvas) {
    for (final planet in planets) {
      for (int i = 0; i < planet.trail.length; i++) {
        final t =
            planet.trail.length == 1 ? 1.0 : i / (planet.trail.length - 1);
        final size = lerpDouble(2, 5.5, t) ?? 3;
        final opacity = lerpDouble(0.08, 0.55, t) ?? 0.2;
        canvas.drawRect(
          Rect.fromCenter(center: planet.trail[i], width: size, height: size),
          Paint()
            ..color = Color.lerp(
              planet.style.accent,
              planet.color,
              0.55,
            )!
                .withOpacity(opacity)
            ..isAntiAlias = false,
        );
      }
    }
  }

  void _paintPlanets(Canvas canvas, Size size, Offset center) {
    for (final planet in planets) {
      final active = planet.index == targetIndex;
      final orbitRadius = _orbitRadiusFor(planet.index, size);
      final position = Offset(
        center.dx + cos(planet.angle) * orbitRadius,
        center.dy + sin(planet.angle) * orbitRadius,
      );

      canvas.drawCircle(
        position,
        active ? 25 : 18,
        Paint()
          ..color = planet.style.accent.withOpacity(active ? 0.30 : 0.15)
          ..maskFilter = MaskFilter.blur(BlurStyle.outer, active ? 18 : 12),
      );

      _drawOrbitPlanet(
        canvas,
        center: position,
        radius: active ? 10 : 8,
        planet: planet,
        active: active,
      );

      if (active) {
        _drawPlanetReticle(
          canvas,
          center: position,
          radius: 15,
          color: planet.style.outline,
          accent: planet.style.accent,
        );
      }
    }
  }

  void _drawOrbitPlanet(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required OrbitPlanet planet,
    required bool active,
  }) {
    final style = planet.style;

    if (style.hasRing) {
      _drawTiltedPixelRing(
        canvas,
        center: center,
        radiusX: radius + 7,
        radiusY: radius * 0.48 + 2,
        rotation: -0.35,
        color: style.ringColor.withOpacity(active ? 0.40 : 0.26),
        pixel: 2.4,
        front: false,
      );
    }

    _drawPlanetSprite(
      canvas,
      center: center,
      radius: radius,
      style: style,
      pixel: 2.0,
      spin: planet.spin,
      active: active,
    );

    if (style.hasMoon) {
      _drawOrbitMoon(
        canvas,
        center: center,
        radius: radius,
        angle: planet.spin + planet.index * 0.9,
        color: style.moonColor,
        active: active,
      );
    }

    if (style.hasRing) {
      _drawTiltedPixelRing(
        canvas,
        center: center,
        radiusX: radius + 7,
        radiusY: radius * 0.48 + 2,
        rotation: -0.35,
        color: style.outline.withOpacity(active ? 0.72 : 0.48),
        pixel: 2.4,
        front: true,
      );
    }

    if (active) {
      _drawPlanetSparkles(
        canvas,
        center: center,
        radius: radius + 9,
        spin: planet.spin,
        color: style.outline,
      );
    }
  }

  void _paintParticles(Canvas canvas) {
    for (final particle in particles) {
      final t = (particle.age / particle.duration).clamp(0.0, 1.0);
      final opacity = 1.0 - t;
      final size = lerpDouble(particle.size, 1.0, t) ?? 1.0;
      canvas.drawRect(
        Rect.fromCenter(center: particle.position, width: size, height: size),
        Paint()
          ..color = particle.color.withOpacity(opacity)
          ..isAntiAlias = false,
      );
    }
  }

  void _paintLives(Canvas canvas, Size size) {
    final bottom = size.height - 42;
    final centerX = size.width / 2;
    for (int i = 0; i < 3; i++) {
      final active = i < lives;
      final position = Offset(centerX + (i - 1) * 28, bottom);
      canvas.drawCircle(
        position,
        8,
        Paint()
          ..color = Colors.white.withOpacity(active ? 0.34 : 0.07)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8),
      );
      canvas.drawRect(
        Rect.fromCenter(center: position, width: 8, height: 8),
        Paint()
          ..color = Colors.white.withOpacity(active ? 0.95 : 0.18)
          ..isAntiAlias = false,
      );
    }
  }

  void _drawPixelRing(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Color color,
    required double pixel,
  }) {
    final steps = max(24, (radius * 0.7).round());
    for (int i = 0; i < steps; i++) {
      final angle = (pi * 2 / steps) * i;
      final point = Offset(
        center.dx + cos(angle) * radius,
        center.dy + sin(angle) * radius,
      );
      canvas.drawRect(
        Rect.fromCenter(center: point, width: pixel, height: pixel),
        Paint()
          ..color = color
          ..isAntiAlias = false,
      );
    }
  }

  void _drawPixelPlanet(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Color base,
    required Color shadow,
    required Color light,
    required double pixel,
  }) {
    final half = radius.ceilToDouble();
    for (double y = -half; y <= half; y += pixel) {
      for (double x = -half; x <= half; x += pixel) {
        final nx = x / radius;
        final ny = y / radius;
        final d2 = nx * nx + ny * ny;
        if (d2 > 1) continue;

        final edge = d2 > 0.78;
        final lightValue = (-nx * 0.72) + (-ny * 0.95);
        Color c = base;

        if (edge) {
          c = shadow;
        } else if (lightValue > 0.72) {
          c = light;
        } else if (lightValue < -0.15) {
          c = Color.lerp(base, shadow, 0.45)!;
        }

        if (d2 < 0.42 && ((x / pixel).round() + (y / pixel).round()) % 5 == 0) {
          c = Color.lerp(c, light, 0.15)!;
        }

        canvas.drawRect(
          Rect.fromLTWH(center.dx + x, center.dy + y, pixel, pixel),
          Paint()
            ..color = c
            ..isAntiAlias = false,
        );
      }
    }
  }

  void _drawPlanetSprite(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required PlanetStyle style,
    required double pixel,
    required double spin,
    required bool active,
  }) {
    final half = radius.ceilToDouble() + pixel;
    final rotation = spin * 0.6;
    final cosR = cos(rotation);
    final sinR = sin(rotation);

    for (double y = -half; y <= half; y += pixel) {
      for (double x = -half; x <= half; x += pixel) {
        final nx = x / radius;
        final ny = y / radius;
        final d2 = nx * nx + ny * ny;
        if (d2 > 1.0) continue;

        final rx = nx * cosR - ny * sinR;
        final ry = nx * sinR + ny * cosR;
        final cellX = (x / pixel).round();
        final cellY = (y / pixel).round();
        final lightValue = (-nx * 0.72) + (-ny * 0.94);

        Color color = style.base;

        if (d2 > 0.84) {
          color = lightValue > 0.25 ? style.outline : style.shadow;
        } else if (lightValue > 0.86) {
          color = style.light;
        } else if (lightValue > 0.50) {
          color = Color.lerp(style.base, style.light, 0.68)!;
        } else if (lightValue < -0.18) {
          color = Color.lerp(style.base, style.shadow, 0.72)!;
        }

        switch (style.pattern) {
          case PlanetPattern.bands:
            final band = ry + sin((rx * 4) + spin * 1.2) * 0.08;
            if ((band > -0.58 && band < -0.26) ||
                (band > 0.02 && band < 0.28)) {
              color = Color.lerp(color, style.accent, 0.62)!;
            }
            break;
          case PlanetPattern.craters:
            final craterA = pow(rx + 0.30, 2) + pow(ry - 0.10, 2);
            final craterB = pow(rx - 0.18, 2) + pow(ry + 0.34, 2);
            final craterC = pow(rx + 0.02, 2) + pow(ry + 0.02, 2);
            if (craterA < 0.070 || craterB < 0.045 || craterC < 0.028) {
              color = Color.lerp(color, style.accent, 0.45)!;
            }
            if (craterA < 0.038 || craterB < 0.022 || craterC < 0.014) {
              color = Color.lerp(color, style.shadow, 0.30)!;
            }
            break;
          case PlanetPattern.core:
            final fissure =
                (rx + ry * 0.42 + sin(spin * 1.1) * 0.05).abs() < 0.08;
            final vertical = (rx - sin(ry * 5 + spin) * 0.08).abs() < 0.10;
            if ((fissure && ry.abs() < 0.88) || (vertical && d2 < 0.56)) {
              color = Color.lerp(color, style.accent, 0.74)!;
            }
            if (d2 < 0.16) color = style.light;
            break;
          case PlanetPattern.storm:
            final wave = ry * 3.2 + sin((rx * 6) - spin * 1.4) * 0.35;
            if (wave > -0.55 && wave < -0.12) {
              color = Color.lerp(color, style.accent, 0.70)!;
            } else if (wave > 0.15 && wave < 0.48) {
              color = Color.lerp(color, style.light, 0.34)!;
            }
            break;
        }

        if ((cellX + cellY + (spin * 5).round()).remainder(5) == 0 &&
            d2 < 0.60) {
          color = Color.lerp(color, style.light, active ? 0.18 : 0.10)!;
        }

        if (active &&
            d2 > 0.52 &&
            d2 < 0.86 &&
            (cellX - cellY).remainder(4) == 0) {
          color = Color.lerp(color, style.outline, 0.20)!;
        }

        canvas.drawRect(
          Rect.fromLTWH(center.dx + x, center.dy + y, pixel, pixel),
          Paint()
            ..color = color
            ..isAntiAlias = false,
        );
      }
    }
  }

  void _drawTiltedPixelRing(
    Canvas canvas, {
    required Offset center,
    required double radiusX,
    required double radiusY,
    required double rotation,
    required Color color,
    required double pixel,
    required bool front,
  }) {
    final steps = max(26, (radiusX * 2.6).round());
    final cosR = cos(rotation);
    final sinR = sin(rotation);

    for (int i = 0; i < steps; i++) {
      final angle = (pi * 2 / steps) * i;
      final y = sin(angle);
      if (front ? y < 0 : y >= 0) continue;

      final local = Offset(cos(angle) * radiusX, y * radiusY);
      final point = center +
          Offset(
            local.dx * cosR - local.dy * sinR,
            local.dx * sinR + local.dy * cosR,
          );

      canvas.drawRect(
        Rect.fromCenter(center: point, width: pixel, height: pixel),
        Paint()
          ..color = color
          ..isAntiAlias = false,
      );
    }
  }

  void _drawOrbitMoon(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required double angle,
    required Color color,
    required bool active,
  }) {
    final moonCenter = center +
        Offset(
          cos(angle) * (radius + 7),
          sin(angle * 0.9) * (radius * 0.60 + 3),
        );

    canvas.drawCircle(
      moonCenter,
      active ? 7 : 5,
      Paint()
        ..color = color.withOpacity(active ? 0.18 : 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8),
    );

    _drawPixelPlanet(
      canvas,
      center: moonCenter,
      radius: active ? 3.2 : 2.6,
      base: color,
      shadow: _darken(color, 0.28),
      light: _lighten(color, 0.12),
      pixel: 1.6,
    );
  }

  void _drawPlanetSparkles(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required double spin,
    required Color color,
  }) {
    final sparkles = [
      Offset(cos(spin) * radius, sin(spin * 0.8) * radius * 0.55),
      Offset(cos(spin + 2.1) * radius * 0.76, sin(spin + 2.1) * radius),
      Offset(
        cos(spin + 4.0) * radius * 0.92,
        sin(spin * 1.2 + 1.1) * radius * 0.62,
      ),
    ];

    for (final sparkle in sparkles) {
      final point = center + sparkle;
      final paint = Paint()
        ..color = color.withOpacity(0.95)
        ..isAntiAlias = false;

      canvas.drawRect(
        Rect.fromCenter(center: point, width: 2.4, height: 2.4),
        paint,
      );
      canvas.drawRect(
        Rect.fromCenter(center: point, width: 6.0, height: 2.0),
        paint,
      );
      canvas.drawRect(
        Rect.fromCenter(center: point, width: 2.0, height: 6.0),
        paint,
      );
    }
  }

  void _drawPlanetReticle(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Color color,
    required Color accent,
  }) {
    final paint = Paint()
      ..color = color.withOpacity(0.92)
      ..isAntiAlias = false;
    final accentPaint = Paint()
      ..color = accent.withOpacity(0.85)
      ..isAntiAlias = false;

    final corners = [
      Offset(-radius, -radius),
      Offset(radius, -radius),
      Offset(-radius, radius),
      Offset(radius, radius),
    ];

    for (final corner in corners) {
      final point = center + corner;
      final horizontalEnd = point.dx + (corner.dx.isNegative ? 6.0 : -6.0);
      final verticalEnd = point.dy + (corner.dy.isNegative ? 6.0 : -6.0);

      canvas.drawRect(
        Rect.fromPoints(point, Offset(horizontalEnd, point.dy + 2)),
        paint,
      );
      canvas.drawRect(
        Rect.fromPoints(point, Offset(point.dx + 2, verticalEnd)),
        paint,
      );
      canvas.drawRect(
        Rect.fromCenter(center: point, width: 2, height: 2),
        accentPaint,
      );
    }
  }

  Color _darken(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  Color _lighten(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  double _orbitRadiusFor(int index, Size size) =>
      min(size.width, size.height) * 0.22 +
      min(size.width, size.height) * 0.105 * index;

  @override
  bool shouldRepaint(covariant TapOrbitPainter oldDelegate) => true;
}

class _PixelPanel extends StatelessWidget {
  const _PixelPanel({
    required this.child,
    required this.borderColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  });

  final Widget child;
  final Color borderColor;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xCC05070D),
        border: Border.all(color: borderColor.withOpacity(0.8), width: 2),
        boxShadow: [
          BoxShadow(
            color: borderColor.withOpacity(0.14),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: child,
    );
  }
}

class OrbitPlanet {
  OrbitPlanet({
    required this.color,
    required this.style,
    required this.angle,
    required this.speed,
    required this.index,
  });

  final Color color;
  final PlanetStyle style;
  double angle;
  double speed;
  final int index;
  double spin = 0;
  final List<Offset> trail = [];
}

enum PlanetPattern { bands, craters, core, storm }

class PlanetStyle {
  const PlanetStyle({
    required this.base,
    required this.shadow,
    required this.light,
    required this.accent,
    required this.outline,
    required this.ringColor,
    required this.moonColor,
    required this.pattern,
    this.hasRing = false,
    this.hasMoon = false,
  });

  final Color base;
  final Color shadow;
  final Color light;
  final Color accent;
  final Color outline;
  final Color ringColor;
  final Color moonColor;
  final PlanetPattern pattern;
  final bool hasRing;
  final bool hasMoon;
}

class TapRipple {
  TapRipple({required this.color, required this.radius});

  final Color color;
  final double radius;
  final double duration = 0.28;
  double age = 0;
}

class HitParticle {
  HitParticle({
    required this.position,
    required this.velocity,
    required this.color,
    required this.duration,
    required this.size,
  });

  Offset position;
  final Offset velocity;
  final Color color;
  final double duration;
  final double size;
  double age = 0;
}

class BackgroundStar {
  BackgroundStar({
    required this.position,
    required this.size,
    required this.baseOpacity,
    required this.phase,
    required this.twinkleSpeed,
    required this.cross,
    required this.driftPhase,
    required this.driftSpeed,
    required this.driftAmplitude,
  });

  final Offset position;
  final double size;
  final double baseOpacity;
  double phase;
  final double twinkleSpeed;
  final bool cross;
  double driftPhase;
  final double driftSpeed;
  final double driftAmplitude;
}

class BackgroundPlanet {
  BackgroundPlanet({
    required this.center,
    required this.radius,
    required this.base,
    required this.shadow,
    required this.light,
    required this.accent,
    required this.outline,
    required this.pixelSize,
    required this.ring,
    required this.moonColor,
    required this.pattern,
    required this.phase,
    required this.pulseSpeed,
    required this.motes,
    this.hasMoon = false,
    this.ringTilt = -0.35,
    this.ringColor,
  });

  final Offset center;
  final double radius;
  final Color base;
  final Color shadow;
  final Color light;
  final Color accent;
  final Color outline;
  final double pixelSize;
  final bool ring;
  final Color moonColor;
  final PlanetPattern pattern;
  final bool hasMoon;
  final double ringTilt;
  final Color? ringColor;
  double phase;
  final double pulseSpeed;
  final List<PlanetMote> motes;
}

class SpaceDustParticle {
  SpaceDustParticle({
    required this.position,
    required this.velocity,
    required this.size,
    required this.opacity,
    required this.phase,
  });

  Offset position;
  final Offset velocity;
  final double size;
  final double opacity;
  double phase;
}

class CometTrail {
  CometTrail({
    required this.position,
    required this.velocity,
    required this.duration,
    required this.size,
    required this.tailLength,
    required this.color,
  });

  Offset position;
  final Offset velocity;
  final double duration;
  final double size;
  final int tailLength;
  final Color color;
  double age = 0;
}

class PlanetMote {
  PlanetMote({
    required this.angle,
    required this.speed,
    required this.distance,
    required this.size,
    required this.phase,
  });

  double angle;
  final double speed;
  final double distance;
  final double size;
  double phase;
}
