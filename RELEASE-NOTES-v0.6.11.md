# CodeWord v0.6.11 — Android release stability and TTS cache fix

This release focuses on making the Android build/release path reproducible and tightening the TTS cache behavior.

## Fixes

- Fixed Flutter analyzer failures on current Dart/Flutter by replacing direct `dart:html` web backend usage with `package:web`.
- Fixed workspace `melos` scripts so `dart run melos run analyze` and `dart run melos run test` no longer require a globally installed `melos` binary.
- Fixed an in-flight TTS cache race where concurrent requests for the same word could trigger duplicate fetches.
- Fixed the Discovery category chip row by giving the horizontal list a bounded height, preventing layout crashes while tabs remain mounted.
- Fixed reading pulse de-duplication so the same word can appear independently across different vocab lists.

## Performance

- TTS cache hits now avoid an extra cache lookup in the native backend.
- Concurrent same-key TTS requests now share one fetch and cached file.

## Verification

- `dart run melos run analyze`
- `dart run melos run test`
- `flutter build web --release`
- `flutter build apk --release`

## Android APK

The attached APK is a Flutter release build. The current Android project still signs release builds with the debug signing config, so it is suitable for direct installation/testing but not Play Store distribution.
