#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACT="${1:-}"

if rg -n 'assets/local|llm_key\.txt|llmFallbackKeyProvider' \
  "$ROOT/apps/codeword/lib" "$ROOT/apps/codeword/pubspec.yaml"; then
  echo "Release secret gate failed: bundled credential path found." >&2
  exit 1
fi

if [[ -z "$ARTIFACT" ]]; then
  echo "Release source secret gate passed."
  exit 0
fi

if [[ ! -f "$ARTIFACT" ]]; then
  echo "Artifact not found: $ARTIFACT" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
unzip -oqq "$ARTIFACT" -d "$TMP_DIR"

if find "$TMP_DIR" -type f -print0 | xargs -0 strings 2>/dev/null | \
  rg -n 'llm_key\.txt|assets/local|sk-[A-Za-z0-9_-]{24,}'; then
  echo "Release secret gate failed: credential-like content in artifact." >&2
  exit 1
fi

echo "Release artifact secret gate passed: $ARTIFACT"
