#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=1.5.0
SHA256=f2c1c76592a82ffff8413ba3c4a1299b6c7ab06c734dee03fd88630485c2b920
WORK="$ROOT/build/libflac"
ARCHIVE="$WORK/downloads/flac-$VERSION.tar.xz"
SOURCE="$WORK/source/flac-$VERSION"
ARCH=${ARCH:-arm64}
MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-13.0}
OUTPUT="$WORK/$ARCH-macos$MACOSX_DEPLOYMENT_TARGET"

if [[ -z "${CMAKE:-}" ]]; then
    if command -v cmake >/dev/null 2>&1; then
        CMAKE=$(command -v cmake)
    elif [[ -x /Applications/CMake.app/Contents/bin/cmake ]]; then
        CMAKE=/Applications/CMake.app/Contents/bin/cmake
    else
        echo 'CMake is required. Install it or set CMAKE to its executable path.' >&2
        exit 1
    fi
fi

mkdir -p "$WORK/downloads" "$WORK/source"
if [[ ! -f "$ARCHIVE" ]]; then
    curl --fail --location --retry 3 \
        "https://github.com/xiph/flac/releases/download/$VERSION/flac-$VERSION.tar.xz" \
        -o "$ARCHIVE.part"
    mv "$ARCHIVE.part" "$ARCHIVE"
fi
printf '%s  %s\n' "$SHA256" "$ARCHIVE" | shasum -a 256 --check

# Only extract verified sources. Re-extract on every invocation to avoid stale edits.
tar -xf "$ARCHIVE" -C "$WORK/source"
"$CMAKE" -S "$SOURCE" -B "$OUTPUT/build" -G 'Unix Makefiles' \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
    -DCMAKE_INSTALL_PREFIX="$OUTPUT/install" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_CXXLIBS=OFF \
    -DBUILD_PROGRAMS=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_TESTING=OFF \
    -DBUILD_DOCS=OFF \
    -DINSTALL_MANPAGES=OFF \
    -DWITH_OGG=OFF
"$CMAKE" --build "$OUTPUT/build" --parallel "$(sysctl -n hw.ncpu)"
"$CMAKE" --install "$OUTPUT/build"
mkdir -p "$OUTPUT/install/share/licenses/flac"
cp "$SOURCE/COPYING.Xiph" "$OUTPUT/install/share/licenses/flac/"
printf '\nlibFLAC installed to %s\n' "$OUTPUT/install"
