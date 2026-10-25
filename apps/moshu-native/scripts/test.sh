#!/bin/bash
set -euo pipefail
native_dir="$(cd "$(dirname "$0")/.." && pwd)"
repo_dir="$(cd "$native_dir/../.." && pwd)"
mkdir -p "$native_dir/Sources/MoshuCore/Resources/vocab"
cp "$repo_dir/apps/codeword/assets/vocab/"*.json "$native_dir/Sources/MoshuCore/Resources/vocab/"
swift test --package-path "$native_dir"
