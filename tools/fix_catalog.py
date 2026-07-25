#!/usr/bin/env python3
"""One-time catalogue migration for codeword's bundled vocab index.

Cleans up `apps/codeword/assets/vocab/_qwerty_index.json` (the git-tracked,
directly-bundled data source — NOT regenerated at runtime) and prunes the
matching per-list word files. It is auditable and idempotent: running it a
second time is a no-op because every rule is keyed on data that no longer
matches once applied.

Rules (mirror of tools/import_qwerty_dict.py so a future upstream refresh
stays consistent):

  1. Drop the `语言` category entirely. Those 23 lists are Japanese / German /
     Indonesian / Kazakh source content (plus EN/中 translation duplicates of
     the same JLPT levels) — off-scope for an English→Chinese app. Their word
     files are deleted to shrink the bundle.

  2. Give duplicate-named textbook lists a publisher suffix so they are
     distinguishable, e.g. `高中必修1` → `高中必修1（人教版）` /（译林版）/
    （北师大版）. Names only; ids, categories and word files are untouched.

  3. Disambiguate the two `Essential Words` lists →（释义版）/（例句版）
     based on their `meaning` / `sentence` description.

  4. Merge the singleton categories `精选词书` / `专业词汇` / `词典` into `综合`.

After applying, the manifest is re-sorted by (category, name) to match the
generator, and the script asserts: no duplicate names remain (beyond the
intended renames), every surviving `wordCount` still matches its word file,
and no deleted list id is referenced anywhere in the manifest.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent  # repo root (codeword/)
VOCAB_DIR = ROOT / 'apps' / 'codeword' / 'assets' / 'vocab'
INDEX = VOCAB_DIR / '_qwerty_index.json'

# 1. Categories removed wholesale (their word files are deleted too).
EXCLUDE_CATEGORIES = {'语言'}

# 4. Small / singleton categories folded into one general bucket.
CATEGORY_MERGE = {
    '精选词书': '综合',
    '专业词汇': '综合',
    '词典': '综合',
}

# 2 + 3. Explicit id → new display name. Keyed on list id so it is
# unambiguous and safe to re-run. Derived and verified against the current
# index; see the module docstring for the rule that produced them.
NAME_OVERRIDES = {
    # Essential Words — meaning vs sentence editions.
    'qwerty_4000_essential_english_words1': 'Essential Words（释义版）',
    'qwerty_4000_essential_english_words2': 'Essential Words（例句版）',
    # 高中必修 / 选修 — one entry per publisher, same title upstream.
    'qwerty_renjiaogaozhong1': '高中必修1（人教版）',
    'qwerty_renjiaogaozhong2': '高中必修2（人教版）',
    'qwerty_renjiaogaozhong3': '高中必修3（人教版）',
    'qwerty_renjiaogaozhong4': '高中必修4（人教版）',
    'qwerty_renjiaogaozhong5': '高中必修5（人教版）',
    'qwerty_renjiaogaozhong6': '高中选修6（人教版）',
    'qwerty_renjiaogaozhong7': '高中选修7（人教版）',
    'qwerty_renjiaogaozhong8': '高中选修8（人教版）',
    'qwerty_renjiaogaozhong9': '高中选修9（人教版）',
    'qwerty_renjiaogaozhong10': '高中选修10（人教版）',
    'qwerty_renjiaogaozhong11': '高中选修11（人教版）',
    'qwerty_yilin1': '高中必修1（译林版）',
    'qwerty_yilin2': '高中必修2（译林版）',
    'qwerty_yilin3': '高中必修3（译林版）',
    'qwerty_beishi1': '高中必修1（北师大版）',
    'qwerty_beishi2': '高中必修2（北师大版）',
    'qwerty_beishi3': '高中必修3（北师大版）',
    'qwerty_beishi4': '高中必修4（北师大版）',
    'qwerty_beishi5': '高中必修5（北师大版）',
    'qwerty_beishi6': '高中选修6（北师大版）',
    'qwerty_beishi7': '高中选修7（北师大版）',
    'qwerty_beishi8': '高中选修8（北师大版）',
    'qwerty_beishi9': '高中选修9（北师大版）',
    'qwerty_beishi10': '高中选修10（北师大版）',
    'qwerty_beishi11': '高中选修11（北师大版）',
}


def main() -> int:
    if not INDEX.exists():
        print(f'FATAL: {INDEX} not found', file=sys.stderr)
        return 1

    manifest = json.loads(INDEX.read_text(encoding='utf-8'))
    print(f'Loaded {len(manifest)} lists from {INDEX.relative_to(ROOT)}')

    kept: list[dict] = []
    removed: list[dict] = []
    for entry in manifest:
        if entry.get('category') in EXCLUDE_CATEGORIES:
            removed.append(entry)
        else:
            kept.append(entry)

    # Apply category merge + name overrides on the kept set.
    renamed = 0
    remapped = 0
    for entry in kept:
        new_cat = CATEGORY_MERGE.get(entry['category'])
        if new_cat:
            entry['category'] = new_cat
            remapped += 1
        new_name = NAME_OVERRIDES.get(entry['id'])
        if new_name and new_name != entry['name']:
            entry['name'] = new_name
            renamed += 1

    # Delete word files for removed lists.
    deleted_files = 0
    for entry in removed:
        wf = VOCAB_DIR / f"{entry['id']}.json"
        if wf.exists():
            wf.unlink()
            deleted_files += 1
            print(f'  DELETED {wf.relative_to(ROOT)}')
        else:
            print(f'  (already gone) {wf.relative_to(ROOT)}')

    print(
        f'\nRemoved {len(removed)} lists ({deleted_files} word files deleted), '
        f'merged {remapped} categories, renamed {renamed} lists.'
    )

    # Re-sort by (category, name) to match the generator's manifest order.
    kept.sort(key=lambda m: (m['category'], m['name']))
    INDEX.write_text(
        json.dumps(kept, ensure_ascii=False, indent=2),
        encoding='utf-8',
    )
    print(f'WROTE {INDEX.relative_to(ROOT)}: {len(kept)} lists')

    _verify(kept, removed)
    return 0


def _verify(kept: list[dict], removed: list[dict]) -> None:
    """Post-migration assertions; raises SystemExit on any failure."""
    errors: list[str] = []

    # No duplicate names remain.
    seen: dict[str, str] = {}
    for e in kept:
        if e['name'] in seen:
            errors.append(
                f"duplicate name {e['name']!r}: {seen[e['name']]} & {e['id']}"
            )
        else:
            seen[e['name']] = e['id']

    # No excluded category leaked through.
    for e in kept:
        if e['category'] in EXCLUDE_CATEGORIES:
            errors.append(f"excluded category survived: {e['id']}")

    # Every surviving list has a word file whose length matches wordCount.
    for e in kept:
        wf = VOCAB_DIR / f"{e['id']}.json"
        if not wf.exists():
            errors.append(f"missing word file: {e['id']}")
            continue
        words = json.loads(wf.read_text(encoding='utf-8'))
        if len(words) != e['wordCount']:
            errors.append(
                f"wordCount mismatch {e['id']}: index={e['wordCount']} "
                f"file={len(words)}"
            )

    # Removed ids are gone from the manifest AND from disk.
    kept_ids = {e['id'] for e in kept}
    for e in removed:
        if e['id'] in kept_ids:
            errors.append(f"removed id still in manifest: {e['id']}")
        if (VOCAB_DIR / f"{e['id']}.json").exists():
            errors.append(f"removed word file still on disk: {e['id']}")

    if errors:
        print('\nVERIFY FAILED:', file=sys.stderr)
        for err in errors:
            print(f'  - {err}', file=sys.stderr)
        raise SystemExit(1)

    total_words = sum(e['wordCount'] for e in kept)
    cats = sorted({e['category'] for e in kept})
    print(
        f'\nVERIFY OK: {len(kept)} lists, {total_words} words, '
        f'categories={cats}'
    )


if __name__ == '__main__':
    sys.exit(main())
