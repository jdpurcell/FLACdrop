# Developing FLACdrop

FLACdrop uses SwiftUI for its interface, Apple's Extended Audio File Services for
input decoding, and a statically linked libFLAC for encoding. Files are processed
sequentially; each encoder uses up to the active logical processor count, capped
at libFLAC's limit of 128 threads.

## Prerequisites

- macOS with Xcode or Command Line Tools providing Swift 6, Clang, and a macOS SDK.
- CMake, either on PATH or at `/Applications/CMake.app/Contents/bin/cmake`.
  Alternatively, set `CMAKE` to its executable path.
- Internet access for the initial libFLAC source download.
- Python 3 at `/usr/bin/python3` and Apple's `afconvert` for the integration tests.

No globally installed libFLAC or Homebrew library is required.

## Build and run

Run these commands from the repository root:

```sh
bash scripts/build-app.sh
open build/FLACdrop.app
```

This builds libFLAC and the app, packages the icon and libFLAC license notice,
then ad-hoc signs `build/FLACdrop.app` for local use. Distribution signing and
notarization are handled separately by the release workflow.

The build defaults to `ARCH=arm64` and `MACOSX_DEPLOYMENT_TARGET=13.0`. Both scripts
accept these environment variables. Prebuilt releases support only arm64; Intel
and universal builds are not part of the release or test configuration.

The app version (`CFBundleShortVersionString`) and build number (`CFBundleVersion`)
are set in `scripts/build-app.sh`. The standard About panel displays the app
version and hides the build number.

## libFLAC dependency

To build only the library:

```sh
bash scripts/build-libflac.sh
```

The script downloads the official FLAC 1.5.0 source archive, verifies the pinned
SHA-256 before extraction, and builds a Release static library. Ogg support, the
C++ wrapper, command-line programs, examples, upstream tests, and documentation
are disabled. Native FLAC encoding, decoding, and multithreading remain enabled.

Outputs are under `build/libflac/<architecture>-macos<deployment-target>/install/`:

- `lib/libFLAC.a`
- `include/FLAC/` public C headers
- `share/licenses/flac/COPYING.Xiph` upstream license notice

The Swift module map is in `Sources/CFLAC/`. Downloads, extracted sources, compiler
caches, and build outputs stay under the ignored `build/` directory. Remove that
directory for a clean build. Cached archives are verified on every invocation.
Keep the upstream license notice with distributions.

## Integration tests

After building with the default arm64/macOS 13.0 configuration, run:

```sh
bash scripts/test-encoder.sh
```

The test script currently uses that configuration's library path. It generates
fixtures using Python and `afconvert`, then checks exact sample round trips for
8/16/24/32-bit WAV, mono, AIFF, and ALAC with four encoding threads and verification
enabled. It also checks natural filename ordering, existing-output protection,
rejection of lossy/floating-point/multichannel/malformed inputs, and temporary-file
cleanup. The suite does not automate Finder drops or the SwiftUI dialogs.

## App icon

Editable artwork and the exported ICNS, PNG, and iconset are in `Assets/Icon/`.
The app build copies `FLACdrop.icns` into its resources and references it through
`CFBundleIconFile`. Editing the SVG alone does not regenerate the exported assets.

## GitHub Actions releases

`.github/workflows/release.yml` runs only through `workflow_dispatch`. From GitHub
Actions, choose **Release → Run workflow**. It builds and tests on a macOS arm64
runner and uploads one `FLACdrop-<version>-macOS-arm64.dmg` as a workflow artifact.
The version comes from the built app. Upload uses `archive: false`, so the DMG is
not wrapped in a ZIP. The workflow does not create a GitHub Release or tag.

Configure these repository Actions secrets:

- `APPLE_DEVID_APP_CERT_DATA`: base64-encoded Developer ID Application P12,
  including its private key.
- `APPLE_DEVID_APP_CERT_PASS`: the P12 password.
- `APPLE_ID_USER`: the Apple ID used for notarization.
- `APPLE_ID_PASS`: an app-specific password for that Apple ID.

The certificate installer is `scripts/install_cert_macos.ps1`.
`scripts/package-release.sh` derives the team ID from the signing identity, signs
the app with Developer ID and hardened runtime, and packages it alongside an
Applications shortcut in a compressed DMG. It signs the DMG, submits it with
`notarytool`, requires acceptance, staples and validates the ticket, and verifies
the disk image before upload. Only the DMG is submitted and stapled; the app is
not separately submitted or stapled. Local ad-hoc builds do not perform these
release steps. Release output is in the ignored `dist/` directory.
