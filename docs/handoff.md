# Handoff: codeword × qwerty-learner integration

**Codebase:** `/Users/bytedance/github/codeword` (Flutter monorepo, melos 7)
**Status at handoff:** macOS debug build running, all 3 melos checks pass.
**Audience:** a fresh agent. The user is the same one from the previous session; the
project is codeword — a local-first vocab-learner for coders.

---

## TL;DR

We replaced codeword's 9 hand-curated programmer-vocab lists (~500 words) with
**all 371 lists / 411,730 words** from `RealKai42/qwerty-learner`, plus
**on-demand Youdao dictvoice audio** with on-disk caching. Old assets and the
`flutter_tts` dep are wiped. The macOS app boots, the home screen renders, the
learning session works, and the catalog grid is browsable.

The user iteratively steered:
1. Replace 60+ lists; online Youdao audio with on-disk cache (violating the
   project's "no cloud" principle — they explicitly OK'd this for audio).
2. "Ignore all legacy baggage" — delete every old artifact, no
   backward-compat shims.
3. Catch UI issues from screenshots and fix them.

Multiple self-audit rounds happened. The final implementation went through
2 audit passes plus 4 screenshot-driven fix rounds.

---

## What's in the repo right now

### Project layout (relevant paths)

```
codeword/
├── melos.yaml            # DELETED — moved to root pubspec.yaml (melos 7 requires)
├── pubspec.yaml          # NEW: root workspace + melos scripts
├── .gitignore            # added: tools/_qwerty_src/
├── docs/
│   └── handoff.md        # this file
├── tools/
│   ├── _qwerty_src/      # qwerty-learner clone (gitignored, build artifact)
│   └── import_qwerty_dict.py   # conversion script
├── apps/codeword/
│   ├── pubspec.yaml      # removed flutter_tts, added crypto
│   ├── macos/Runner/
│   │   ├── DebugProfile.entitlements   # added network.client
│   │   └── Release.entitlements        # added network.client
│   ├── assets/
│   │   ├── vocab/        # 372 JSONs (~121 MB): _qwerty_index.json + qwerty_*.json
│   │   └── audio/        # DELETED
│   └── lib/
│       ├── main.dart                                 # await loadQwertyCatalog; inject via override
│       ├── services/
│       │   ├── tts_service.dart          # 2-step: cache → Youdao (8s timeout, content-type check)
│       │   ├── tts_cache.dart            # sha1 keys, 100MB LRU, in-flight dedup
│       │   └── qwerty_tts_resolver.dart  # Youdao URL builder
│       ├── screens/
│       │   ├── learning_session_screen.dart   # stateful AskingView/WrongDetailView; auto-play on listen
│       │   ├── discovery_screen.dart           # search + category-filtered catalog grid
│       │   ├── reading_screen.dart             # _vocabNameFor() function removed
│       │   ├── settings_screen.dart            # profile, AI config, storage
│       │   └── stats_widgets.dart              # qwertyPalette
│       └── state/learning_session.dart        # many changes
└── packages/
    ├── lib_core/lib/src/
    │   ├── models/
    │   │   ├── vocab_word.dart     # +translations: List<String>
    │   │   └── vocab_list.dart     # +category: String
    │   └── review_repository.dart  # schemaVersion=2 gate
    ├── lib_content/lib/src/
    │   └── catalog.dart            # ONLY loadQwertyCatalog + ContentLoader.loadList
    └── lib_ui/lib/src/
        └── tokens.dart             # 9 AppColors.domain* removed, +qwertyPalette[8]
```

### Removed artifacts

- 9 old vocab JSONs (`{cs,python,ai,llm,web,devops,data,security,product}_core.json`)
- 500 pre-generated OGGs (`assets/audio/{cs,py,ai,...}_NNN.ogg`)
- `tools/generate_audio.py` (espeak+ffmpeg pipeline)
- `melos.yaml` (moved into root `pubspec.yaml`)
- `kBuiltinLists`, `kBuiltinVocabIds`, `_vocabIdFromWordId`,
  `_vocabNameFor` (all hardcoded legacy references)
- 9 `AppColors.domain*` constants
- `_AudioButton`'s `_warned`/`_availabilityStream` legacy toast machinery
- `flutter_tts` package + macOS pod + plugin registrant
- `QuestionType.seeContextPickWord` (always rendered as "...")

---

## Key design decisions (don't re-debate these)

1. **Youdao audio at runtime, cached.** User explicitly said "可以用有道的，原则可以违反". `TtsService.speak({text, lang})` checks `TtsCache` first, otherwise HTTP GETs Youdao, writes to `<appDocs>/tts_cache/<sha1>.mp3`, plays via `audioplayers.DeviceFileSource`. 8s timeout, `content-type` must contain `audio` to be accepted.

