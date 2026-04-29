import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_service.dart';
import 'beatmap_service.dart';
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
  static const int randomOrbitThreshold = 150;

  // Milestones (score thresholds)
  static const int milestoneDriftScore = 25;
  static const int milestoneFluxScore = 75;
  static const int milestoneStormScore = 150;
  static const int milestoneSingularityScore = 300;

  // Speed system (per plan)
  static const double speedScalePerHit = 0.008;
  static const double speedScalePerMilestone = 0.06;
  static const double speedScaleCap = 2.35;
  static const double planetMaxSpeedBase = 2.25;
  static const double planetMaxSpeedStep = 0.15;

  // Golden target
  static const int goldenScoreThreshold = 100;
  static const double goldenChanceBase = 0.06;
  static const double goldenChanceSingularity = 0.10;
  static const double goldenHitWindowMult = 0.72;
  static const double goldenPerfectWindowMult = 0.70;

  // Last life
  static const int resurrectionStreak = 8;

  // ---------------- Orbit Rush — multi-gate distribution rules ----------------

  /// How far AHEAD of the planet the gate spawns.
  /// Min 1.0 rad (~57°), max 1.85 rad (~106°). Player has 0.5-1.5s to react.
  static const double gateAheadMin = 1.0;
  static const double gateAheadMax = 1.85;

  /// Lifetime of a gate (seconds). Shrinks with milestone tier.
  static const double gateLifetimeBase = 2.6;
  static const double gateLifetimeMin = 1.2;

  /// Recency window — last N spawns we remember when balancing orbit selection.
  /// Higher = stricter rotation across orbits.
  static const int recentSpawnHistorySize = 6;

  /// Hard cap: never allow the same orbit to receive more than this many
  /// CONSECUTIVE spawns even if its weight wins. Forces real rotation.
  static const int maxConsecutiveSpawnsSameOrbit = 2;

  /// How many candidate angles to try when finding a non-overlapping spot.
  static const int gateAngleSearchAttempts = 12;

  // Bonus gates
  static const double bonusGateWidthMult = 0.65;
  static const int bonusGateScoreMult = 3;

  // Music sync (procedural BPM clock — matches the 128 BPM main theme)
  static const double assumedBPM = 128.0;
  static const double secondsPerBeat = 60.0 / assumedBPM;

  // Intro phase
  static const double introDuration = 1.6;

  // Layout safety — reserve space for HUD top and lives/hint bottom
  static const double hudReservedTop = 130;
  static const double hudReservedBottom = 110;
  static const double orbitEdgePadding = 18; // glow + planet halo padding
  static const double orbitInnerRadiusFactor = 0.32; // closest orbit / max

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
  final List<ScorePopup> _popups = [];

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
  double _currentGateAngle = gateAngle;
  String _feedbackText = '';
  Color _feedbackColor = Colors.white;
  bool _gameEnded = false;

  // Milestone progression
  int _milestoneTier = 0; // 0=ORBIT, 1=DRIFT, 2=FLUX, 3=STORM, 4=SINGULARITY
  String _milestoneName = 'ORBIT';
  String _milestoneAnnouncement = '';
  String _milestoneSubtitle = '';
  double _milestoneAge = 999;

  // Last life mechanics
  int _lastLifeStreak = 0;
  String _resurrectionAnnouncement = '';
  double _resurrectionAge = 999;

  // Combo shatter
  double _shatterAge = 999;

  // Gate rotation (STORM / SINGULARITY)
  double _gateRotationSpeed = 0;
  int _gateDirection = 1;
  double _gateDirectionFlipCooldown = 0;

  // Game phase (intro → playing)
  GamePhase _phase = GamePhase.intro;
  double _introAge = 0;

  // BPM beat clock
  double _beatPhase = 0; // 0..1 within current beat
  int _beatCount = 0;

  // Screen shake
  double _shakeAge = 999;
  double _shakeMagnitude = 0;

  // Layout — recomputed on size/safeArea change
  double _maxOrbitRadius = 200;

  // Combo tier-up toast (announces when crossing into Charged/Overdrive/etc.)
  String _comboUnlockText = '';
  String _comboUnlockSubtitle = '';
  double _comboUnlockAge = 999;

  // First-hit dopamine — first 3 hits feel BIGGER
  // Tracks how many hits since reset to enable special feedback for 1,2,3
  // (Same as _totalHits but used here for clarity at the call site)

  // Hit-stop — early-game perfects briefly freeze time for 80ms (game feel)
  double _hitStopRemaining = 0;

  // Demo phantom planet — visible during intro to teach the mechanic visually
  double _demoPlanetAngle = -pi / 2 - 1.2; // starts left of the gate

  // Ignition shockwave (first tap)
  bool _ignitionTriggered = false;

  // ---------------- Orbit Rush — multi-gate state ----------------
  /// All currently active gates across all orbits. Each is independent and
  /// has its own lifetime and angle. Rendered + checked for tap detection.
  final List<Gate> _gates = [];

  /// Last N planet indices we spawned gates on. Used to balance distribution
  /// (penalize over-used orbits, prefer stale ones). Capped at
  /// [recentSpawnHistorySize].
  final List<int> _recentSpawnPlanetIndices = [];

  /// Combo Meter — drains over time, refills on hit. If empties → combo
  /// resets (NO life lost — pressure, not punishment). 0..1.
  double _comboMeter = 1.0;

  /// Anti-spam guard for beat-synced bonus gate spawning.
  double _lastBeatSpawnGuardS = 0;

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
    _currentGateAngle = gateAngle;
    _hintOpacity = 1;
    _feedbackAge = 1;
    _feedbackText = '';
    _feedbackColor = Colors.white;
    _gameEnded = false;
    _milestoneTier = 0;
    _milestoneName = 'ORBIT';
    _milestoneAnnouncement = '';
    _milestoneSubtitle = '';
    _milestoneAge = 999;
    _lastLifeStreak = 0;
    _resurrectionAnnouncement = '';
    _resurrectionAge = 999;
    _shatterAge = 999;
    _gateRotationSpeed = 0;
    _gateDirection = 1;
    _gateDirectionFlipCooldown = 0;
    _phase = GamePhase.intro;
    _introAge = 0;
    _beatPhase = 0;
    _beatCount = 0;
    _shakeAge = 999;
    _shakeMagnitude = 0;
    _popups.clear();
    _comboUnlockText = '';
    _comboUnlockSubtitle = '';
    _comboUnlockAge = 999;
    _hitStopRemaining = 0;
    _demoPlanetAngle = -pi / 2 - 1.2;
    _ignitionTriggered = false;
    _gates.clear();
    _recentSpawnPlanetIndices.clear();
    _comboMeter = 1.0;
    _lastBeatSpawnGuardS = 0;
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
    final baseSpeed = 0.72 + index * 0.12; // per arcade balance plan
    final maxSpeed = planetMaxSpeedBase + index * planetMaxSpeedStep;
    _planets.add(
      OrbitPlanet(
        color: _planetStyles[index].base,
        style: _planetStyles[index],
        angle: _initialAngleForPlanet(index),
        speed: direction * baseSpeed,
        index: index,
        maxSpeed: maxSpeed,
      ),
    );
  }

  double _initialAngleForPlanet(int index) {
    if (index == 0) {
      return _currentGateAngle + (pi * 2) - firstOrbitWarmupLead;
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
    final globalScale = _speedScaleGlobal();

    // Warmup boost only on the very first planet during onboarding
    if (planet.index == 0 && _planets.length == 1) {
      final hitProgress = (_totalHits / warmupHitsToSecondOrbit).clamp(0.0, 1.0);
      final timeProgress = (_clock / 12.0).clamp(0.0, 1.0);
      final progress = max(hitProgress, timeProgress);
      final warmup = lerpDouble(firstOrbitWarmupBoost, 1.0, progress) ?? 1.0;
      return warmup * globalScale;
    }
    return globalScale;
  }

  double _frenzyLevel() => (_score / 320).clamp(0, 1).toDouble();

  // ============================================================
  // Orbit Rush — multi-gate spawn engine (balanced across orbits)
  // ============================================================

  /// Maximum gates allowed simultaneously on a SINGLE orbit. Grows with
  /// difficulty so early game stays clean and readable.
  ///
  /// Score 0-9   → 1 (one barra por órbita)
  /// Score 10-24 → 1 (still strict, just more total)
  /// Score 25-49 → 2 (DRIFT — can stack, but with separation)
  /// Score 50-99 → 2 (FLUX still 2)
  /// Score 100+  → 3 (SINGULARITY — full chaos)
  int _maxGatesPerOrbit() {
    if (_score >= 100) return 3;
    if (_score >= 25) return 2;
    return 1;
  }

  /// Total gates allowed in scene at once. Drives perceived intensity.
  /// Score 0-9   → 1 (one bar visible at a time)
  /// Score 10-24 → 2
  /// Score 25-49 → 3
  /// Score 50+   → 4-5
  int _maxGatesTotal() {
    if (_score >= 100) return 5;
    if (_score >= 50) return 4;
    if (_score >= 25) return 3;
    if (_score >= 10) return 2;
    return 1;
  }

  /// Minimum angular separation (radians) between gates on the SAME orbit.
  /// Higher = cleaner visuals. Never below 30°.
  ///
  /// Score 0-24  → 90°  (1.57 rad) — only ever 1 per orbit anyway
  /// Score 25-49 → 60°  (1.05 rad)
  /// Score 50-99 → 45°  (0.79 rad)
  /// Score 100+  → 35°  (0.61 rad)
  double _minAngularSeparation() {
    if (_score >= 100) return pi / 5.1;     // ~35°
    if (_score >= 50) return pi / 4.0;       // 45°
    if (_score >= 25) return pi / 3.0;       // 60°
    return pi / 2.0;                         // 90°
  }

  /// Wraps an angle to [-pi, pi].
  double _wrapAngleSigned(double a) {
    while (a > pi) a -= 2 * pi;
    while (a < -pi) a += 2 * pi;
    return a;
  }

  /// Lifetime of a freshly spawned gate (seconds). Shrinks with tier.
  double _gateLifetime({bool bonus = false}) {
    final t = (_milestoneTier / 4.0).clamp(0.0, 1.0);
    final base = lerpDouble(gateLifetimeBase, gateLifetimeMin, t)!;
    return bonus ? base * 0.7 : base;
  }

  /// How many of the last N spawns went to a given orbit.
  int _recentSpawnsOn(int planetIndex) {
    return _recentSpawnPlanetIndices.where((i) => i == planetIndex).length;
  }

  /// True if the last [maxConsecutiveSpawnsSameOrbit] spawns ALL went to the
  /// given planetIndex. We force rotation when this happens.
  bool _isOrbitOverused(int planetIndex) {
    if (_recentSpawnPlanetIndices.length < maxConsecutiveSpawnsSameOrbit) {
      return false;
    }
    final tail = _recentSpawnPlanetIndices.sublist(
      _recentSpawnPlanetIndices.length - maxConsecutiveSpawnsSameOrbit,
    );
    return tail.every((i) => i == planetIndex);
  }

  /// Number of currently active gates on the given orbit.
  int _gatesOnOrbit(int planetIndex) =>
      _gates.where((g) => g.planetIndex == planetIndex).length;

  /// Picks a playable orbit for the next gate using a balanced weighted
  /// selection algorithm:
  ///
  ///   1. Filter out planets that already have [_maxGatesPerOrbit] gates
  ///   2. Filter out planets that have hit the consecutive-spawn cap
  ///      (unless they're the only option)
  ///   3. Score each remaining orbit:
  ///      - higher base weight if rarely used recently
  ///      - lower weight if it currently holds many gates
  ///      - small random tiebreaker to avoid robotic patterns
  ///   4. Return the highest-scoring orbit
  ///
  /// Returns null if no orbit can take a new gate right now.
  OrbitPlanet? _chooseSpawnOrbit() {
    if (_planets.isEmpty) return null;

    final perOrbitMax = _maxGatesPerOrbit();
    final eligible = _planets.where((p) {
      return _gatesOnOrbit(p.index) < perOrbitMax;
    }).toList();
    if (eligible.isEmpty) return null;

    // Soft rule: try to skip orbits that just got two consecutive spawns
    var pool = eligible.where((p) => !_isOrbitOverused(p.index)).toList();
    if (pool.isEmpty) pool = eligible;

    // Deterministic weighted score
    double weightFor(OrbitPlanet p) {
      final activeOnP = _gatesOnOrbit(p.index);
      final recentCount = _recentSpawnsOn(p.index);
      // Less weight if currently loaded or recently spawned on
      return -activeOnP * 2.0 - recentCount * 1.2 + _random.nextDouble() * 0.4;
    }

    pool.sort((a, b) => weightFor(b).compareTo(weightFor(a)));
    return pool.first;
  }

  /// Finds an angle on the given orbit that:
  ///   - is AHEAD of the planet (in its direction of travel)
  ///   - keeps [_minAngularSeparation] from every existing gate on that orbit
  /// Returns null if no valid spot is found in [gateAngleSearchAttempts] tries.
  double? _findValidGateAngle(OrbitPlanet planet) {
    final dir = planet.speed >= 0 ? 1.0 : -1.0;
    final minSep = _minAngularSeparation();
    final existing = _gates.where((g) => g.planetIndex == planet.index).toList();

    for (int attempt = 0; attempt < gateAngleSearchAttempts; attempt++) {
      final aheadOffset =
          lerpDouble(gateAheadMin, gateAheadMax, _random.nextDouble())!;
      final candidate = _wrapAngleSigned(planet.angle + dir * aheadOffset);

      final ok = existing
          .every((g) => _angleDistance(candidate, g.angle) >= minSep);
      if (ok) return candidate;
    }
    return null;
  }

  /// Spawns a single gate on a balanced-chosen orbit at a non-overlapping
  /// angle. Respects [_maxGatesTotal]. Returns true if a gate was actually
  /// added.
  bool _spawnGate({GateType type = GateType.normal}) {
    if (_gates.length >= _maxGatesTotal()) return false;

    final orbit = _chooseSpawnOrbit();
    if (orbit == null) return false;

    final angle = _findValidGateAngle(orbit);
    if (angle == null) return false;

    final isBonus = type == GateType.bonus;
    final width = isBonus ? hitWindow * bonusGateWidthMult : hitWindow;

    _gates.add(
      Gate(
        planetIndex: orbit.index,
        angle: angle,
        halfWidth: width,
        lifetime: _gateLifetime(bonus: isBonus),
        color: isBonus ? const Color(0xFFFFD24D) : orbit.color,
        type: type,
      ),
    );

    _recentSpawnPlanetIndices.add(orbit.index);
    while (_recentSpawnPlanetIndices.length > recentSpawnHistorySize) {
      _recentSpawnPlanetIndices.removeAt(0);
    }
    return true;
  }

  /// Per-frame gate engine: ages gates, removes dead ones, tops up to
  /// [_maxGatesTotal], and sprinkles bonus gates on strong music beats.
  void _updateGates(double dt) {
    // 1. Age all gates and collect dead ones
    final dead = <Gate>[];
    for (final g in _gates) {
      g.age += dt;
      if (g.isDead) dead.add(g);
    }

    // 2. Punish letting an active gate expire (combo meter takes a hit)
    for (final d in dead) {
      if (!d.consumed) {
        _comboMeter = max(0, _comboMeter - 0.18);
      }
    }
    _gates.removeWhere(dead.contains);

    // 3. Top up scene to desired total — distributed across orbits
    int safety = 4;
    while (_gates.length < _maxGatesTotal() && safety > 0) {
      if (!_spawnGate()) break;
      safety--;
    }

    // 4. Beat-synced bonus gate (only score >= 8, only on strong snares)
    _lastBeatSpawnGuardS += dt;
    if (_lastBeatSpawnGuardS > 0.9 &&
        _score >= 8 &&
        _random.nextDouble() < 0.35) {
      // Without a real beatmap-loaded service we just gate by interval.
      _spawnGate(type: GateType.bonus);
      _lastBeatSpawnGuardS = 0;
    }
  }

  /// Combo Meter drains over time. If it hits 0 with hitStreak >= 3, the
  /// combo resets (NO life lost — this is pressure, not punishment).
  void _updateComboMeter(double dt) {
    if (_hitStreak == 0) {
      _comboMeter = 0;
      return;
    }
    // Higher tier = faster drain (more pressure)
    final tier = _comboTier();
    final budget = [4.0, 3.2, 2.5, 2.0, 1.6][tier.clamp(0, 4)];
    _comboMeter = max(0, _comboMeter - dt / budget);
    if (_comboMeter <= 0 && _hitStreak >= 3) {
      _hitStreak = 0;
      _comboMeter = 0;
      _flashColor = const Color(0xFFFF8866);
      _flashOpacity = 0.30;
      _feedbackText = 'COMBO LOST';
      _feedbackColor = const Color(0xFFFF8866);
      _feedbackAge = 0;
      HapticFeedback.lightImpact();
    }
  }

  // ---------------- Music sync (real beatmap with fallback) ----------------

  /// Returns 0..1 — spikes on each detected musical beat, decays exponentially.
  /// Uses the real beatmap (librosa-analyzed) when loaded; falls back to
  /// procedural 128 BPM if the JSON is missing.
  double _beatPulse() {
    if (BeatmapService.instance.isLoaded) {
      return BeatmapService.instance.pulse;
    }
    return exp(-3.6 * _beatPhase);
  }

  /// Energy of the current section (intro / build_up / drop / outro).
  /// 0..1, used to modulate ambient effects globally.
  double _sectionEnergy() {
    if (BeatmapService.instance.isLoaded) {
      return BeatmapService.instance.sectionEnergy;
    }
    return 0.5;
  }

  /// Slower oscillation for ambient breathing.
  /// With real beatmap: phase-locked to bars (4 beats); without: procedural.
  double _barBreathing() {
    if (BeatmapService.instance.isLoaded) {
      // Smooth oscillation tied to section energy + the beat clock
      final t = _clock;
      final sectionPulse = 0.5 + 0.5 * sin(t * 0.55);
      return sectionPulse * (0.6 + _sectionEnergy() * 0.4);
    }
    return 0.5 + 0.5 * sin(2 * pi * (_beatCount % 4 + _beatPhase) / 4);
  }

  // ---------------- Intro phase ----------------

  /// 0..1 progress of the intro animation (eased).
  double _introProgressEased() {
    final t = (_introAge / introDuration).clamp(0.0, 1.0);
    // Smoothstep
    return t * t * (3 - 2 * t);
  }

  // ---------------- Screen shake ----------------

  void _triggerShake(double magnitude) {
    if (magnitude > _shakeMagnitude || _shakeAge > 0.15) {
      _shakeMagnitude = magnitude;
      _shakeAge = 0;
    }
  }

  /// Returns current shake offset to apply to the canvas.
  Offset _shakeOffset() {
    if (_shakeAge >= 0.45) return Offset.zero;
    final t = (_shakeAge / 0.45).clamp(0.0, 1.0);
    final amp = _shakeMagnitude * (1.0 - t);
    // Pseudo-random offset using time + age
    final ax = sin(_clock * 71 + _shakeAge * 130) * amp;
    final ay = cos(_clock * 53 + _shakeAge * 110) * amp;
    return Offset(ax, ay);
  }

  // ---------------- Layout (orbits never overflow) ----------------

  /// Recompute the maximum orbit radius from current safe area + reserved HUD.
  /// Guarantees that even the outermost orbit + planet glow fits inside the
  /// visible play area on any screen.
  void _recomputeOrbitLayout(Size size, EdgeInsets safeArea) {
    final reservedTop = safeArea.top + hudReservedTop;
    final reservedBottom = safeArea.bottom + hudReservedBottom;
    final availableHeight =
        max(120.0, size.height - reservedTop - reservedBottom);
    final availableWidth = max(120.0, size.width - 2 * orbitEdgePadding);
    final maxByHeight = availableHeight / 2;
    final maxByWidth = availableWidth / 2;
    _maxOrbitRadius =
        max(80.0, min(maxByHeight, maxByWidth) - orbitEdgePadding);
  }

  // ---------------- Arcade balance plan helpers ----------------

  int _comboTier() {
    if (_hitStreak >= 21) return 4;
    if (_hitStreak >= 13) return 3;
    if (_hitStreak >= 7) return 2;
    if (_hitStreak >= 3) return 1;
    return 0;
  }

  int _comboMultiplier() {
    switch (_comboTier()) {
      case 4:
        return 5;
      case 3:
        return 4;
      case 2:
        return 3;
      case 1:
        return 2;
      default:
        return 1;
    }
  }

  String _comboTierName() {
    switch (_comboTier()) {
      case 4:
        return 'MAX ORBIT';
      case 3:
        return 'HYPER';
      case 2:
        return 'OVERDRIVE';
      case 1:
        return 'CHARGED';
      default:
        return 'STABLE';
    }
  }

  Color _comboTierColor(Color planetColor) {
    switch (_comboTier()) {
      case 4:
        return const Color(0xFFFFD24D); // gold
      case 3:
        return const Color(0xFFFF66E0); // hyper magenta
      case 2:
        return const Color(0xFFFF9A2E); // overdrive orange
      case 1:
        return planetColor;
      default:
        return Colors.white70;
    }
  }

  bool get _adrenalineActive => _comboTier() >= 3;
  bool get _isLastLife => _lives == 1 && !_gameEnded;

  int _computeMilestoneTier() {
    if (_score >= milestoneSingularityScore) return 4;
    if (_score >= milestoneStormScore) return 3;
    if (_score >= milestoneFluxScore) return 2;
    if (_score >= milestoneDriftScore) return 1;
    return 0;
  }

  String _milestoneNameForTier(int tier) {
    switch (tier) {
      case 4:
        return 'SINGULARITY';
      case 3:
        return 'STORM';
      case 2:
        return 'FLUX';
      case 1:
        return 'DRIFT';
      default:
        return 'ORBIT';
    }
  }

  String _milestoneSubtitleForTier(int tier) {
    switch (tier) {
      case 4:
        return 'GATE GOES WILD';
      case 3:
        return 'GATE IS ROTATING';
      case 2:
        return 'GATE GOES DIAGONAL';
      case 1:
        return 'GATE IS SHIFTING';
      default:
        return '';
    }
  }

  double _speedScaleGlobal() {
    final raw =
        1.0 + _totalHits * speedScalePerHit + _milestoneTier * speedScalePerMilestone;
    return min(speedScaleCap, raw);
  }

  double _goldenChance() {
    if (_score < goldenScoreThreshold) return 0;
    return _milestoneTier >= 4 ? goldenChanceSingularity : goldenChanceBase;
  }

  double _currentHitWindow() {
    if (_planets.isEmpty) return hitWindow;
    final target = _planets[_targetIndex.clamp(0, _planets.length - 1)];
    return target.isGolden ? hitWindow * goldenHitWindowMult : hitWindow;
  }

  double _currentPerfectWindow() {
    if (_planets.isEmpty) return perfectWindow;
    final target = _planets[_targetIndex.clamp(0, _planets.length - 1)];
    return target.isGolden
        ? perfectWindow * goldenPerfectWindowMult
        : perfectWindow;
  }

  void _maybeMakeTargetGolden() {
    if (_planets.isEmpty) return;
    final chance = _goldenChance();
    if (chance <= 0) return;
    if (_random.nextDouble() >= chance) return;
    final target = _planets[_targetIndex.clamp(0, _planets.length - 1)];
    if (target.isGolden) return;
    target.isGolden = true;
    target.goldenStartAngle = target.angle;
    target.goldenAccumulatedTravel = 0;
  }

  void _resetGolden(OrbitPlanet planet) {
    planet.isGolden = false;
    planet.goldenAccumulatedTravel = 0;
  }

  void _checkMilestoneCrossing() {
    final newTier = _computeMilestoneTier();
    if (newTier == _milestoneTier) return;
    _milestoneTier = newTier;
    _milestoneName = _milestoneNameForTier(newTier);

    // Configure gate behavior for the new tier
    switch (newTier) {
      case 0:
        _gateRotationSpeed = 0;
        break;
      case 1:
      case 2:
        _gateRotationSpeed = 0; // changes via _nextGateAngle on each hit
        break;
      case 3:
        _gateRotationSpeed = 0.32; // slow rotation
        break;
      case 4:
        _gateRotationSpeed = 0.55; // faster + can flip
        break;
    }

    if (newTier > 0) {
      _milestoneAnnouncement = 'ENTERING $_milestoneName';
      _milestoneSubtitle = _milestoneSubtitleForTier(newTier);
      _milestoneAge = 0;
      _flashColor = Colors.white;
      _flashOpacity = 0.55;
      _gatePulse = 1.0;
    }
  }

  double _nextCometCooldown() {
    final frenzy = _frenzyLevel();
    final minCooldown = lerpDouble(2.2, 0.48, frenzy) ?? 1.0;
    final maxCooldown = lerpDouble(4.2, 1.15, frenzy) ?? 2.0;
    return minCooldown +
        _random.nextDouble() * max(0.15, maxCooldown - minCooldown);
  }

  int _cometsPerBurst() {
    if (_score >= 320) return 4;
    if (_score >= 220) return 3;
    if (_score >= 120) return 2;
    return 1;
  }

  int _maxTrailPoints() => 8 + (_frenzyLevel() * 7).round();

  int _nextTargetIndex() {
    if (_planets.isEmpty) return 0;
    if (_score < randomOrbitThreshold || _planets.length <= 1) {
      return (_targetIndex + 1) % _planets.length;
    }

    final candidates = List.generate(_planets.length, (i) => i)
      ..remove(_targetIndex);
    if (candidates.isEmpty) return _targetIndex;
    return candidates[_random.nextInt(candidates.length)];
  }

  double _nextGateAngle() {
    // ORBIT (tier 0) — fixed top
    if (_milestoneTier == 0) return gateAngle;

    // STORM / SINGULARITY — gate is rotating; keep current angle
    // (rotation is updated continuously in _tick)
    if (_milestoneTier >= 3) return _currentGateAngle;

    // DRIFT (tier 1) — cardinal + smooth shifts
    // FLUX  (tier 2) — diagonals included
    final candidates = _milestoneTier == 1
        ? const <double>[
            -pi / 2, // top
            0, // right
            pi / 2, // bottom
            pi, // left
            -pi / 4,
            pi / 4,
            -3 * pi / 4,
            3 * pi / 4,
          ]
        : const <double>[
            -pi / 4,
            -pi / 2,
            -3 * pi / 4,
            pi / 4,
            pi / 2,
            3 * pi / 4,
            0,
            pi,
            -2.2,
            2.2,
          ];

    var next = candidates[_random.nextInt(candidates.length)];
    int attempts = 0;
    while (_angleDistance(next, _currentGateAngle) < 0.45 && attempts < 6) {
      next = candidates[_random.nextInt(candidates.length)];
      attempts++;
    }
    return next;
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
      _shakeAge += dt;

      // Advance the beat clock.
      // Primary path: beatmap-driven sync against actual audio playback.
      // Fallback: procedural 128 BPM clock (same behavior as before).
      if (BeatmapService.instance.isLoaded) {
        // Cheap interpolated polling — refreshes every ~100ms,
        // interpolated on every frame in between.
        AudioService.positionTracker.tick(dt);
        BeatmapService.instance.tick(
          dt,
          AudioService.positionTracker.currentPositionMs,
        );
      } else {
        _beatPhase += dt / secondsPerBeat;
        while (_beatPhase >= 1.0) {
          _beatPhase -= 1.0;
          _beatCount++;
        }
      }

      // Intro phase advances the introAge; auto-finish when complete.
      if (_phase == GamePhase.intro) {
        _introAge += dt;
        if (_introAge >= introDuration) {
          _phase = GamePhase.playing;
        }
      }

      // Hit-stop — early-game perfect freezes time briefly for impact feel
      double effectiveDt = dt;
      if (_hitStopRemaining > 0) {
        _hitStopRemaining = max(0, _hitStopRemaining - dt);
        effectiveDt = dt * 0.15; // simulate freeze without skipping the tick
      }

      _updateAmbient(effectiveDt);
      _updatePlanets(effectiveDt);
      _updateParticles(effectiveDt);
      _updateRipples(effectiveDt);
      _updatePopups(effectiveDt);
      // Orbit Rush — gate engine + combo meter (only during active play)
      if (_phase == GamePhase.playing && !_gameEnded) {
        _updateGates(effectiveDt);
        _updateComboMeter(effectiveDt);
      }
      _comboUnlockAge += dt;

      // Demo phantom planet animates during intro to teach the mechanic
      if (_phase == GamePhase.intro) {
        _demoPlanetAngle += 1.7 * dt;
      }
      _flashOpacity = max(0, _flashOpacity - dt / 0.20);
      _comboPulse = max(0, _comboPulse - dt / 0.28);
      _gatePulse = max(0, _gatePulse - dt / 0.22);
      _feedbackAge += dt;
      _milestoneAge += dt;
      _resurrectionAge += dt;
      _shatterAge += dt;

      // STORM / SINGULARITY: continuously rotate the gate
      if (_milestoneTier >= 3 && _gateRotationSpeed > 0) {
        _currentGateAngle += _gateRotationSpeed * _gateDirection * dt;
        // Wrap to keep within sane range
        if (_currentGateAngle > pi) _currentGateAngle -= pi * 2;
        if (_currentGateAngle < -pi) _currentGateAngle += pi * 2;

        // SINGULARITY: occasional direction flip
        if (_milestoneTier >= 4) {
          _gateDirectionFlipCooldown -= dt;
          if (_gateDirectionFlipCooldown <= 0) {
            _gateDirection *= -1;
            _gateDirectionFlipCooldown = 4.0 + _random.nextDouble() * 4.0;
          }
        }
      }

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
      for (int i = 0; i < _cometsPerBurst(); i++) {
        _spawnComet();
      }
      _cometCooldown = _nextCometCooldown();
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
    final frenzy = _frenzyLevel();
    final speed = 420 + _random.nextDouble() * 240 + frenzy * 220;

    _comets.add(
      CometTrail(
        position: start,
        velocity: direction * speed,
        duration: 0.9 + _random.nextDouble() * 0.35 - frenzy * 0.18,
        size: 3.0 + _random.nextDouble() * 1.8 + frenzy * 0.8,
        tailLength: 12 + _random.nextInt(9) + (frenzy * 8).round(),
        color: _random.nextDouble() > 0.45
            ? Colors.white
            : const Color(0xFF9EEBFF),
      ),
    );
  }

  void _updatePlanets(double dt) {
    for (final planet in _planets) {
      final speedMultiplier = _orbitSpeedMultiplierFor(planet);
      var effectiveSpeed = planet.speed * speedMultiplier;
      // Cap to maxSpeed (preserve sign)
      if (effectiveSpeed.abs() > planet.maxSpeed) {
        effectiveSpeed = planet.maxSpeed * effectiveSpeed.sign;
      }

      final delta = effectiveSpeed * dt;
      planet.angle += delta;

      // Track golden orbit revolution; revert after one full orbit
      if (planet.isGolden) {
        planet.goldenAccumulatedTravel += delta.abs();
        if (planet.goldenAccumulatedTravel >= pi * 2) {
          _resetGolden(planet);
        }
      }

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
        if (planet.trail.length > _maxTrailPoints()) planet.trail.removeAt(0);
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

  void _updatePopups(double dt) {
    final dead = <ScorePopup>[];
    for (final pop in _popups) {
      pop.age += dt;
      pop.position = Offset(pop.position.dx, pop.position.dy - 60 * dt);
      if (pop.age >= ScorePopup.duration) dead.add(pop);
    }
    _popups.removeWhere(dead.contains);
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

    // Skip intro on first tap — empower the player from the get-go.
    // Big ignition shockwave, screen flash, gate pulse, haptic bump.
    if (_phase == GamePhase.intro) {
      setState(() {
        _phase = GamePhase.playing;
        _introAge = introDuration;
        _gatePulse = 1.0;
        _flashOpacity = 0.42;
        _flashColor = Colors.white;
        _ignitionTriggered = true;
        // Spawn a big ripple from the center for visual punch
        if (_screenSize != Size.zero) {
          _ripples.add(
            TapRipple(
              color: const Color(0xFF56E7FF),
              radius: _maxOrbitRadius * 1.6,
            ),
          );
        }
      });
      _triggerShake(6.5);
      HapticFeedback.mediumImpact();
      AudioService.playTap();
      AudioService.playPerfect();
      return;
    }

    HapticFeedback.selectionClick();
    AudioService.playTap();

    final center = _screenSize.center(Offset.zero);

    // Orbit Rush: scan ALL gates on ALL orbits, not just the "target" one.
    // Pick the gate whose planet is currently inside it (closest if multiple).
    Gate? hitGate;
    OrbitPlanet? hitPlanet;
    double bestDist = double.infinity;
    for (final g in _gates) {
      if (g.planetIndex < 0 || g.planetIndex >= _planets.length) continue;
      final p = _planets[g.planetIndex];
      final d = _angleDistance(p.angle, g.angle);
      if (d <= g.halfWidth && d < bestDist) {
        hitGate = g;
        hitPlanet = p;
        bestDist = d;
      }
    }

    if (hitGate != null && hitPlanet != null) {
      final radius = _orbitRadiusFor(hitPlanet.index, _screenSize);
      final gatePosition = Offset(
        center.dx + cos(hitGate.angle) * radius,
        center.dy + sin(hitGate.angle) * radius,
      );
      _ripples.add(TapRipple(color: hitGate.color, radius: radius));
      _gatePulse = 1.0;
      // Update visual focus (HUD color) to follow where the action happened
      _targetIndex = hitPlanet.index;
      // Perfect threshold scales with bonus gates (stricter)
      final perfectAbs = perfectWindow * (hitGate.isBonus ? 0.7 : 1.0);
      final isPerfect = bestDist <= perfectAbs;
      hitGate.consumed = true;
      _gates.remove(hitGate);
      _handleHit(hitPlanet, isPerfect, gatePosition, gateHit: hitGate);
    } else {
      // True miss — no gate was hit
      final fallback = _planets[_targetIndex.clamp(0, _planets.length - 1)];
      final radius = _orbitRadiusFor(fallback.index, _screenSize);
      _ripples.add(TapRipple(color: fallback.color, radius: radius));
      _gatePulse = 1.0;
      _handleMiss('MISS', fallback.color);
    }
  }

  void _handleHit(
    OrbitPlanet planet,
    bool perfect,
    Offset impact, {
    Gate? gateHit,
  }) {
    final wasGolden = planet.isGolden;
    final wasBonus = gateHit?.isBonus ?? false;
    final tierBefore = _comboTier();

    _totalHits++;
    _hitStreak++;
    _bestCombo = max(_bestCombo, _hitStreak);

    // Refill the combo meter on every successful hit (Orbit Rush pressure)
    _comboMeter = 1.0;

    // ----- Scoring -----
    // base = mult ; perfect = base + 1 ; golden = base * 3 ;
    // bonus gate = base * 3 ; last life = +1
    final mult = _comboMultiplier();
    int gain = mult;
    if (perfect) gain += 1;
    if (wasGolden) gain *= 3;
    if (wasBonus) gain *= bonusGateScoreMult;
    if (_isLastLife) gain += 1;
    _score += gain;

    // ----- Golden cleanup -----
    if (wasGolden) {
      _resetGolden(planet);
      _feedbackText = 'GOLDEN!';
      _feedbackColor = const Color(0xFFFFD24D);
      _spawnBurst(
        impact,
        const Color(0xFFFFD24D),
        38,
        outwardPower: 220,
      );
      _flashColor = const Color(0xFFFFE48A);
      _flashOpacity = 0.55;
      _triggerShake(8.0);
    } else if (wasBonus) {
      _feedbackText = 'BONUS!';
      _feedbackColor = const Color(0xFFFFD24D);
      _flashColor = const Color(0xFFFFE48A);
      _flashOpacity = 0.55;
      _spawnBurst(
        impact,
        const Color(0xFFFFD24D),
        38,
        outwardPower: 220,
      );
      _triggerShake(7.0);
    } else {
      _feedbackText = perfect ? 'PERFECT' : 'NICE';
      _feedbackColor = planet.color;
      _flashColor = Colors.white;
      _flashOpacity = perfect ? 0.38 : 0.26;
      _spawnBurst(
        impact,
        planet.color,
        perfect ? 30 : 20,
        outwardPower: perfect ? 190 : 145,
      );
      _triggerShake(perfect ? 4.5 : 2.0);
    }
    _feedbackAge = 0;

    // ----- Audio -----
    if (wasGolden) {
      AudioService.playPerfect();
      AudioService.playCombo();
    } else if (perfect) {
      AudioService.playPerfect();
    } else {
      AudioService.playHit();
    }
    final tierAfter = _comboTier();
    if (tierAfter > tierBefore) {
      AudioService.playCombo();
      _comboPulse = 1.0;
      // Announce combo tier-up — dopamine ladder
      _comboUnlockText = 'COMBO x${_comboMultiplier()}';
      _comboUnlockSubtitle = _comboTierName();
      _comboUnlockAge = 0;
      HapticFeedback.mediumImpact();
    } else if (perfect || wasGolden) {
      _comboPulse = 1.0;
    }

    // Floating "+N" popup at impact — visceral score feedback every hit
    _popups.add(
      ScorePopup(
        position: impact,
        value: gain,
        color: (wasGolden || wasBonus)
            ? const Color(0xFFFFD24D)
            : planet.color,
        golden: wasGolden || wasBonus,
      ),
    );

    // Haptic feedback layers
    if (wasGolden) {
      HapticFeedback.heavyImpact();
    } else if (perfect) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }

    // Hit-stop on perfect during early game (first 10 hits) — tactile impact
    if (perfect && _totalHits <= 10) {
      _hitStopRemaining = 0.08;
    }

    // ----- Last life resurrection -----
    if (_isLastLife) {
      _lastLifeStreak++;
      if (_lastLifeStreak >= resurrectionStreak && _lives < maxLives) {
        _lives++;
        _lastLifeStreak = 0;
        _resurrectionAnnouncement = 'RESURRECTION';
        _resurrectionAge = 0;
        _flashColor = const Color(0xFFFFE48A);
        _flashOpacity = 0.78;
        _triggerShake(10.0);
        AudioService.playCombo();
        AudioService.playPerfect();
        _spawnBurst(
          impact,
          const Color(0xFFFFD24D),
          50,
          outwardPower: 260,
        );
      }
    } else {
      _lastLifeStreak = 0;
    }

    // ----- Milestone crossing detection -----
    _checkMilestoneCrossing();

    // ----- Spawning new orbits -----
    if (_totalHits >= _hitsNeededForNextOrbit()) _addPlanet();

    // Orbit Rush: top up gates immediately so the player NEVER waits.
    // _updateGates will also handle this on the next frame, but doing it
    // here avoids any visible gap.
    int safety = 3;
    while (_gates.length < _maxGatesTotal() && safety > 0) {
      if (!_spawnGate()) break;
      safety--;
    }

    _maybeMakeTargetGolden();
  }

  void _handleMiss(String message, Color color) {
    AudioService.playMiss();
    final brokenTier = _comboTier();
    final shatter = brokenTier >= 2; // Overdrive (x3) or higher
    _hitStreak = 0;
    _lives--;
    _flashColor = shatter ? const Color(0xFFFF3B5C) : Colors.red;
    _flashOpacity = shatter ? 0.66 : 0.40;
    _feedbackText = shatter ? 'COMBO SHATTER' : message;
    _feedbackColor = shatter ? const Color(0xFFFF6680) : Colors.redAccent;
    _feedbackAge = 0;
    if (shatter) {
      _shatterAge = 0;
      _triggerShake(12.0);
      HapticFeedback.heavyImpact();
      AudioService.playGameOver();
    } else {
      _triggerShake(5.0);
      HapticFeedback.mediumImpact();
    }
    if (_screenSize != Size.zero) {
      _spawnBurst(
        _screenSize.center(Offset.zero),
        shatter ? const Color(0xFFFF6680) : color.withOpacity(0.8),
        shatter ? 30 : 12,
        outwardPower: shatter ? 200 : 105,
      );
    }
    if (_lives <= 0) {
      _endGame();
    } else if (_lives == 1) {
      _lastLifeStreak = 0;
    }
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
    // Distribute orbits between innerRadius and _maxOrbitRadius.
    // Outermost (index = maxPlanets-1) sits exactly on _maxOrbitRadius —
    // this ensures the orbit never overflows the safe play area.
    final inner = _maxOrbitRadius * orbitInnerRadiusFactor;
    if (maxPlanets <= 1) return _maxOrbitRadius;
    final step = (_maxOrbitRadius - inner) / (maxPlanets - 1);
    return inner + step * index;
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
    final feedbackVisible = _feedbackAge < 0.65;
    final activeColor = _planets.isEmpty
        ? Colors.cyanAccent
        : _planets[_targetIndex.clamp(0, _planets.length - 1)].color;
    final comboColor = _comboTierColor(activeColor);
    final comboMult = _comboMultiplier();
    final comboTierName = _comboTierName();
    final milestoneVisible = _milestoneAge < 1.7;
    final milestoneOpacity = milestoneVisible
        ? (1.0 - (_milestoneAge / 1.7).clamp(0.0, 1.0)).clamp(0.0, 1.0)
        : 0.0;
    final resurrectionVisible = _resurrectionAge < 1.5;
    final resurrectionOpacity = resurrectionVisible
        ? (1.0 - (_resurrectionAge / 1.5).clamp(0.0, 1.0)).clamp(0.0, 1.0)
        : 0.0;
    final comboUnlockVisible = _comboUnlockAge < 1.0;
    final comboUnlockOpacity = comboUnlockVisible
        ? (1.0 - (_comboUnlockAge / 1.0).clamp(0.0, 1.0)).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final newSize = Size(constraints.maxWidth, constraints.maxHeight);
          _screenSize = newSize;
          final safeArea = MediaQuery.of(context).padding;
          _recomputeOrbitLayout(newSize, safeArea);
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
                    gateAngle: _currentGateAngle,
                    hitWindow: _currentHitWindow(),
                    perfectWindow: _currentPerfectWindow(),
                    gatePulse: _gatePulse,
                    time: _clock,
                    frenzy: _frenzyLevel(),
                    adrenalineActive: _adrenalineActive,
                    lastLifeActive: _isLastLife,
                    shatterAge: _shatterAge,
                    maxOrbitRadius: _maxOrbitRadius,
                    beatPulse: _beatPulse(),
                    barBreathing: _barBreathing(),
                    introProgress: _introProgressEased(),
                    isIntro: _phase == GamePhase.intro,
                    shakeOffset: _shakeOffset(),
                    popups: _popups,
                    demoPlanetAngle: _demoPlanetAngle,
                    gates: _gates,
                    comboMeter: _comboMeter,
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
                              borderColor: comboColor,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'COMBO x$comboMult  $_hitStreak',
                                    style: TextStyle(
                                      color: comboColor,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.8,
                                      shadows: [
                                        Shadow(
                                          color: comboColor,
                                          blurRadius: 16,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_comboTier() >= 1) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      comboTierName,
                                      style: TextStyle(
                                        color: comboColor.withOpacity(0.85),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 2.2,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Combo Meter bar — drains over time, refills on hit.
                        // Visible pressure feedback: keeps the player moving.
                        const SizedBox(height: 6),
                        AnimatedOpacity(
                          opacity: comboActive ? 1 : 0,
                          duration: const Duration(milliseconds: 140),
                          child: SizedBox(
                            width: 180,
                            height: 6,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: Stack(
                                children: [
                                  Container(color: Colors.white12),
                                  FractionallySizedBox(
                                    widthFactor: _comboMeter.clamp(0.0, 1.0),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: comboColor,
                                        boxShadow: [
                                          BoxShadow(
                                            color: comboColor.withOpacity(0.6),
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        AnimatedOpacity(
                          opacity: 1,
                          duration: const Duration(milliseconds: 200),
                          child: _PixelPanel(
                            borderColor: Colors.white24,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            child: Text(
                              _milestoneName,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.4,
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
                if (milestoneOpacity > 0)
                  IgnorePointer(
                    child: Center(
                      child: Opacity(
                        opacity: milestoneOpacity,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _milestoneAnnouncement,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 38,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 4.0,
                                shadows: [
                                  Shadow(
                                    color: Colors.cyanAccent,
                                    blurRadius: 28,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _milestoneSubtitle,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 3.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (comboUnlockOpacity > 0)
                  IgnorePointer(
                    child: Align(
                      alignment: const Alignment(0, -0.35),
                      child: Opacity(
                        opacity: comboUnlockOpacity,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _comboUnlockText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 3.0,
                                shadows: [
                                  Shadow(
                                    color: Colors.cyanAccent,
                                    blurRadius: 22,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _comboUnlockSubtitle,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 3.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (resurrectionOpacity > 0)
                  IgnorePointer(
                    child: Center(
                      child: Opacity(
                        opacity: resurrectionOpacity,
                        child: Text(
                          _resurrectionAnnouncement,
                          style: const TextStyle(
                            color: Color(0xFFFFE48A),
                            fontSize: 46,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4.0,
                            shadows: [
                              Shadow(
                                color: Color(0xFFFFD24D),
                                blurRadius: 32,
                              ),
                            ],
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
    required this.frenzy,
    required this.adrenalineActive,
    required this.lastLifeActive,
    required this.shatterAge,
    required this.maxOrbitRadius,
    required this.beatPulse,
    required this.barBreathing,
    required this.introProgress,
    required this.isIntro,
    required this.shakeOffset,
    required this.popups,
    required this.demoPlanetAngle,
    required this.gates,
    required this.comboMeter,
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
  final double frenzy;
  final bool adrenalineActive;
  final bool lastLifeActive;
  final double shatterAge;
  final double maxOrbitRadius;
  final double beatPulse;
  final double barBreathing;
  final double introProgress;
  final bool isIntro;
  final Offset shakeOffset;
  final List<ScorePopup> popups;
  final double demoPlanetAngle;
  final List<Gate> gates;
  final double comboMeter;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);

    // Background NEVER shakes (would break the world feel) — paint first.
    _paintBackground(canvas, size);
    _paintSpaceDust(canvas);
    _paintBackgroundPlanets(canvas);
    _paintStars(canvas);
    _paintComets(canvas);

    // Apply screen shake to the playfield only.
    canvas.save();
    canvas.translate(shakeOffset.dx, shakeOffset.dy);

    _paintOrbitGates(canvas, size, center);
    _paintCenterStar(canvas, center, size);
    _paintRipples(canvas, center);
    _paintPlanetTrails(canvas);
    _paintPlanets(canvas, size, center);
    _paintParticles(canvas);

    canvas.restore();

    _paintScorePopups(canvas);
    _paintLives(canvas, size);
    _paintVignettes(canvas, size);
    _paintIntroOverlay(canvas, size, center);

    if (flashOpacity > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = flashColor.withOpacity(flashOpacity),
      );
    }
  }

  void _paintScorePopups(Canvas canvas) {
    for (final pop in popups) {
      final t = (pop.age / ScorePopup.duration).clamp(0.0, 1.0);
      final opacity = (1.0 - t).clamp(0.0, 1.0);
      // Pop-in scale: quick burst then settle
      final scale = t < 0.18
          ? lerpDouble(1.6, 1.0, t / 0.18) ?? 1.0
          : 1.0;
      final fontSize = (pop.golden ? 22.0 : 17.0) * scale;
      final tp = TextPainter(
        text: TextSpan(
          text: '+${pop.value}',
          style: TextStyle(
            color: pop.color.withOpacity(opacity),
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            shadows: [
              Shadow(
                color: pop.color.withOpacity(opacity),
                blurRadius: pop.golden ? 16 : 10,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(pop.position.dx - tp.width / 2, pop.position.dy - tp.height / 2),
      );
    }
  }

  void _paintIntroOverlay(Canvas canvas, Size size, Offset center) {
    if (introProgress >= 1.0) return;

    // Demo phantom planet — orbits the first ring teaching the mechanic.
    // Brightens when crossing the gate so the player understands "tap there".
    final demoOpacity = (introProgress * 1.3).clamp(0.0, 1.0);
    final demoRadius = maxOrbitRadius * 0.32;
    final demoPos = Offset(
      center.dx + cos(demoPlanetAngle) * demoRadius,
      center.dy + sin(demoPlanetAngle) * demoRadius,
    );
    final atGate = (cos(demoPlanetAngle - (-pi / 2))).clamp(-1.0, 1.0);
    final near = ((atGate + 1) / 2 * 1.1).clamp(0.0, 1.0);
    canvas.drawCircle(
      demoPos,
      14 + near * 4,
      Paint()
        ..color = const Color(0xFF56E7FF).withOpacity(0.20 * demoOpacity * near)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 14),
    );
    canvas.drawCircle(
      demoPos,
      6 + near * 2,
      Paint()..color = const Color(0xFF56E7FF).withOpacity(0.85 * demoOpacity),
    );
    canvas.drawCircle(
      demoPos,
      3,
      Paint()..color = Colors.white.withOpacity(0.95 * demoOpacity),
    );

    final t = introProgress;
    // Full-screen radial pulse — emanates from the star
    final pulseRadius =
        lerpDouble(0, max(size.width, size.height), t) ?? 0;
    final pulseOpacity = (1.0 - t) * 0.55;
    canvas.drawCircle(
      center,
      pulseRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF56E7FF).withOpacity(pulseOpacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 12),
    );

    // Title fade in/out: 0..0.45 fade in, 0.45..0.85 hold, 0.85..1 fade out
    double titleOpacity;
    if (t < 0.45) {
      titleOpacity = t / 0.45;
    } else if (t < 0.85) {
      titleOpacity = 1.0;
    } else {
      titleOpacity = 1.0 - (t - 0.85) / 0.15;
    }
    titleOpacity = titleOpacity.clamp(0.0, 1.0);

    final titlePainter = TextPainter(
      text: TextSpan(
        text: 'TAP ORBIT',
        style: TextStyle(
          color: Colors.white.withOpacity(titleOpacity),
          fontSize: 48,
          fontWeight: FontWeight.w900,
          letterSpacing: 6,
          shadows: [
            Shadow(
              color: const Color(0xFF56E7FF).withOpacity(titleOpacity),
              blurRadius: 28,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    titlePainter.paint(
      canvas,
      Offset(
        center.dx - titlePainter.width / 2,
        center.dy + maxOrbitRadius + 40,
      ),
    );

    // Subtitle "TAP TO BEGIN" appears in the second half
    if (t > 0.55) {
      final subOpacity = ((t - 0.55) / 0.30).clamp(0.0, 1.0);
      final breath = 0.65 + 0.35 * sin(time * 4.5);
      final subPainter = TextPainter(
        text: TextSpan(
          text: 'TAP TO BEGIN',
          style: TextStyle(
            color: Colors.white.withOpacity(subOpacity * breath),
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 4.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      subPainter.paint(
        canvas,
        Offset(
          center.dx - subPainter.width / 2,
          center.dy + maxOrbitRadius + 96,
        ),
      );
    }
  }

  void _paintVignettes(Canvas canvas, Size size) {
    Color? vignetteColor;
    double intensity = 0;

    if (lastLifeActive) {
      final pulse = 0.6 + 0.4 * sin(time * 4.5);
      vignetteColor = const Color(0xFFFF1A2A);
      intensity = 0.34 * pulse;
    } else if (adrenalineActive && planets.isNotEmpty) {
      final activeColor =
          planets[targetIndex.clamp(0, planets.length - 1)].color;
      final pulse = 0.7 + 0.3 * sin(time * 5.5);
      vignetteColor = activeColor;
      intensity = 0.22 * pulse;
    }

    if (vignetteColor != null && intensity > 0) {
      final rect = Offset.zero & size;
      final radial = RadialGradient(
        colors: [
          vignetteColor.withOpacity(0),
          vignetteColor.withOpacity(intensity),
        ],
        stops: const [0.55, 1.0],
      );
      canvas.drawRect(
        rect,
        Paint()..shader = radial.createShader(rect),
      );
    }

    // Combo shatter — quick red full-screen flash that fades out
    if (shatterAge < 0.45) {
      final t = (shatterAge / 0.45).clamp(0.0, 1.0);
      final shatterAlpha = (1.0 - t) * 0.42;
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFFFF3B5C).withOpacity(shatterAlpha),
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
    // 1. Paint all orbit rings (with beat pulse) for ALL planets
    for (final planet in planets) {
      final active = planet.index == targetIndex;
      final radius = _orbitRadiusFor(planet.index, size);
      final color = planet.color;

      final beatBoost = 0.05 * beatPulse;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = active ? 1.5 : 0.8
          ..color = color.withOpacity(
            (active ? 0.20 : 0.08) + beatBoost,
          ),
      );
    }

    // 2. Paint every active Orbit Rush gate on its own orbit
    for (final gate in gates) {
      if (gate.planetIndex < 0 || gate.planetIndex >= planets.length) continue;
      final planet = planets[gate.planetIndex];
      final radius = _orbitRadiusFor(gate.planetIndex, size);
      _paintSingleGate(canvas, center, radius, gate, planet);
    }
  }

  /// Renders one Orbit Rush gate with lifetime fade + bonus styling +
  /// "incoming planet" approach glow.
  void _paintSingleGate(
    Canvas canvas,
    Offset center,
    double radius,
    Gate gate,
    OrbitPlanet planet,
  ) {
    final isFocus = gate.planetIndex == targetIndex;
    final remaining = gate.lifeRemaining;
    final urgency = 1.0 - remaining; // 0 fresh, 1 about to die

    // Approach (planet → gate)
    var rawDistance = (planet.angle - gate.angle).abs() % (pi * 2);
    if (rawDistance > pi) rawDistance = pi * 2 - rawDistance;
    final approach = (1.0 - (rawDistance / 0.9)).clamp(0.0, 1.0);
    final eased = approach * approach * (3 - 2 * approach);

    final color = gate.color;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Outer glow halo — pulses with beat + planet approach + focus
    final haloAlpha = (0.10 +
            eased * 0.10 +
            (isFocus ? gatePulse * 0.10 : 0) +
            beatPulse * 0.05) *
        (0.45 + remaining * 0.55);
    final haloWidth =
        12 + (isFocus ? gatePulse * 6 : 0) + beatPulse * 2 + (gate.isBonus ? 2 : 0);
    canvas.drawArc(
      rect,
      gate.angle - gate.halfWidth,
      gate.halfWidth * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = haloWidth
        ..color = color.withOpacity(haloAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 12),
    );

    // Main band — thicker for bonus, fades with urgency
    final bandWidth = (gate.isBonus ? 5.5 : 4.5) * (0.6 + remaining * 0.4);
    final bandOpacity = ((gate.isBonus ? 0.85 : 0.62) * (0.5 + remaining * 0.5) +
            eased * 0.20)
        .clamp(0.0, 1.0);
    canvas.drawArc(
      rect,
      gate.angle - gate.halfWidth,
      gate.halfWidth * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = bandWidth
        ..color = color.withOpacity(bandOpacity),
    );

    // Perfect zone (white sliver) on focused gate
    if (isFocus) {
      final perfectAbs =
          (perfectWindow * (gate.isBonus ? 0.7 : 1.0)).clamp(0.02, gate.halfWidth);
      canvas.drawArc(
        rect,
        gate.angle - perfectAbs,
        perfectAbs * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2.2
          ..color = Colors.white.withOpacity(0.85 * (0.5 + remaining * 0.5)),
      );
    }

    // Boundary ticks — subtle radial marks at the gate edges
    final tickColor = color.withOpacity(remaining);
    _drawBoundaryTick(canvas, center, radius, gate.angle - gate.halfWidth, tickColor);
    _drawBoundaryTick(canvas, center, radius, gate.angle + gate.halfWidth, tickColor);

    // Bonus shimmer
    if (gate.isBonus) {
      final spark = sin(time * 9 + gate.age * 4) * 0.5 + 0.5;
      final cx = center.dx + cos(gate.angle) * radius;
      final cy = center.dy + sin(gate.angle) * radius;
      canvas.drawCircle(
        Offset(cx, cy),
        3.0 + spark * 1.5,
        Paint()..color = Colors.white.withOpacity(0.9 * remaining),
      );
    }

    // Urgency warning when nearly dead
    if (urgency > 0.7) {
      final warn = (urgency - 0.7) / 0.3;
      canvas.drawArc(
        rect,
        gate.angle - gate.halfWidth,
        gate.halfWidth * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 8
          ..color = const Color(0xFFFF6680).withOpacity(0.35 * warn)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8),
      );
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
    // Beat-synced pulse: spike on each beat, breathing on each bar.
    // The star "breathes" with the music (procedural BPM clock).
    final beatBoost = 1.0 + beatPulse * 0.18;
    final breath = 1.0 + (barBreathing - 0.5) * 0.06;
    final sunPulse = beatBoost * breath +
        sin(time * (2.6 + frenzy * 2.0)) * 0.03;

    // Intro: the star "ignites" — grows from 0 with bounce.
    final introScale = isIntro
        ? Curves.elasticOut.transform(introProgress)
        : 1.0;

    final coreRadius =
        min(size.width, size.height) * (0.04 + frenzy * 0.005) *
            sunPulse *
            introScale;
    final sunStyle = PlanetStyle(
      base: const Color(0xFFFFB347),
      shadow: const Color(0xFFB85E00),
      light: const Color(0xFFFFF2A0),
      accent: const Color(0xFFFF7A47),
      outline: const Color(0xFFFFF6CF),
      ringColor: const Color(0xFFFFD97A),
      moonColor: const Color(0xFFFFF2C2),
      pattern: PlanetPattern.storm,
    );

    canvas.drawCircle(
      center,
      coreRadius * (3.8 + frenzy * 0.9),
      Paint()
        ..color = Colors.white.withOpacity(0.12 + frenzy * 0.05)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 26),
    );
    canvas.drawCircle(
      center,
      coreRadius * (2.5 + frenzy * 0.4),
      Paint()
        ..color = sunStyle.accent.withOpacity(0.18 + frenzy * 0.09)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 22),
    );

    _drawSolarCorona(
      canvas,
      center: center,
      radius: coreRadius * 1.35,
      color: sunStyle.base,
      outline: sunStyle.outline,
    );
    _drawSolarFlares(
      canvas,
      center: center,
      radius: coreRadius * (1.62 + frenzy * 0.22),
      color: sunStyle.accent,
      outline: sunStyle.outline,
    );
    _drawSolarFlares(
      canvas,
      center: center,
      radius: coreRadius * (1.98 + frenzy * 0.30),
      color: sunStyle.base,
      outline: sunStyle.accent,
      rotationOffset: pi / 10,
      alphaScale: 0.62,
    );

    _drawPlanetSprite(
      canvas,
      center: center,
      radius: coreRadius * 1.08,
      style: sunStyle,
      pixel: 3,
      spin: time * (0.48 + frenzy * 0.35),
      active: true,
    );
  }

  void _drawSolarCorona(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Color color,
    required Color outline,
  }) {
    const spikes = 18;
    for (int i = 0; i < spikes; i++) {
      final angle = time * 0.18 + (pi * 2 / spikes) * i;
      final pulse = sin(time * 2.4 + i * 0.55) * 0.5 + 0.5;
      final distance = radius + pulse * (2.4 + frenzy * 2.2);
      final point =
          center + Offset(cos(angle) * distance, sin(angle) * distance);
      final size = 2.0 + pulse * 1.2 + frenzy * 0.35;

      canvas.drawRect(
        Rect.fromCenter(center: point, width: size, height: size),
        Paint()
          ..color = outline.withOpacity(0.72)
          ..isAntiAlias = false,
      );
      canvas.drawRect(
        Rect.fromCenter(
          center: center +
              Offset(
                cos(angle) * (distance - size * 0.9),
                sin(angle) * (distance - size * 0.9),
              ),
          width: size * 0.9,
          height: size * 0.9,
        ),
        Paint()
          ..color = color.withOpacity(0.88)
          ..isAntiAlias = false,
      );
    }
  }

  void _drawSolarFlares(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Color color,
    required Color outline,
    double rotationOffset = 0,
    double alphaScale = 1,
  }) {
    const tongues = 10;
    for (int i = 0; i < tongues; i++) {
      final angle = time * 0.42 + rotationOffset + (pi * 2 / tongues) * i;
      final pulse = sin(time * 2.15 + i * 0.9) * 0.5 + 0.5;
      final direction = Offset(cos(angle), sin(angle));
      final tangent = Offset(-direction.dy, direction.dx);
      final length = 5.5 + pulse * 6.0 + frenzy * 5.0;
      final segments = 4 + (pulse * 3).round() + (frenzy * 2).round();

      for (int segment = 0; segment < segments; segment++) {
        final t = segments == 1 ? 1.0 : segment / (segments - 1);
        final distance = radius + t * length;
        final sway = sin(time * 3.2 + i * 0.7 + segment * 0.8) *
            (1.6 + frenzy * 1.8) *
            (1 - t);
        final point = center + direction * distance + tangent * sway;
        final size = lerpDouble(4.2 + frenzy, 1.2, t) ?? 2.0;
        final offsetPoint = point + tangent * (segment.isEven ? 0.0 : 0.9);

        canvas.drawRect(
          Rect.fromCenter(center: offsetPoint, width: size, height: size),
          Paint()
            ..color = outline.withOpacity((0.58 + pulse * 0.16) * alphaScale)
            ..isAntiAlias = false,
        );
        canvas.drawRect(
          Rect.fromCenter(
            center: point - direction * (size * 0.18),
            width: size * 0.72,
            height: size * 0.72,
          ),
          Paint()
            ..color = color.withOpacity((0.82 - t * 0.18) * alphaScale)
            ..isAntiAlias = false,
        );
      }
    }
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

      // Golden aura — strong glow + sparkles
      if (planet.isGolden) {
        final pulse = 0.55 + 0.45 * sin(time * 8.0);
        canvas.drawCircle(
          position,
          32,
          Paint()
            ..color = const Color(0xFFFFD24D).withOpacity(0.55 * pulse)
            ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 22),
        );
        canvas.drawCircle(
          position,
          22,
          Paint()
            ..color = const Color(0xFFFFE48A).withOpacity(0.60)
            ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 12),
        );
      }

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

      // Golden overlay tint on top of the sprite
      if (planet.isGolden) {
        canvas.drawCircle(
          position,
          12,
          Paint()
            ..color = const Color(0xFFFFD24D).withOpacity(0.42)
            ..blendMode = BlendMode.srcOver,
        );
        // Sparkle ring around it
        for (int i = 0; i < 4; i++) {
          final sparkAngle = time * 3.5 + i * pi / 2;
          final sparkPos = position +
              Offset(cos(sparkAngle), sin(sparkAngle)) * 18;
          canvas.drawRect(
            Rect.fromCenter(center: sparkPos, width: 3, height: 3),
            Paint()
              ..color = const Color(0xFFFFE48A)
              ..isAntiAlias = false,
          );
        }
      }

      if (active) {
        _drawPlanetReticle(
          canvas,
          center: position,
          radius: 15,
          color: planet.isGolden
              ? const Color(0xFFFFE48A)
              : planet.style.outline,
          accent: planet.isGolden
              ? const Color(0xFFFFD24D)
              : planet.style.accent,
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

  double _orbitRadiusFor(int index, Size size) {
    // Mirrors the state-side formula. Distributes orbits between
    // inner = 32% of max and the safe-area-aware max.
    const innerFactor = 0.32;
    const maxOrbits = 4;
    final inner = maxOrbitRadius * innerFactor;
    if (maxOrbits <= 1) return maxOrbitRadius;
    final step = (maxOrbitRadius - inner) / (maxOrbits - 1);
    return inner + step * index;
  }

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
    required this.maxSpeed,
  });

  final Color color;
  final PlanetStyle style;
  double angle;
  double speed; // signed base speed (sign = direction). Effective speed computed in _updatePlanets.
  final int index;
  final double maxSpeed; // absolute cap on effective speed
  double spin = 0;
  final List<Offset> trail = [];

  // Golden target state
  bool isGolden = false;
  double goldenStartAngle = 0;
  double goldenAccumulatedTravel = 0;
}

enum PlanetPattern { bands, craters, core, storm }

enum GamePhase { intro, playing, gameOver }

enum GateType { normal, bonus }

/// One Orbit Rush gate — a finite-lifetime hit zone bound to a specific
/// orbit/planet. Multiple gates can coexist on the same orbit (separated
/// by [`_GameScreenState._minAngularSeparation`]) or on different orbits.
class Gate {
  Gate({
    required this.planetIndex,
    required this.angle,
    required this.halfWidth,
    required this.lifetime,
    required this.color,
    this.type = GateType.normal,
  });

  final int planetIndex;
  double angle;
  final double halfWidth;
  final double lifetime;
  double age = 0;
  final GateType type;
  Color color;
  bool consumed = false;

  /// 1.0 fresh → 0.0 about to die.
  double get lifeRemaining =>
      (1.0 - (age / lifetime).clamp(0.0, 1.0)).clamp(0.0, 1.0);

  bool get isDead => age >= lifetime || consumed;
  bool get isBonus => type == GateType.bonus;
}

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

/// Floating "+N" toast that pops from the impact and floats up while fading.
/// Provides per-hit visual scoring feedback so the player FEELS the points.
class ScorePopup {
  ScorePopup({
    required this.position,
    required this.value,
    required this.color,
    this.golden = false,
  });

  Offset position;
  final int value;
  final Color color;
  final bool golden;
  double age = 0;
  static const double duration = 0.85;
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
