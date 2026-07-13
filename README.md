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

All word data and progress data stays on the device. AI Reading is optional
BYOK: the user's API key is stored with platform-encrypted storage and is sent
only to the provider selected by the user. No developer API key is bundled.

## Release checks

```bash
cd apps/codeword
flutter analyze
flutter test
../../tools/check_release_secrets.sh
```

For a built IPA or AAB, pass the artifact path to
`tools/check_release_secrets.sh` to inspect the archive before upload.
