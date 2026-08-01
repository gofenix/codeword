#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IPA="${1:-}"
PUBSPEC="$ROOT/apps/codeword/pubspec.yaml"

if [[ -z "$IPA" ]]; then
  echo "Usage: $0 <ipa>" >&2
  exit 2
fi

if [[ ! -f "$IPA" ]]; then
  echo "IPA not found: $IPA" >&2
  exit 2
fi

VERSION_VALUE="$(awk '/^version:/ { print $2; exit }' "$PUBSPEC" | tr -d "\"'")"
SOURCE_VERSION="${VERSION_VALUE%%+*}"
SOURCE_BUILD="${VERSION_VALUE##*+}"

if [[ "$VERSION_VALUE" != *+* || -z "$SOURCE_VERSION" || ! "$SOURCE_BUILD" =~ ^[0-9]+$ ]]; then
  echo "Could not parse version and numeric build number from: $PUBSPEC" >&2
  exit 2
fi

INFO_PATH="$(unzip -Z1 "$IPA" | rg -m1 '^Payload/[^/]+\.app/Info\.plist$' || true)"
if [[ -z "$INFO_PATH" ]]; then
  echo "Main app Info.plist not found in IPA: $IPA" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -r "$TMP_DIR"' EXIT
unzip -p "$IPA" "$INFO_PATH" > "$TMP_DIR/Info.plist"

IPA_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TMP_DIR/Info.plist")"
IPA_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$TMP_DIR/Info.plist")"

if [[ "$IPA_VERSION" != "$SOURCE_VERSION" || "$IPA_BUILD" != "$SOURCE_BUILD" ]]; then
  echo "iOS release version mismatch: pubspec=$SOURCE_VERSION+$SOURCE_BUILD ipa=$IPA_VERSION+$IPA_BUILD" >&2
  exit 1
fi

echo "iOS release version passed: $IPA_VERSION+$IPA_BUILD"
