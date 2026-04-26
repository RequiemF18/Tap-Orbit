package com.example.tap_orbit

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.sin

class MainActivity : FlutterActivity() {
    private val channelName = "tap_orbit/audio"
    private var enabled = true
    private var runningMusic = false
    private var musicTrack: AudioTrack? = null
    private var musicThread: Thread? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "setEnabled" -> {
                    enabled = call.argument<Boolean>("enabled") ?: true
                    if (!enabled) stopMusic()
                    result.success(null)
                }
                "startMusic" -> {
                    startMusic()
                    result.success(null)
                }
                "stopMusic" -> {
                    stopMusic()
                    result.success(null)
                }
                "play" -> {
                    playSound(call.argument<String>("sound") ?: "tap")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onPause() {
        super.onPause()
        stopMusic()
    }

    override fun onResume() {
        super.onResume()
        if (enabled) startMusic()
    }

    override fun onDestroy() {
        stopMusic()
        super.onDestroy()
    }

    private fun startMusic() {
        if (!enabled || runningMusic) return

        runningMusic = true
        musicThread = Thread {
            val sampleRate = 44100
            val bufferSize = maxOf(
                AudioTrack.getMinBufferSize(sampleRate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT),
                sampleRate / 2
            )
            val track = createTrack(sampleRate, bufferSize)
            musicTrack = track
            track.play()

            val notes = intArrayOf(220, 277, 330, 415, 330, 277, 247, 196)
            val buffer = ShortArray(1024)
            var sampleIndex = 0L

            while (runningMusic) {
                for (i in buffer.indices) {
                    val t = sampleIndex.toDouble() / sampleRate
                    val beat = ((t * 2.0).toInt()) % notes.size
                    val note = notes[beat].toDouble()
                    val pad = sin(2.0 * PI * note * t) * 0.12
                    val octave = sin(2.0 * PI * note * 2.0 * t) * 0.04
                    val bass = sin(2.0 * PI * (note / 2.0) * t) * 0.075
                    val pulse = if (((t * 4.0).toInt() % 2) == 0) 0.025 else 0.0
                    val sample = (pad + octave + bass + pulse) * 0.28
                    buffer[i] = (sample.coerceIn(-1.0, 1.0) * Short.MAX_VALUE).toInt().toShort()
                    sampleIndex++
                }

                try {
                    track.write(buffer, 0, buffer.size)
                } catch (_: Exception) {
                    runningMusic = false
                }
            }

            try {
                track.stop()
                track.release()
            } catch (_: Exception) {}
        }.also { it.start() }
    }

    private fun stopMusic() {
        runningMusic = false
        try {
            musicTrack?.pause()
            musicTrack?.flush()
        } catch (_: Exception) {}
        musicTrack = null
        musicThread = null
    }

    private fun playSound(sound: String) {
        if (!enabled) return
        Thread {
            when (sound) {
                "tap" -> tone(intArrayOf(660), 55, 0.22, Wave.SQUARE)
                "hit" -> tone(intArrayOf(880, 1320), 125, 0.35, Wave.SINE)
                "perfect" -> tone(intArrayOf(990, 1485, 1980), 185, 0.42, Wave.SINE)
                "miss" -> tone(intArrayOf(180, 120), 165, 0.36, Wave.SAW)
                "combo" -> tone(intArrayOf(523, 659, 784, 1046), 230, 0.36, Wave.SQUARE)
                "gameOver" -> tone(intArrayOf(440, 330, 220, 110), 380, 0.40, Wave.SAW)
                else -> tone(intArrayOf(660), 55, 0.22, Wave.SQUARE)
            }
        }.start()
    }

    private enum class Wave { SINE, SQUARE, SAW }

    private fun tone(notes: IntArray, durationMs: Int, volume: Double, wave: Wave) {
        val sampleRate = 44100
        val totalSamples = sampleRate * durationMs / 1000
        val buffer = ShortArray(totalSamples)
        val segment = maxOf(1, totalSamples / notes.size)

        for (i in 0 until totalSamples) {
            val noteIndex = minOf(notes.size - 1, i / segment)
            val freq = notes[noteIndex].toDouble()
            val t = i.toDouble() / sampleRate
            val localT = (i % segment).toDouble() / segment
            val envelope = exp(-4.5 * localT)
            val raw = when (wave) {
                Wave.SINE -> sin(2.0 * PI * freq * t)
                Wave.SQUARE -> if (sin(2.0 * PI * freq * t) >= 0) 1.0 else -1.0
                Wave.SAW -> 2.0 * ((freq * t) - floor(0.5 + freq * t))
            }
            buffer[i] = (raw * envelope * volume * Short.MAX_VALUE)
                .toInt()
                .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                .toShort()
        }

        val track = createTrack(sampleRate, buffer.size * 2)
        try {
            track.play()
            track.write(buffer, 0, buffer.size)
            Thread.sleep(durationMs.toLong() + 20)
            track.stop()
            track.release()
        } catch (_: Exception) {
            try { track.release() } catch (_: Exception) {}
        }
    }

    private fun createTrack(sampleRate: Int, bufferSize: Int): AudioTrack {
        return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_GAME)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(sampleRate)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setBufferSizeInBytes(bufferSize)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
        } else {
            @Suppress("DEPRECATION")
            AudioTrack(
                AudioManager.STREAM_MUSIC,
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize,
                AudioTrack.MODE_STREAM
            )
        }
    }
}
