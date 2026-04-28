import 'dart:convert';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// One-beat record loaded from the JSON beatmap.
class Beat {
  const Beat({
    required this.timeMs,
    required this.strength,
    required this.energy,
    required this.type,
  });

  final int timeMs;
  final double strength;
  final double energy;
  final String type; // "kick" | "snare" | "hat"

  factory Beat.fromJson(Map<String, dynamic> j) => Beat(
        timeMs: j['timeMs'] as int,
        strength: (j['strength'] as num).toDouble(),
        energy: (j['energy'] as num).toDouble(),
        type: j['type'] as String? ?? 'kick',
      );
}

/// Coarse section descriptor (intro / build_up / drop / outro).
class Section {
  const Section({
    required this.startMs,
    required this.endMs,
    required this.name,
    required this.energy,
  });

  final int startMs;
  final int endMs;
  final String name;
  final double energy;

  factory Section.fromJson(Map<String, dynamic> j) => Section(
        startMs: j['startMs'] as int,
        endMs: j['endMs'] as int,
        name: j['name'] as String,
        energy: (j['energy'] as num).toDouble(),
      );
}

/// Loads a JSON beatmap produced by `tools/generate_beatmap.py` and
/// drives a runtime "beat clock" synchronized with the actual audio.
///
/// Architecture:
///   - The beatmap is loaded once from assets via [load].
///   - Every frame, [tick] is called with the AudioPlayer's current
///     playback position. The service detects beat crossings and
///     decays a pulse value that game visuals can read via [pulse].
///   - Latency calibration: see [latencyOffsetMs] (-200..+200 typical).
///
/// Why preprocessed beatmap (Option A) instead of real-time FFT:
///   * Flutter has NO stable plugin to read the live decoded buffer of
///     an AudioPlayer instance — only mic capture (`flutter_audio_capture`)
///     or plugin-specific APIs that break across versions.
///   * Real-time FFT in Dart per-frame burns battery and risks dropped
///     frames on mid-range Android.
///   * librosa offline analysis is sub-frame accurate, deterministic
///     across runs, and lets us hand-tune the data if needed.
class BeatmapService {
  BeatmapService._();

  static final BeatmapService instance = BeatmapService._();

  // ------------------------------------------------------------------
  // Configuration
  // ------------------------------------------------------------------

  /// Latency calibration. Positive = visuals fire EARLIER (audio is late).
  /// Negative = visuals fire LATER (audio is early).
  ///
  /// Typical Android values to try: 0, -50, -80, +30, +60.
  /// Recommended starting value: 0 (tweak from there).
  ///
  /// Edit this constant to adjust globally, OR use [setLatencyOffsetMs].
  int latencyOffsetMs = 0;

  /// Decay rate of the pulse after a beat fires. Higher = sharper pulse.
  /// 6.0 is a clean "thump"; 4.0 is a softer breath.
  double pulseDecayRate = 5.5;

  // ------------------------------------------------------------------
  // Loaded data
  // ------------------------------------------------------------------

  bool _loaded = false;
  bool get isLoaded => _loaded;

  String _track = '';
  double _bpm = 0;
  int _beatmapOffsetMs = 0;
  int _durationMs = 0;
  List<Beat> _beats = const [];
  List<Section> _sections = const [];

  String get track => _track;
  double get bpm => _bpm;
  int get durationMs => _durationMs;
  List<Beat> get beats => _beats;
  List<Section> get sections => _sections;

  // ------------------------------------------------------------------
  // Runtime state (advanced by [tick])
  // ------------------------------------------------------------------

  int _currentPositionMs = 0;
  int _nextBeatIndex = 0;
  Beat? _lastFiredBeat;
  double _timeSinceLastBeatS = 9999;
  double _lastBeatStrength = 0;
  double _lastBeatEnergy = 0;
  String _lastBeatType = 'kick';
  Section? _currentSection;

  /// 0..~1 — spikes to ~1 on each beat, decays exponentially.
  /// Modulated by the beat's strength so soft hats give a soft pulse.
  double get pulse {
    if (!_loaded || _timeSinceLastBeatS > 2.0) return 0;
    return _lastBeatStrength * exp(-pulseDecayRate * _timeSinceLastBeatS);
  }

  /// Energy of the last beat (0..1) — useful for size/scale modulations.
  double get lastBeatEnergy => _lastBeatEnergy;

  /// Type of the last beat: "kick" | "snare" | "hat".
  String get lastBeatType => _lastBeatType;

  /// Section currently playing (intro/build_up/drop/outro).
  Section? get currentSection => _currentSection;

