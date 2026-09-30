#!/usr/bin/env bash
# ==============================================================================
# Red Music Locker - Production Web Release Build Script for M3tal-Hub
# ==============================================================================
set -euo pipefail

BASE_HREF="${1:-/red-music-locker/}"
echo "============================================="
echo "Building Red Music Locker Web Release"
echo "Base HREF: ${BASE_HREF}"
echo "============================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${ROOT_DIR}/app"

echo "Resolving dependencies..."
flutter pub get

echo "Compiling Flutter web release..."
flutter build web --release --base-href "${BASE_HREF}"

# Mirror output to root build/web and dist for universal hub compatibility
cd "${ROOT_DIR}"
rm -rf build/web dist
mkdir -p build/web dist
cp -r app/build/web/* build/web/
cp -r app/build/web/* dist/

test -f dist/index.html || {
  echo "Error: dist/index.html was not generated!" >&2
  exit 1
}

echo "Red Music Locker release build completed successfully at dist/ and build/web/."
