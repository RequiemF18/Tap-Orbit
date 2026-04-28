import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'beatmap_service.dart';

class AudioService {
  AudioService._();

  static const MethodChannel _channel = MethodChannel('tap_orbit/audio');
  static const String _enabledKey = 'tap_orbit_audio_enabled';
  static const String _musicAsset = 'audio/main_theme.wav';
  static const String _beatmapAsset = 'assets/audio/main_theme.beatmap.json';

  static bool _enabled = true;
  static final AudioPlayer _musicPlayer = AudioPlayer();

  /// Position tracker — polled at ~10Hz, interpolated by frame deltas.
  /// Reading playback position directly from AudioPlayer every frame
  /// is expensive on Android, so we cache + interpolate.
  static final AudioPositionTracker positionTracker =
      AudioPositionTracker(_musicPlayer);

  /// Public accessor for the AudioPlayer powering the background track.
  static AudioPlayer get musicPlayer => _musicPlayer;

  static bool get enabled => _enabled;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? true;
    await _musicPlayer.setReleaseMode(ReleaseMode.loop);
    await _musicPlayer.setVolume(1.0);

    // Load the offline-generated beatmap. Game falls back to procedural
    // BPM if this is missing (no crash).
    await BeatmapService.instance.load(_beatmapAsset);

    if (_enabled) await startMusic();
  }

  static Future<void> toggle() async {
    _enabled = !_enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, _enabled);
    if (_enabled) {
      await startMusic();
      await playTap();
    } else {
      await stopMusic();
    }
  }

  static Future<void> startMusic() async {
    if (!_enabled) return;
    try {
      await _musicPlayer.play(AssetSource(_musicAsset));
      // Reset cursors so beatmap aligns with the fresh playback
      BeatmapService.instance.resetCursor();
      positionTracker.reset();
    } catch (_) {}
  }

  static Future<void> stopMusic() async {
    try {
      await _musicPlayer.stop();
      BeatmapService.instance.resetCursor();
      positionTracker.reset();
    } catch (_) {}
  }

  static Future<void> pauseMusic() async {
    try {
      await _musicPlayer.pause();
    } catch (_) {}
  }

  static Future<void> resumeMusic() async {
    if (!_enabled) return;
    try {
      await _musicPlayer.resume();
    } catch (_) {}
  }

  static Future<void> playTap() async => _play('tap');
  static Future<void> playHit() async => _play('hit');
  static Future<void> playPerfect() async => _play('perfect');
  static Future<void> playMiss() async => _play('miss');
  static Future<void> playCombo() async => _play('combo');
  static Future<void> playGameOver() async => _play('gameOver');

  static Future<void> _play(String sound) async {
    if (!_enabled) return;
    try {
      await _channel.invokeMethod('play', {'sound': sound});
    } catch (_) {
      await SystemSound.play(SystemSoundType.click);
    }
  }
}
