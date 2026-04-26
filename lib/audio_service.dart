import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioService {
  AudioService._();

  static const MethodChannel _channel = MethodChannel('tap_orbit/audio');
  static const String _enabledKey = 'tap_orbit_audio_enabled';

  static bool _enabled = true;

  static bool get enabled => _enabled;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? true;
    await _safeInvoke('setEnabled', {'enabled': _enabled});
    if (_enabled) {
      await startMusic();
    }
  }

  static Future<void> toggle() async {
    _enabled = !_enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, _enabled);
    await _safeInvoke('setEnabled', {'enabled': _enabled});
    if (_enabled) {
      await startMusic();
      await playTap();
    } else {
      await stopMusic();
    }
  }

  static Future<void> startMusic() async {
    if (!_enabled) return;
    await _safeInvoke('startMusic');
  }

  static Future<void> stopMusic() async {
    await _safeInvoke('stopMusic');
  }

  static Future<void> playTap() async => _play('tap');
  static Future<void> playHit() async => _play('hit');
  static Future<void> playPerfect() async => _play('perfect');
  static Future<void> playMiss() async => _play('miss');
  static Future<void> playCombo() async => _play('combo');
  static Future<void> playGameOver() async => _play('gameOver');

  static Future<void> _play(String sound) async {
    if (!_enabled) return;
    await _safeInvoke('play', {'sound': sound});
  }

  static Future<void> _safeInvoke(String method, [Map<String, Object?>? args]) async {
    try {
      await _channel.invokeMethod(method, args);
    } catch (_) {
      // Audio is optional. Keep gameplay running even if native audio is unavailable.
    }
  }
}