2. **Bundled 371 lists / 121 MB assets.** User said "全量". Release builds will compress with zlib. No lazy-loading.

3. **SchemaVersion wipe on first v2 launch.** `_enforceSchemaVersion()` reads `codeword_user_data.json`. If `schemaVersion` < 2, deletes 3 JSONs + resets in-memory state. User opted in to "全抹干净".

4. **CJK char-split normalization at conversion time.** qwerty upstream has `trans[]` like `["细","胞","器","；","细","胞","器","官"]` (one char per element). The script's `_normalise_translations` collapses to `["细胞器；细胞器官"]` when ≥70% of elements are single chars (covers pure CJK and CJK+Latin mixes like `["预","防","药","a","d","j"]`).

5. **Question type split for auto-play** (latest UI decision):
   - `listenPickMeaning` — auto-play (audio IS the prompt)
   - `seeWordPickMeaning` — no auto-play (audio is supplementary, button = "再听一次")
   - `seeMeaningPickWord` — no auto-play (auto-play would give away the answer)
   - `seeContextPickWord` — REMOVED entirely (qwerty data has empty `exampleEn` so the prompt always rendered as `...`)

6. **Library grid is grouped by category, 6 buckets** (priority order): 考试英语, 编程, 青少年英语, 语言, 词典, 专业词汇. Each shows `category · count`. 371 entries, scrollable.

---

## Current state — verified working

- `melos run analyze` → SUCCESS (0 issues)
- `melos run test` → SUCCESS (22/22)
- `melos run build:macos` → SUCCESS
- macOS app running (PID varies)
- Youdao endpoint: `curl -I .../dictvoice?audio=hello&type=2` returns 200, `audio/mpeg`, 10KB

The user's last screenshots showed:
- Home hero card displays "生物医学专业英语词汇" tag (resolved via `vocabMetaProvider[heroId]?.name`)
- Translation shows "细胞器；细胞器官" (post-normalization)
- Wrong-detail card: same fix applied via `_HeroWordDetail` (now a `ConsumerWidget`)
- Question type "语境选词" no longer appears (enum value removed)

---

## What the next agent should know

### 1. Why `_extractVocabIdFromWordId` (NOT `_extractSlugFromWordId`)

First version of the function returned just the slug (e.g. `cet4`), which
made `ContentLoader.loadList(slug)` look for `assets/vocab/cet4.json` — file
doesn't exist. **It must return the full id** `qwerty_<slug>` so the path
becomes `assets/vocab/qwerty_<slug>.json` which DOES exist. This was the
single biggest bug caught late in the audit.

```dart
// learning_session.dart:11
String _extractVocabIdFromWordId(String wid) {
  final parts = wid.split('_');
  if (parts.length < 3 || parts[0] != 'qwerty') return wid;
  return 'qwerty_${parts.sublist(1, parts.length - 1).join('_')}';
}
```

### 2. Conversion script edge cases the script handles

- Two qwerty entries with same id but different URLs (`Oxford5000`, `frequently_used_words03` upstream bug) — dedupe by URL, take first occurrence.
- `usphone` field sometimes empty — fall back to `phone`, then `phonetic`, then `ukphone`.
- Some qwerty entries have `usphone: ''` — `phonetic = usphone or ukphone` strips.
- Slug collisions: append `_2`, `_3` etc.
- COCA 20000 is the largest list (20199 words) — 5-digit zero-pad (`f'{idx:05d}'`) handles it.

### 3. How to refresh the asset bundle

```bash
cd /Users/bytedance/github/codeword
# (one-time, sets up tools/_qwerty_src — gitignored)
mkdir -p tools/_qwerty_src
git clone --depth 1 https://github.com/RealKai42/qwerty-learner.git tools/_qwerty_src

# every time upstream changes
python3 tools/import_qwerty_dict.py

# re-bundle into the .app
melos run build:macos
```

The script is idempotent (writes 372 files; rolls back on exception). If it
exits non-zero, no partial output remains.

### 4. The catalog provider thread

```dart
// learning_session.dart:591
final qwertyCatalogProvider = Provider<List<VocabList>>((ref) {
  throw UnimplementedError('qwertyCatalogProvider must be overridden...');
});
```

This MUST be overridden in `main()` before `runApp()`. Pattern:

```dart
// main.dart
List<VocabList> catalog = const [];
try { catalog = await loadQwertyCatalog(); } catch (_) {}
runApp(ProviderScope(
  overrides: [qwertyCatalogProvider.overrideWithValue(catalog)],
  child: const CodewordApp(),
));
```

