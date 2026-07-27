#!/usr/bin/env python3
"""Convert qwerty-learner's public/dicts/*.json into codeword's VocabWord schema.

Inputs:
  - tools/_qwerty_src/src/resources/dictionary.ts  (registry of lists)
  - tools/_qwerty_src/public/dicts/*.json         (raw word lists)

Outputs (written to apps/codeword/assets/vocab/):
  - _qwerty_index.json   (manifest of all converted lists)
  - qwerty_<slug>.json   (one file per list)

Each output word has the codeword VocabWord schema:
  {id, word, phonetic, pos, translation, translations, exampleEn, exampleCn,
   domain, level, synonyms, antonyms}

Rules:
  - id = 'qwerty_<slug>_<5-digit zero-pad>'
  - phonetic = (usphone or phone or phonetic, fallback to ukphone) stripped
  - translations = trans[] verbatim (whitespace-trimmed, drop empty)
  - translation = translations joined by '；'
  - Empty defaults for pos/exampleEn/exampleCn/synonyms/antonyms
  - domain = 'qwerty_<slug>'

LIST_META_OVERRIDES patches category/emoji/domainColor for lists that
don't fit the auto-derived scheme.

Catalogue-cleanup rules (mirrored from tools/fix_catalog.py so a fresh
upstream refresh reproduces the shipped catalogue):
  - EXCLUDE_CATEGORIES: skip non-English source lists (日/德/印尼/哈萨克…).
  - NAME_OVERRIDES: publisher/edition suffixes so duplicate-titled
    textbook lists stay distinguishable.
  - CATEGORY_MAP / LIST_META_OVERRIDES fold the singleton 专业词汇 / 词典
    buckets into the shared 综合 category.
NOTE: the upstream qwerty clone (tools/_qwerty_src) is gitignored and not
present here, so this generator cannot be re-run/verified locally; these
rules exist to keep a future refresh consistent with fix_catalog.py.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent  # repo root (codeword/)
QWERTY_SRC = ROOT / 'tools' / '_qwerty_src'
DICT_TS = QWERTY_SRC / 'src' / 'resources' / 'dictionary.ts'
QWERTY_DICTS = QWERTY_SRC / 'public' / 'dicts'
OUT_DIR = ROOT / 'apps' / 'codeword' / 'assets' / 'vocab'

# 8-color palette cycled by index in the manifest (after sort).
PALETTE = [
    '#3B82F6',  # blue
    '#8B5CF6',  # violet
    '#EC4899',  # pink
    '#10B981',  # green
    '#F59E0B',  # amber
    '#14B8A6',  # teal
    '#EF4444',  # red
    '#6366F1',  # indigo
]

# Maps qwerty category -> our category. Anything not in here falls through to
# the original (stripped of leading 中国/国际/etc. prefix).
CATEGORY_MAP = {
    '中国考试': '考试英语',
    '国际考试': '考试英语',
    '青少年英语': '青少年英语',
    '专业词汇': '综合',
    '英语词典': '综合',
    '程序员的英语': '编程',
    'code': '编程',
    '代码练习': '编程',
    '日语': '语言',
    '哈萨克语': '语言',
    '印尼语': '语言',
    '日语学习': '语言',
    '德语学习': '语言',
    '其它': '其他',
    '其他': '其他',
    '影视': '其他',
    '词典': '综合',
    # Hand-curated candidate bucket (not emitted by this generator, listed
    # for parity with tools/fix_catalog.py).
    '精选词书': '综合',
}

# Per-list overrides for emoji + domainColor + category.
# Keys are qwerty `id` (or the URL filename stem if the id is buggy).
LIST_META_OVERRIDES = {
    # exams — blue family
    'cet4':            {'category': '考试英语', 'emoji': '📘', 'color': '#3B82F6'},
    'cet6':            {'category': '考试英语', 'emoji': '📗', 'color': '#2563EB'},
    'kaoyan':          {'category': '考试英语', 'emoji': '📕', 'color': '#1D4ED8'},
    'kaoyan_2024':     {'category': '考试英语', 'emoji': '📕', 'color': '#1E40AF'},
    'ielts':           {'category': '考试英语', 'emoji': '🛫', 'color': '#8B5CF6'},
    'toefl':           {'category': '考试英语', 'emoji': '🗽', 'color': '#7C3AED'},
    'gre':             {'category': '考试英语', 'emoji': '🎓', 'color': '#6D28D9'},
    'gmat':            {'category': '考试英语', 'emoji': '💼', 'color': '#5B21B6'},
    'sat':             {'category': '考试英语', 'emoji': '🇺🇸', 'color': '#4F46E5'},
    'bec2':            {'category': '考试英语', 'emoji': '💱', 'color': '#0EA5E9'},
    'bec3':            {'category': '考试英语', 'emoji': '💱', 'color': '#0284C7'},
    'pet-2024':        {'category': '考试英语', 'emoji': '🐶', 'color': '#0891B2'},
    'ket':             {'category': '考试英语', 'emoji': '🐣', 'color': '#0E7490'},
    'level4':          {'category': '考试英语', 'emoji': '🎓', 'color': '#7E22CE'},
    'level8':          {'category': '考试英语', 'emoji': '🎓', 'color': '#6B21A8'},
    'duolingo_vocabulary_b1':  {'category': '考试英语', 'emoji': '🦉', 'color': '#22C55E'},
    'duolingo_vocabulary_b2':  {'category': '考试英语', 'emoji': '🦉', 'color': '#16A34A'},
    'duolingo_vocabulary_c1':  {'category': '考试英语', 'emoji': '🦉', 'color': '#15803D'},

    # kids / youth — green family
    'gaokao3500':      {'category': '青少年英语', 'emoji': '🏫', 'color': '#10B981'},
    'nce1':            {'category': '青少年英语', 'emoji': '🐣', 'color': '#059669'},
    'nce2':            {'category': '青少年英语', 'emoji': '🐤', 'color': '#047857'},
    'nce3':            {'category': '青少年英语', 'emoji': '🐔', 'color': '#065F46'},
    'nce4':            {'category': '青少年英语', 'emoji': '🦅', 'color': '#064E3B'},

    # languages — purple family
    'japanese_n1':     {'category': '语言', 'emoji': '🇯🇵', 'color': '#A855F7'},
    'japanese_n2':     {'category': '语言', 'emoji': '🇯🇵', 'color': '#9333EA'},
    'japanese_n3':     {'category': '语言', 'emoji': '🇯🇵', 'color': '#7E22CE'},
    'japanese_n4':     {'category': '语言', 'emoji': '🇯🇵', 'color': '#6B21A8'},
    'japanese_n5':     {'category': '语言', 'emoji': '🇯🇵', 'color': '#581C87'},
    'kazakh':          {'category': '语言', 'emoji': '🇰🇿', 'color': '#C026D3'},

    # code — orange family
    'coder':           {'category': '编程', 'emoji': '💻', 'color': '#F97316'},
    'javascript':      {'category': '编程', 'emoji': '🟨', 'color': '#F59E0B'},
    'node':            {'category': '编程', 'emoji': '🟩', 'color': '#84CC16'},
    'java':            {'category': '编程', 'emoji': '☕', 'color': '#EA580C'},
    'linux':           {'category': '编程', 'emoji': '🐧', 'color': '#0F172A'},
    'csharp':          {'category': '编程', 'emoji': '#️⃣', 'color': '#7C2D12'},

    # specialty
    'biomedical-terms':{'category': '综合', 'emoji': '🧬', 'color': '#BE123C'},

    # catch-alls
    'oxford5000':      {'category': '综合', 'emoji': '📕', 'color': '#475569'},
    'oxford3000':      {'category': '综合', 'emoji': '📗', 'color': '#64748B'},
    'longman_communication_3000_words': {'category': '综合', 'emoji': '📙', 'color': '#94A3B8'},
    'coca_20000':      {'category': '综合', 'emoji': '🗂️', 'color': '#1E293B'},
}

# Categories dropped wholesale (non-English source content). Mirrors
# fix_catalog.py's EXCLUDE_CATEGORIES. Applied AFTER category resolution.
EXCLUDE_CATEGORIES = {'语言'}

# Individual lists dropped as duplicate/equivalent copies of another kept list
# (same word set, only ordering / casing / edition differs), plus the two
# 4000-Essential lists whose translations are 100% English gloss (unusable in
# the Chinese multiple-choice / listening modes). Keyed on the FINAL codeword
# id. Mirrors the one-off prune applied to the bundled assets; keep in sync so
# an upstream refresh does not resurrect them.
EXCLUDE_IDS = {
    'qwerty_ielts_disorder',                        # ≡ qwerty_ielts_order (仅乱序)
    'qwerty_pte_advanced_apeuni_json',              # ≡ qwerty_pte_senior
    'qwerty_zaiyaoniming_gre3000',                  # ≡ qwerty_gre3000 (别名)
    'qwerty_pte_basic_apeuni',                      # ≡ qwerty_pte_junior
    'qwerty_nce1',                                  # ≡ qwerty_nce_new_1 (新版)
    'qwerty_ielts_listening_neworientaldirect_task4',  # ≡ task3
    'qwerty_sql_lower_case',                        # ≡ qwerty_sql_upper_case
    'qwerty_4000_essential_english_words1',         # 纯英文释义, 四选一不可用
    'qwerty_4000_essential_english_words2',         # 纯英文释义, 四选一不可用
}

# Display-name overrides so duplicate-titled lists stay distinguishable.
# Keyed on the FINAL codeword id (`qwerty_<slug>`), matching fix_catalog.py.
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


def slugify(s: str) -> str:
    s = re.sub(r'[^a-z0-9]+', '_', s.lower()).strip('_')
    return s or 'list'


def parse_dictionary_ts(path: Path):
    """Yield (id, name, description, category, tags, url, length, language) per entry."""
    text = path.read_text(encoding='utf-8')
    pattern = re.compile(
        r"id:\s*'([^']+)',\s*"
        r"name:\s*'((?:\\'|[^'])*)',\s*"
        r"description:\s*'((?:\\'|[^'])*)',\s*"
        r"category:\s*'([^']+)',\s*"
        r"tags:\s*\[([^\]]*)\],\s*"
        r"url:\s*'([^']+)',\s*"
        r"length:\s*(\d+),\s*"
        r"language:\s*'([^']*)'",
        re.DOTALL,
    )
    for m in pattern.finditer(text):
        yield {
            'id': m.group(1),
            'name': m.group(2).replace("\\'", "'"),
            'description': m.group(3).replace("\\'", "'"),
            'category': m.group(4),
            'tags': re.findall(r"'([^']*)'", m.group(5)),
            'url': m.group(6),
            'length': int(m.group(7)),
            'language': m.group(8),
        }


def read_qwerty_words(url_path: str) -> list[dict]:
    """Read public/dicts/<basename> and return list of raw word dicts."""
    basename = url_path.split('/')[-1]
    p = QWERTY_DICTS / basename
    if not p.exists():
        return []
    return json.loads(p.read_text(encoding='utf-8'))


def derive_phonetic(entry: dict) -> str:
    for k in ('usphone', 'phone', 'phonetic', 'Phonetic'):
        v = (entry.get(k) or '').strip()
        if v:
            return v
    return (entry.get('ukphone') or '').strip()


def derive_level(meta: dict) -> str:
    name = meta['name']
    if 'CET-4' in name: return 'CET-4'
    if 'CET-6' in name: return 'CET-6'
    if '考研' in name or 'Kaoyan' in name.lower(): return '考研'
    if 'IELTS' in name or '雅思' in name: return 'IELTS'
    if 'TOEFL' in name or '托福' in name: return 'TOEFL'
    if 'GRE' in name: return 'GRE'
    if 'GMAT' in name: return 'GMAT'
    if 'SAT' in name: return 'SAT'
    return ''


def _normalise_translations(raw_trans: list) -> list[str]:
    """Normalise qwerty-learner's trans[] into a list of definition strings.

    Some upstream lists (notably the Chinese biomedical/school-grade
    lists) carry one character per element, often with Latin letters
    interleaved as POS markers:
      "trans": ["细","胞","器","；","细","胞","器","官"]
      "trans": ["预","防","药","；","预","防","法","a","d","j",".",
                "预","防","的","，","防","止","的"]
    We detect that pattern — when most non-empty elements are
    single-character strings (CJK ideograph, CJK/Hangul/Kana
    syllable, or ASCII letter) — and collapse the whole list into one
    string. Otherwise we pass it through as one definition per element.
    """
    cleaned = [t.strip() for t in raw_trans if isinstance(t, str) and t.strip()]
    if not cleaned:
        return []

    def is_single_char(s: str) -> bool:
        if len(s) != 1:
            return False
        cp = ord(s[0])
        return (
            0x4E00 <= cp <= 0x9FFF           # CJK Unified Ideographs
            or 0x3400 <= cp <= 0x4DBF         # CJK Extension A
            or 0x3040 <= cp <= 0x30FF         # Hiragana / Katakana
            or 0xAC00 <= cp <= 0xD7AF         # Hangul Syllables
            or 0x3000 <= cp <= 0x303F         # CJK punctuation
            or 0xFF00 <= cp <= 0xFFEF         # Halfwidth / fullwidth forms
            or 0x20 <= cp < 0x7F              # printable ASCII (letters, digits, punct)
        )

    single_char_count = sum(1 for s in cleaned if is_single_char(s))
    # If 70%+ of elements are single chars, treat as char-split and join.
    if single_char_count / len(cleaned) >= 0.7:
        return [''.join(cleaned)]
    return cleaned


def to_codeword_word(entry: dict, slug: str, seq: int) -> dict:
    name = entry.get('name') or entry.get('word') or ''
    raw_trans = entry.get('trans') or entry.get('translations') or []
    translations = _normalise_translations(raw_trans)
    return {
        'id': f'qwerty_{slug}_{seq:05d}',
        'word': name,
        'phonetic': derive_phonetic(entry),
        'translation': '；'.join(translations),
        'translations': translations,
        'domain': f'qwerty_{slug}',
    }


def build_meta(qw_meta: dict) -> dict:
    override = LIST_META_OVERRIDES.get(qw_meta['id'], {})
    category = override.get('category') or CATEGORY_MAP.get(qw_meta['category'], qw_meta['category'])
    emoji = override.get('emoji', '📘')
    color = override.get('color', '#3B82F6')
    return {
        'id': '',  # filled by caller
        'name': qw_meta['name'],
        'description': qw_meta['description'],
        'category': category,
        'emoji': emoji,
        'domainColor': color,
        'level': 1,
        'wordCount': qw_meta['length'],
        'source': 'qwerty',
    }


def main() -> int:
    if not DICT_TS.exists():
        print(f'FATAL: {DICT_TS} not found', file=sys.stderr)
        return 1
    if not QWERTY_DICTS.exists():
        print(f'FATAL: {QWERTY_DICTS} not found', file=sys.stderr)
        return 1

    # Dedupe by URL (Oxford5000 / frequently_used_words03 quirks in upstream).
    by_url: dict[str, dict] = {}
    for entry in parse_dictionary_ts(DICT_TS):
        if entry['url'] not in by_url:
            by_url[entry['url']] = entry

    print(f'Parsed {len(by_url)} unique lists from dictionary.ts')

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # Two-phase: collect, then assert slug uniqueness, then write.
    pending: list[tuple[str, dict, list[dict]]] = []  # (slug, meta, words)
    used_slugs: set[str] = set()
    seen_ids: set[str] = set()
    written_files: list[Path] = []

    try:
        for url, qw_meta in by_url.items():
            words = read_qwerty_words(url)
            if not words:
                print(f'  SKIP (no file): {url}')
                continue

            base_slug = slugify(qw_meta['id'])
            slug = base_slug
            i = 2
            while slug in used_slugs:
                slug = f'{base_slug}_{i}'
                i += 1
            used_slugs.add(slug)

            code_meta = build_meta(qw_meta)
            code_meta['id'] = f'qwerty_{slug}'

            # Drop excluded categories (non-English source lists). Release the
            # reserved slug so it doesn't perturb later collision suffixes.
            if code_meta['category'] in EXCLUDE_CATEGORIES:
                used_slugs.discard(slug)
                print(f"  SKIP (excluded category {code_meta['category']}): {code_meta['id']}")
                continue

            # Drop individually-excluded duplicate/unusable lists.
            if code_meta['id'] in EXCLUDE_IDS:
                used_slugs.discard(slug)
                print(f"  SKIP (excluded id): {code_meta['id']}")
                continue

            # Publisher/edition display-name override for duplicate titles.
            name_override = NAME_OVERRIDES.get(code_meta['id'])
            if name_override:
                code_meta['name'] = name_override

            code_words = [
                to_codeword_word(w, slug, i + 1) for i, w in enumerate(words)
            ]
            for w in code_words:
                if w['id'] in seen_ids:
                    raise SystemExit(f'duplicate word id detected: {w["id"]}')
                seen_ids.add(w['id'])
            code_meta['wordCount'] = len(code_words)

            pending.append((slug, code_meta, code_words))

        # Write all files.
        for slug, code_meta, code_words in pending:
            out_file = OUT_DIR / f'qwerty_{slug}.json'
            out_file.write_text(
                json.dumps(code_words, ensure_ascii=False, indent=2),
                encoding='utf-8',
            )
            written_files.append(out_file)
            print(f'  WROTE {out_file.relative_to(ROOT)}: {len(code_words)} words')

        # Build manifest, sort by (category, name).
        manifest = sorted(
            (m for _, m, _ in pending),
            key=lambda m: (m['category'], m['name']),
        )
        manifest_path = OUT_DIR / '_qwerty_index.json'
        manifest_path.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2),
            encoding='utf-8',
        )
        written_files.append(manifest_path)
        print(f'  WROTE {manifest_path.relative_to(ROOT)}: {len(manifest)} lists')

        total_words = sum(m['wordCount'] for m in manifest)
        print(f'\nOK: {len(manifest)} lists, {total_words} words total')
        return 0
    except SystemExit:
        raise
    except Exception as e:
        # Roll back any written files.
        for f in written_files:
            try:
                f.unlink()
            except OSError:
                pass
        print(f'FATAL: {e}', file=sys.stderr)
        raise


if __name__ == '__main__':
    sys.exit(main())
