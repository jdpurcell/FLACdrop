import Foundation
import AVFoundation
import CFLAC

final class Decoded {
    var samples: [Int32] = []
    var failed = false
}
func flacPCM(_ url: URL) -> [Int32] {
    let result = Decoded()
    let decoder = FLAC__stream_decoder_new()!
    defer { FLAC__stream_decoder_delete(decoder) }
    let context = Unmanaged.passUnretained(result).toOpaque()
    let status = FLAC__stream_decoder_init_file(decoder, url.path, { _, frame, buffers, context in
        let result = Unmanaged<Decoded>.fromOpaque(context!).takeUnretainedValue()
        let header = frame!.pointee.header
        for index in 0..<Int(header.blocksize) {
            for channel in 0..<Int(header.channels) {
                result.samples.append(buffers![channel]![index] << (32 - header.bits_per_sample))
            }
        }
        return FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE
    }, nil, { _, _, context in
        Unmanaged<Decoded>.fromOpaque(context!).takeUnretainedValue().failed = true
    }, context)
    precondition(status == FLAC__STREAM_DECODER_INIT_STATUS_OK)
    precondition(FLAC__stream_decoder_process_until_end_of_stream(decoder) != 0)
    precondition(!result.failed)
    return result.samples
}
func pcm(_ url: URL) throws -> [Int32] {
    var reference: ExtAudioFileRef?
    precondition(ExtAudioFileOpenURL(url as CFURL, &reference) == noErr)
    let file = reference!
    defer { ExtAudioFileDispose(file) }
    var format = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout.size(ofValue: format))
    precondition(ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileDataFormat, &size, &format) == noErr)
    let channels = format.mChannelsPerFrame
    format = AudioStreamBasicDescription(mSampleRate: format.mSampleRate, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 4 * channels, mFramesPerPacket: 1, mBytesPerFrame: 4 * channels,
        mChannelsPerFrame: channels, mBitsPerChannel: 32, mReserved: 0)
    precondition(ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, size, &format) == noErr)
    var result: [Int32] = []
    var storage = [Int32](repeating: 0, count: 8192 * Int(channels))
    while true {
        var count: UInt32 = 8192
        storage.withUnsafeMutableBytes { bytes in
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: channels, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
            precondition(ExtAudioFileRead(file, &count, &list) == noErr)
        }
        if count == 0 { return result }
        result.append(contentsOf: storage.prefix(Int(count * channels)))
    }
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let options = EncodingOptions(compression: 8, verify: true, threads: 4)
let shuffled = [13, 2, 10, 1, 9, 3, 12, 5, 4, 11, 8, 7, 6].map {
    directory.appendingPathComponent("\($0).wav")
}
precondition(naturallySortedFiles(shuffled).map(\.lastPathComponent) == (1...13).map { "\($0).wav" })
print("PASS: natural filename ordering 1 through 13")
for name in ["pcm8.wav", "pcm16.wav", "pcm24.wav", "pcm32.wav", "mono.wav", "integer.aiff", "lossless.m4a"] {
    let input = directory.appendingPathComponent(name)
    var values: [Double] = []
    try encodeFile(input, options: options) { values.append($0) }
    let output = input.deletingPathExtension().appendingPathExtension("flac")
    let equalSamples = try pcm(input) == flacPCM(output)
    precondition(equalSamples, "Samples changed: \(name)")
    precondition(values.last == 1)
    let before = try Data(contentsOf: output)
    do { try encodeFile(input, options: options) { _ in }; fatalError("Overwrote output") }
    catch { precondition(error.localizedDescription.contains("already exists")) }
    let after = try Data(contentsOf: output)
    precondition(after == before)
    print("PASS: \(name) exact PCM round-trip and no overwrite")
}
for name in ["float.wav", "surround.wav", "lossy.m4a", "broken.wav"] {
    let input = directory.appendingPathComponent(name)
    do { try encodeFile(input, options: options) { _ in }; fatalError("Accepted \(name)") }
    catch { print("PASS: rejected \(name): \(error.localizedDescription)") }
    precondition(!FileManager.default.fileExists(atPath: input.deletingPathExtension().appendingPathExtension("flac").path))
}
let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path)
precondition(!remaining.contains { $0.hasPrefix(".flacdrop-") })
print("All integration checks passed")