All downstream code reads it synchronously. Tests must override too — see
`apps/codeword/test/widget_test.dart:testApp()` for the pattern.

### 5. Things that haven't been runtime-tested (only code-reviewed)

- `TtsService` Youdao fetch on real macOS network (curl showed 200; not via
  the actual `audioplayers.DeviceFileSource` codepath yet)
- `TtsCache` 100MB LRU eviction (logic correct, not stress-tested)
- `ReviewRepository._enforceSchemaVersion` against a real v1 user-data file
- Android `audioplayers` MP3 playback (not built for android yet)

---

## Known follow-ups (if the user asks for more)

1. **Dictation question type** (`听音拼词`): play audio, user types the word
   in a `TextField`. Suggested in the last session but not built. The 3-step
   ask → tap-to-hear → type-into-textfield flow would close the recall loop
   properly. The `QuestionType` enum and `_buildQuestion` switch are the
   entry points.

2. **~~Search/filter for the 371 lists.~~** Done: `discovery_screen.dart`
   now has a search bar and category chips that filter by name, description,
   and category.

3. **Asset bundle size.** 121 MB JSON in debug; release compresses to
   ~40-50 MB. Could trim `domain` field from each word (it's redundant
   with the list-level category) to save a few MB. Not urgent.

4. **The `q.content` field in `LearningQuestion` is unused.** Leftover from
   when `seeContextPickWord` was a thing. Could be removed.

5. **macOS app: needs `R` hot-restart after asset refresh.** Hot reload alone
   doesn't pick up new `assets/vocab/*.json` files (they're bundled at build
   time). The user already saw the "Lost connection to device" symptom once.

---

## Suggested skills for the next agent

- **`find-skills`** — if the user asks for something outside the obvious
  (e.g. translations to other languages, custom LLM flows), discover
  matching skills first.
- **`check`** — when the user says "review this" or "ship it", `check`
  auto-fixes safe issues and drives the release/PR flow.
- **`hunt`** — if a runtime bug surfaces (audio doesn't play, schemaVersion
  wipe doesn't fire, etc.), use this instead of guessing.
- **`impeccable`** — for any UI polish pass (the 371-list grid is the most
  visually obvious candidate; the home hero card is a smaller target).
- **`learn`** — not relevant; the user is iterating, not researching.
- **`think`** — if the user asks for a feature that's more than a one-file
  change, run `think` first to get a decision-complete plan.
- **`unpack-paper`** / **`read`** — not relevant; we're not reading papers
  or articles.

---

## Open questions for the next session

The user might ask:
- "把安卓 build 跑通" — Android side is untested. `melos run build:android`.
- "做听音拼词" — see Dictation above.
- "词库搜索" — see filter above.
- "音频缓存到 200MB 够不够" — configurable in `tts_cache.dart:maxBytes`.
- "再加一个语言" — qwerty has 371 lists covering 9+ languages; more
  vocab sources can be added by writing a new `to_codeword_word`-style
  converter and re-running the script.

---

## File:line index of the riskiest code paths

| Path | Why risky |
|---|---|
| `learning_session.dart:11-20` `_extractVocabIdFromWordId` | Wrong version breaks every per-vocab stat and the per-list loadList call. |
| `tts_cache.dart:33-44` `_inflight` map | Concurrent calls to `speak('cancel','us')` must dedupe to one download. |
| `review_repository.dart:93-122` `_enforceSchemaVersion` | Wipes user data once; a logic bug here = data loss. |
| `main.dart:30-37` `loadQwertyCatalog` try-catch | If the asset is missing/corrupt, app must boot with empty catalog, not crash. |
| `tts_service.dart:32-46` `speak` | Content-type must contain "audio" — if Youdao returns HTML on rate-limit, the check prevents garbage playback. |
| `import_qwerty_dict.py:_normalise_translations` | Single heuristic for char-split; a too-loose threshold merges English definitions incorrectly. Current 70% threshold was tested on biomedical, kaoyan, and English Essential words. |

---

## Quick re-orientation commands

```bash
cd /Users/bytedance/github/codeword

# what's running
pgrep -lf "codeword.app/Contents/MacOS" | head -1

# any flutter run still attached
ps aux | grep -E "flutter run|frontend_server_aot" | grep -v grep

# fresh run
export PATH="$PATH:$HOME/.pub-cache/bin"
cd apps/codeword
flutter run -d macos --debug

# verify the three gates
melos run analyze
melos run test
melos run build:macos

# inspect the catalog
python3 -c "
import json
m = json.load(open('apps/codeword/assets/vocab/_qwerty_index.json'))
print(f'{len(m)} lists, {sum(e[\"wordCount\"] for e in m)} words total')
"
```
