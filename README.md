SDK 3.4+ / Flutter 3.24+

Use Melos 7 to manage the workspace:

```bash
dart pub global activate melos
melos bootstrap
melos run build:macos
```

## Layout

- `apps/codeword` — Flutter app (macOS + Android)
- `packages/lib_core` — domain models, SM-2 algorithm, local review-state repo
- `packages/lib_ui` — v5 design tokens & shared widgets
- `packages/lib_content` — built-in vocabulary content

## Principle

**Local-first, no cloud, no login, no sync.**

All word data and progress data stays on the device. AI features
(planned) are BYOK — the user's API key is stored locally with
platform-encrypted storage (Keychain on macOS, EncryptedSharedPreferences
on Android) and never leaves the device.