  /// Average energy of the current section (0..1).
  double get sectionEnergy => _currentSection?.energy ?? 0.5;

  /// Distance (s) to the nearest beat — useful for "almost on beat" effects.
  double timeToNextBeatS() {
    if (!_loaded || _nextBeatIndex >= _beats.length) return 9999;
    final nextMs = _beats[_nextBeatIndex].timeMs - latencyOffsetMs;
    return (nextMs - _currentPositionMs) / 1000.0;
  }

  // ------------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------------

  Future<void> load(String assetPath) async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _track = j['track'] as String? ?? '';
      _bpm = (j['bpm'] as num?)?.toDouble() ?? 128.0;
      _beatmapOffsetMs = j['offsetMs'] as int? ?? 0;
      _durationMs = j['durationMs'] as int? ?? 0;
      _beats = (j['beats'] as List<dynamic>)
          .map((e) => Beat.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
      _sections = (j['sections'] as List<dynamic>)
          .map((e) => Section.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
      _loaded = true;
    } catch (_) {
      // Beatmap missing or invalid — service stays disabled, game uses
      // procedural fallback. No crash.
      _loaded = false;
    }
  }

  /// Reset playback cursor (call when music restarts, e.g. on game reset
  /// after the loop wraps around).
  void resetCursor() {
    _nextBeatIndex = 0;
    _lastFiredBeat = null;
    _timeSinceLastBeatS = 9999;
  }

  /// Drive the beat clock from the audio player's current position.
  ///
  /// Call once per frame from the game ticker. [dt] is the frame delta in
  /// seconds. [audioPositionMs] is the position fetched from the
  /// AudioPlayer (cached from a periodic poll — don't call getCurrentPosition
  /// on every frame; poll every ~100ms and interpolate with dt).
  void tick(double dt, int audioPositionMs) {
    _timeSinceLastBeatS += dt;
    if (!_loaded) return;

    final adjustedPosMs = audioPositionMs - _beatmapOffsetMs;
    _currentPositionMs = adjustedPosMs;

    // Detect playback rewind/loop: if position regressed, reset cursor
    if (_lastFiredBeat != null &&
        adjustedPosMs + 200 < _lastFiredBeat!.timeMs - latencyOffsetMs) {
      resetCursor();
    }

    // Fire all beats whose adjusted time has passed
    while (_nextBeatIndex < _beats.length) {
      final b = _beats[_nextBeatIndex];
      final fireTime = b.timeMs - latencyOffsetMs;
      if (adjustedPosMs >= fireTime) {
        _onBeatFired(b);
        _nextBeatIndex++;
      } else {
        break;
      }
    }

    // Update current section
    _currentSection = _findSectionAt(adjustedPosMs);
  }

  void _onBeatFired(Beat b) {
    _lastFiredBeat = b;
    _timeSinceLastBeatS = 0;
    _lastBeatStrength = b.strength;
    _lastBeatEnergy = b.energy;
    _lastBeatType = b.type;
  }

  Section? _findSectionAt(int positionMs) {
    for (final s in _sections) {
      if (positionMs >= s.startMs && positionMs < s.endMs) return s;
    }
    return _sections.isNotEmpty ? _sections.last : null;
  }

  /// Set latency offset at runtime (e.g. from a calibration screen).
  /// Stored for the lifetime of the process; persist via SharedPreferences
  /// at the call site if you want it sticky.
  void setLatencyOffsetMs(int ms) {
    latencyOffsetMs = ms;
  }
}

/// Helper to safely poll an AudioPlayer's position without spamming it.
/// Pulls a fresh position every [pollIntervalMs] and interpolates the rest
/// of the time using local frame deltas — keeps us frame-accurate without
/// hammering the audio plugin.
class AudioPositionTracker {
  AudioPositionTracker(this._player, {this.pollIntervalMs = 100});

  final AudioPlayer _player;
  final int pollIntervalMs;

  int _lastPolledMs = 0;
  double _msSinceLastPoll = 0;
  bool _polling = false;

  int get currentPositionMs =>
      _lastPolledMs + _msSinceLastPoll.round();

  Future<void> tick(double dt) async {
    _msSinceLastPoll += dt * 1000;
    if (_msSinceLastPoll < pollIntervalMs || _polling) return;
    _polling = true;
    try {
      final pos = await _player.getCurrentPosition();
      if (pos != null) {
        _lastPolledMs = pos.inMilliseconds;
        _msSinceLastPoll = 0;
      }
    } catch (_) {
      // ignore
    } finally {
      _polling = false;
    }
  }

  void reset() {
    _lastPolledMs = 0;
    _msSinceLastPoll = 0;
  }
}
