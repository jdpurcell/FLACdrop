import Foundation
import AudioToolbox
import CFLAC
import Darwin

func naturallySortedFiles(_ urls: [URL]) -> [URL] {
    urls.sorted {
        let order = $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
        return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
    }
}

struct EncodingOptions: Sendable {
    let compression: UInt32
    let verify: Bool
    var threads: UInt32 = UInt32(min(128, max(1, ProcessInfo.processInfo.activeProcessorCount)))
}

struct EncodingFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func checked(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else {
        throw EncodingFailure(message: "\(operation) failed (Core Audio error \(status)).")
    }
}

/// Reads signed, high-aligned 32-bit PCM, then restores the source's integer scale.
/// Never resamples, downmixes, or passes through floating-point PCM.
func encodeFile(_ input: URL, options: EncodingOptions,
                progress: (Double) -> Void) throws {
    let output = input.deletingPathExtension().appendingPathExtension("flac")
    guard !FileManager.default.fileExists(atPath: output.path) else {
        throw EncodingFailure(message: "Output already exists: \(output.lastPathComponent)")
    }
    var file: ExtAudioFileRef?
    try checked(ExtAudioFileOpenURL(input as CFURL, &file), "Opening input")
    guard let file else { throw EncodingFailure(message: "Could not open input.") }
    defer { ExtAudioFileDispose(file) }
    var source = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout.size(ofValue: source))
    try checked(ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileDataFormat, &size, &source), "Reading source format")
    guard (1...2).contains(source.mChannelsPerFrame) else {
        throw EncodingFailure(message: "Only mono and stereo audio are supported.")
    }
    let bits: UInt32
    switch source.mFormatID {
    case kAudioFormatLinearPCM:
        guard source.mFormatFlags & kAudioFormatFlagIsFloat == 0 else {
            throw EncodingFailure(message: "Floating-point PCM is not supported.")
        }
        bits = source.mBitsPerChannel
    case kAudioFormatAppleLossless:
        switch source.mFormatFlags {
        case kAppleLosslessFormatFlag_16BitSourceData: bits = 16
        case kAppleLosslessFormatFlag_20BitSourceData: bits = 20
        case kAppleLosslessFormatFlag_24BitSourceData: bits = 24
        case kAppleLosslessFormatFlag_32BitSourceData: bits = 32
        default: throw EncodingFailure(message: "Unknown ALAC source bit depth.")
        }
    default:
        throw EncodingFailure(message: "Unsupported codec. Only integer PCM and Apple Lossless are accepted.")
    }
    guard (4...32).contains(bits), source.mSampleRate > 0,
          source.mSampleRate.rounded() == source.mSampleRate,
          source.mSampleRate <= 655350 else {
        throw EncodingFailure(message: "Unsupported bit depth or sample rate.")
    }
    var length: Int64 = 0
    size = UInt32(MemoryLayout.size(ofValue: length))
    try checked(ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileLengthFrames, &size, &length), "Reading audio length")
    let channels = source.mChannelsPerFrame
    var client = AudioStreamBasicDescription(mSampleRate: source.mSampleRate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian,
        mBytesPerPacket: 4 * channels, mFramesPerPacket: 1,
        mBytesPerFrame: 4 * channels, mChannelsPerFrame: channels,
        mBitsPerChannel: 32, mReserved: 0)
    try checked(ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat,
        UInt32(MemoryLayout.size(ofValue: client)), &client), "Configuring integer decoding")
    guard let encoder = FLAC__stream_encoder_new() else {
        throw EncodingFailure(message: "Could not allocate encoder.")
    }
    defer { FLAC__stream_encoder_delete(encoder) }
    guard FLAC__stream_encoder_set_channels(encoder, channels) != 0,
          FLAC__stream_encoder_set_bits_per_sample(encoder, bits) != 0,
          FLAC__stream_encoder_set_sample_rate(encoder, UInt32(source.mSampleRate)) != 0,
          FLAC__stream_encoder_set_compression_level(encoder, options.compression) != 0,
          FLAC__stream_encoder_set_verify(encoder, options.verify ? 1 : 0) != 0,
          FLAC__stream_encoder_set_total_samples_estimate(encoder, UInt64(max(0, length))) != 0,
          FLAC__stream_encoder_set_num_threads(encoder, options.threads) == FLAC__STREAM_ENCODER_SET_NUM_THREADS_OK else {
        throw EncodingFailure(message: "Could not configure FLAC encoder.")
    }
    // Encode privately, then publish using link(2): atomically fails if output exists.
    let temporary = input.deletingLastPathComponent().appendingPathComponent(".flacdrop-\(UUID().uuidString).tmp")
    defer { try? FileManager.default.removeItem(at: temporary) }
    let status = temporary.path.withCString { FLAC__stream_encoder_init_file(encoder, $0, nil, nil) }
    guard status == FLAC__STREAM_ENCODER_INIT_STATUS_OK else {
        throw EncodingFailure(message: "Could not initialize output (FLAC error \(status.rawValue)).")
    }
    func encoderError() -> EncodingFailure {
        let description = FLAC__stream_encoder_get_resolved_state_string(encoder).map { String(cString: $0) } ?? "Unknown encoder error"
        return EncodingFailure(message: description)
    }
    var pcm = [Int32](repeating: 0, count: 16384 * Int(channels))
    var processed: Int64 = 0
    while true {
        var frames: UInt32 = 16384
        try pcm.withUnsafeMutableBytes { bytes in
            var buffer = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                mNumberChannels: channels, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
            try checked(ExtAudioFileRead(file, &frames, &buffer), "Reading audio")
        }
        if frames == 0 { break }
        for i in 0..<(Int(frames) * Int(channels)) { pcm[i] >>= (32 - bits) }
        let ok = pcm.withUnsafeBufferPointer {
            FLAC__stream_encoder_process_interleaved(encoder, $0.baseAddress, frames)
        }
        guard ok != 0 else { throw encoderError() }
        processed += Int64(frames)
        progress(length > 0 ? min(0.99, Double(processed) / Double(length)) : 0)
    }
    guard processed == length else { throw EncodingFailure(message: "Input ended before the expected number of samples.") }
    guard FLAC__stream_encoder_finish(encoder) != 0 else { throw encoderError() }
    guard link(temporary.path, output.path) == 0 else {
        let code = errno
        throw EncodingFailure(message: code == EEXIST ? "Output already exists: \(output.lastPathComponent)" : "Could not save output: \(String(cString: strerror(code)))")
    }
    progress(1)
}
