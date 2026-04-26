# Tap Orbit

Tap Orbit is a simple one-finger Flutter mobile game for Android.

Planets orbit a central glowing star. Tap to shoot an expanding ring from the center. Catch the active planet at the right moment to score, build combo, add planets, and increase speed. Misses cost lives.

## Features

- CustomPainter game loop
- Programmatic visuals only
- No image assets
- No game engine
- Central glowing star
- Orbiting neon planets
- Expanding ring shot
- Planet trails
- Hit particles
- Hit and miss screen flashes
- 3 lives
- Score, combo, best combo
- Personal best with shared_preferences
- Portrait-only Android setup

## Run

```bash
flutter pub get
flutter run
```

If Android platform files need to be regenerated locally, run:

```bash
flutter create . --platforms=android
flutter pub get
flutter run
```

## Build APK

```bash
flutter build apk --release
```

The APK will be generated at:

```text
build/app/outputs/flutter-apk/app-release.apk
```
