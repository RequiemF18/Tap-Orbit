#!/usr/bin/env python3
"""
generate_beatmap.py — Tap Orbit beatmap generator

Analyzes the background music WAV and produces a JSON beatmap with:
  - Beat timestamps (ms)
  - Per-beat strength (onset envelope amplitude)
  - Per-beat energy (RMS over the surrounding window)
  - Section boundaries (intro / build / drop / outro), with avg energy

Usage:
    python3 tools/generate_beatmap.py \
        --input assets/audio/main_theme.wav \
        --output assets/audio/main_theme.beatmap.json

Dependencies:
    pip3 install librosa numpy soundfile

Output JSON schema (matches the format expected by BeatmapService):
{
  "track":       "main_theme",
  "bpm":         128.0,
  "offsetMs":    0,
  "durationMs":  120000,
  "beats": [
    { "timeMs": 532, "strength": 0.82, "energy": 0.76, "type": "kick" }
  ],
  "sections": [
    { "startMs": 0, "endMs": 15000, "name": "intro", "energy": 0.4 }
  ]
}
"""

import argparse
import json
import os
import sys
from typing import List, Dict, Any

try:
    import librosa  # type: ignore
    import numpy as np
except ImportError as e:
    sys.stderr.write(
        "ERROR: missing dependency.\n"
        "Install with:  pip3 install librosa numpy soundfile\n"
        f"Original error: {e}\n"
    )
    sys.exit(2)


# ----------------------------------------------------------------------
# Beat & onset analysis
# ----------------------------------------------------------------------
def analyze_beats(y: np.ndarray, sr: int) -> Dict[str, Any]:
    """Detect beats and compute per-beat strength + energy.

    Returns:
        dict with 'tempo', 'beat_times' (ms), 'strengths', 'energies'
    """
    # Beat tracking using onset envelope
    onset_env = librosa.onset.onset_strength(y=y, sr=sr, aggregate=np.median)
    tempo, beat_frames = librosa.beat.beat_track(
        onset_envelope=onset_env, sr=sr, units="frames"
    )
    beat_times_s = librosa.frames_to_time(beat_frames, sr=sr)

    # Strength: onset envelope value at each beat (normalized 0..1)
    if len(onset_env) > 0:
        max_onset = float(np.max(onset_env)) or 1.0
        beat_strengths = onset_env[beat_frames] / max_onset
    else:
        beat_strengths = np.zeros(len(beat_frames))

    # Energy: RMS over a small window centered on each beat
    rms = librosa.feature.rms(y=y, frame_length=2048, hop_length=512)[0]
    rms_max = float(np.max(rms)) or 1.0
    rms_norm = rms / rms_max
    rms_times_s = librosa.frames_to_time(np.arange(len(rms)), sr=sr, hop_length=512)
    beat_energies = []
    for t in beat_times_s:
        idx = int(np.argmin(np.abs(rms_times_s - t)))
        beat_energies.append(float(rms_norm[idx]))

    return {
        "tempo": float(tempo) if np.isscalar(tempo) else float(tempo[0]),
        "beat_times_s": beat_times_s.tolist(),
        "strengths": beat_strengths.tolist(),
        "energies": beat_energies,
    }


def classify_beat_type(strength: float, energy: float) -> str:
    """Heuristic — strong+energetic = kick, mid = snare, low = hat."""
    if strength >= 0.65 and energy >= 0.55:
        return "kick"
    if strength >= 0.40:
        return "snare"
    return "hat"


# ----------------------------------------------------------------------
# Section detection (simple but effective)
# ----------------------------------------------------------------------
def detect_sections(
    y: np.ndarray, sr: int, duration_s: float
) -> List[Dict[str, Any]]:
    """Detect coarse sections (intro/build/drop/outro) using energy windows.

    For an arcade loop track of 1-3 minutes, simple fixed segmentation
    weighted by RMS gives clean and stable results.
    """
    # Compute RMS energy in 1-second windows
    win_seconds = 1.0
    win_samples = int(sr * win_seconds)
    n_windows = max(1, int(duration_s / win_seconds))
    energies = []
    for i in range(n_windows):
        start = i * win_samples
        end = min(start + win_samples, len(y))
        if start >= len(y):
            energies.append(0.0)
            continue
        e = float(np.sqrt(np.mean(y[start:end] ** 2)))
        energies.append(e)
    e_max = max(energies) or 1.0
    energies_norm = [e / e_max for e in energies]

    # Heuristic split: 15% intro, 30% build, 40% drop, 15% outro
    boundaries = [
        ("intro", 0.0, 0.15),
        ("build_up", 0.15, 0.45),
        ("drop", 0.45, 0.85),
        ("outro", 0.85, 1.0),
    ]
    sections = []
    for name, p0, p1 in boundaries:
        start_ms = int(duration_s * 1000 * p0)
        end_ms = int(duration_s * 1000 * p1)
        # Avg energy over this section
        i0 = max(0, int(p0 * n_windows))
        i1 = max(i0 + 1, int(p1 * n_windows))
        avg_e = (
            float(np.mean(energies_norm[i0:i1]))
            if i1 > i0
            else 0.0
        )
        sections.append(
            {
                "startMs": start_ms,
                "endMs": end_ms,
                "name": name,
                "energy": round(avg_e, 3),
            }
        )
    return sections


# ----------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", "-i", required=True, help="Path to WAV/MP3 input")
    ap.add_argument("--output", "-o", required=True, help="Path to JSON output")
    ap.add_argument(
        "--track-name",
        default=None,
        help="Identifier for the track (default: input filename stem)",
    )
    ap.add_argument(
        "--offset-ms",
        type=int,
        default=0,
        help="Manual latency calibration (ms). Subtracted from each beat time.",
    )
    args = ap.parse_args()

    track_name = args.track_name or os.path.splitext(
        os.path.basename(args.input)
    )[0]

    print(f"Loading {args.input} ...")
    y, sr = librosa.load(args.input, sr=None, mono=True)
    duration_s = librosa.get_duration(y=y, sr=sr)
    print(f"  duration = {duration_s:.2f}s, sr = {sr} Hz")

    print("Detecting beats ...")
    info = analyze_beats(y, sr)
    print(f"  tempo = {info['tempo']:.2f} BPM")
    print(f"  beats found = {len(info['beat_times_s'])}")

    print("Detecting sections ...")
    sections = detect_sections(y, sr, duration_s)

    # Build beat list
    beats = []
    for t_s, strength, energy in zip(
        info["beat_times_s"], info["strengths"], info["energies"]
    ):
        time_ms = int(round(t_s * 1000)) - args.offset_ms
        if time_ms < 0:
            continue
        beats.append(
            {
                "timeMs": time_ms,
                "strength": round(float(strength), 3),
                "energy": round(float(energy), 3),
                "type": classify_beat_type(strength, energy),
            }
        )

    out = {
        "track": track_name,
        "bpm": round(info["tempo"], 2),
        "offsetMs": 0,  # runtime calibration goes here
        "durationMs": int(round(duration_s * 1000)),
        "beats": beats,
        "sections": sections,
    }

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(out, f, indent=2)
    print(f"Wrote {args.output}  ({len(beats)} beats, {len(sections)} sections)")


if __name__ == "__main__":
    main()
