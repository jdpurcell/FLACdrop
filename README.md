# FLACdrop

A simple drag-and-drop FLAC encoder for macOS. Convert lossless audio files to
FLAC with the official libFLAC encoder.

<img width="440" height="284" alt="FLACdrop" src="https://github.com/user-attachments/assets/80b2e3c8-1138-40fb-8cde-8d7ed54e7550" />

## Requirements and installation

- macOS 13 Ventura or later.
- A Mac with Apple silicon (M1 or newer). Intel Macs are not supported by the
  prebuilt app.

Open the downloaded DMG, drag **FLACdrop** to **Applications**, and launch it.
No additional encoders or audio tools need to be installed. The app is signed and
notarized, so it opens normally without Gatekeeper workarounds. 

## Using FLACdrop

1. Choose a **Compression level** and whether to **Verify encoded audio**.
2. Drag one or more audio files from Finder onto **Drop files here**.
3. Wait for the completion message. If any files fail, the app lists their names
   and error messages and continues processing the remaining files.

Each output is saved in the same folder as its input, with the extension changed
to `.flac`: `Song.wav` becomes `Song.flac`. Original files are kept. Existing
outputs are never overwritten; a matching output filename is reported as an
error. The source folder must be writable.

## Supported audio

- **WAV and AIFF** containing integer PCM audio.
- **Apple Lossless (ALAC)** in M4A or CAF containers.
- **Mono and stereo**, preserving the source sample rate and integer bit depth.

Lossy codecs such as MP3 and AAC, floating-point PCM, and audio with more than two
channels are not accepted. The app checks the audio codec, not just the filename
extension: an `.m4a` containing AAC is rejected. It cannot detect whether a
lossless file was previously converted from a lossy source.

Audio tags and artwork are not copied to the output files.

## AI disclosure

Most of the code in this project was written by an AI agent under human direction.
