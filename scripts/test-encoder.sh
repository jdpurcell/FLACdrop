#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PREFIX="$ROOT/build/libflac/arm64-macos13.0/install"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/flacdrop-tests.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
/usr/bin/python3 - "$TEST_DIR" <<'PY'
import sys, wave, struct
from pathlib import Path
p = Path(sys.argv[1])
for name, bits, channels in [('pcm8',8,2),('pcm16',16,2),('pcm24',24,2),('pcm32',32,2),('mono',24,1),('surround',16,6)]:
    samples = [-(1 << (bits-1)), (1 << (bits-1))-1, -1, 0, 1]
    samples += [((i * 17077) % (1 << bits)) - (1 << (bits-1)) for i in range(40000 * channels - 5)]
    with wave.open(str(p / (name+'.wav')), 'wb') as f:
        f.setparams((channels, bits//8, 44100, 0, 'NONE', 'not compressed'))
        f.writeframes(b''.join((v+128).to_bytes(1,'little') if bits==8 else v.to_bytes(bits//8,'little',signed=True) for v in samples))
(p/'broken.wav').write_bytes(b'not audio')
PY
/usr/bin/afconvert "$TEST_DIR/pcm24.wav" "$TEST_DIR/integer.aiff" -f AIFF -d BEI24
/usr/bin/afconvert "$TEST_DIR/pcm24.wav" "$TEST_DIR/lossless.m4a" -f m4af -d alac
/usr/bin/afconvert "$TEST_DIR/pcm16.wav" "$TEST_DIR/lossy.m4a" -f m4af -d aac
/usr/bin/afconvert "$TEST_DIR/pcm16.wav" "$TEST_DIR/float.wav" -f WAVE -d LEF32
xcrun swiftc -swift-version 6 -module-cache-path "$ROOT/build/ModuleCache" \
    -I "$ROOT/Sources/CFLAC" -Xcc -I -Xcc "$PREFIX/include" \
    "$ROOT/Sources/FLACdrop/Encoder.swift" "$ROOT/Tests/main.swift" \
    "$PREFIX/lib/libFLAC.a" -o "$TEST_DIR/test-encoder"
"$TEST_DIR/test-encoder" "$TEST_DIR"
