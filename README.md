SDK 3.4+ / Flutter 3.24+

Use Melos 7 to manage the workspace:

```bash
dart pub global activate melos
melos bootstrap
melos run build:macos
```

## Layout

- `apps/codeword` — Flutter app (macOS + Android)
- `packages/lib_core` — domain models, SM-2 algorithm
- `packages/lib_ui` — v5 design tokens & shared widgets
- `packages/lib_content` — built-in vocabulary content
- `packages/lib_sync` — 6-digit sync + E2E encryption
