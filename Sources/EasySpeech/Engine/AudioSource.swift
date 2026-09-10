import AVFoundation
import Speech
import OSLog

enum AudioSourceError: LocalizedError {
    case noAudioTrack
    case unreadable(String)
    case bufferAllocationFailed

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            "This file has no audio track."
        case .unreadable(let detail):
            detail
        case .bufferAllocationFailed:
            "Could not allocate an audio buffer."
        }
    }
}

/// Decodes any AVFoundation-readable media into the PCM format SpeechAnalyzer wants.
///
/// EasyWhisperUI shells out to FFmpeg and writes a temporary 44.1 kHz WAV next to the
/// source before every run. AVFoundation decodes and resamples in one pass, in-process,
/// so there is no temp file, no conversion wait, and no bundled binary. FFmpeg is used
/// only as a fallback for containers AVFoundation refuses (ogg, opus, mkv, wma).
enum AudioSource {

    private static let log = Logger(subsystem: "com.easyspeech.ui", category: "audio")

    /// Extensions AVFoundation handles natively.
    static let nativeExtensions: Set<String> = [
        "wav", "aiff", "aif", "aifc", "caf", "mp3", "m4a", "aac", "adts",
        "mp4", "m4v", "mov", "flac", "au", "snd", "amr", "3gp", "3g2"
    ]

    /// Extensions we can still open, but only by way of FFmpeg.
    static let ffmpegExtensions: Set<String> = ["ogg", "oga", "opus", "mkv", "webm", "wma", "avi", "flv", "wmv", "ts"]

    static var allExtensions: [String] { Array(nativeExtensions.union(ffmpegExtensions)).sorted() }

    // MARK: - Duration

    static func duration(of url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return duration.isNumeric ? duration.seconds : 0
    }

    // MARK: - FFmpeg fallback

    /// Locates an FFmpeg binary if the user happens to have one.
    static func locateFFmpeg() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
            "/opt/local/bin/ffmpeg"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    static func needsFFmpeg(_ url: URL) -> Bool {
        ffmpegExtensions.contains(url.pathExtension.lowercased())
    }

    /// Converts an unsupported container to a temporary 16 kHz mono WAV.
    /// The caller owns the returned file and must delete it.
    static func transcodeWithFFmpeg(_ url: URL, sampleRate: Double) throws -> URL {
        guard let ffmpeg = locateFFmpeg() else {
            throw AudioSourceError.unreadable(
                "\(url.pathExtension.uppercased()) files need FFmpeg, which wasn't found. Install it with `brew install ffmpeg`, or convert the file to M4A first."
            )
        }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("easyspeech-\(UUID().uuidString).wav")

        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = [
            "-hide_banner", "-loglevel", "error", "-y",
            "-i", url.path,
            "-vn", "-sn", "-dn", "-map_metadata", "-1",
            "-ac", "1",
            "-ar", String(Int(sampleRate)),
            "-c:a", "pcm_s16le",
            output.path
        ]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()

        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "unknown error"
            throw AudioSourceError.unreadable("FFmpeg could not decode this file: \(message)")
        }
        return output
    }

    // MARK: - PCM streaming

    /// A pull-based sequence over the file's audio.
    ///
    /// This deliberately is **not** an `AsyncStream`. AsyncStream buffers without bound,
    /// so a producer that decodes faster than the recognizer consumes will hold the whole
    /// file in memory — a 3.6-hour podcast decodes in ~12 seconds and parks ~420 MB of
    /// PCM. Driving the reader from `next()` instead means SpeechAnalyzer pulls one buffer
    /// at a time and memory stays flat regardless of how long the recording is.
    struct InputSequence: AsyncSequence, Sendable {
        typealias Element = AnalyzerInput

        let url: URL
        let format: AVAudioFormat

        func makeAsyncIterator() -> Iterator {
            Iterator(url: url, format: format)
        }

        final class Iterator: AsyncIteratorProtocol {
            private let url: URL
            private let format: AVAudioFormat
            private var reader: AVAssetReader?
            private var output: AVAssetReaderTrackOutput?
            private var finished = false

            init(url: URL, format: AVAudioFormat) {
                self.url = url
                self.format = format
            }

            deinit {
                if reader?.status == .reading { reader?.cancelReading() }
            }

            func next() async throws -> AnalyzerInput? {
                if finished { return nil }
                if reader == nil { try await start() }

                guard let reader, let output else { return nil }

                while true {
                    try Task.checkCancellation()

                    guard let sampleBuffer = output.copyNextSampleBuffer() else {
                        finished = true
                        if reader.status == .failed {
                            throw AudioSourceError.unreadable(
                                reader.error?.localizedDescription ?? "Decoding failed partway through."
                            )
                        }
                        return nil
                    }

                    let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    if let buffer = makePCMBuffer(from: sampleBuffer, format: format) {
                        return AnalyzerInput(buffer: buffer, bufferStartTime: presentationTime)
                    }
                    // Empty or undecodable packet — keep going rather than ending the file.
                }
            }

            private func start() async throws {
                let asset = AVURLAsset(url: url,
                                       options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
                guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
                    throw AudioSourceError.noAudioTrack
                }

                let reader = try AVAssetReader(asset: asset)

                // Ask the reader to resample and downmix straight into the analyzer's own
                // format. That format is Int16 at 16 kHz today, but read it from `format`
                // rather than assuming — Apple is free to change it.
                let description = format.streamDescription.pointee
                let isFloat = (description.mFormatFlags & kAudioFormatFlagIsFloat) != 0

                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: Int(format.channelCount),
                    AVLinearPCMBitDepthKey: Int(description.mBitsPerChannel),
                    AVLinearPCMIsFloatKey: isFloat,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]

                let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
                output.alwaysCopiesSampleData = false
                guard reader.canAdd(output) else {
                    throw AudioSourceError.unreadable("This file's audio format can't be decoded.")
                }
                reader.add(output)

                guard reader.startReading() else {
                    throw AudioSourceError.unreadable(
                        reader.error?.localizedDescription ?? "Could not start reading the file."
                    )
                }

                self.reader = reader
                self.output = output
            }
        }
    }

    /// Copies decoded LPCM out of a CMSampleBuffer into an AVAudioPCMBuffer.
    ///
    /// Works for any sample format by copying raw bytes into the buffer's own
    /// AudioBufferList rather than reaching for `floatChannelData`, which is nil
    /// whenever the analyzer asks for integer samples.
    private static func makePCMBuffer(from sampleBuffer: CMSampleBuffer,
                                      format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format,
                                               frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

        let destinationList = pcmBuffer.mutableAudioBufferList
        guard let destination = destinationList.pointee.mBuffers.mData else { return nil }
        let capacity = Int(destinationList.pointee.mBuffers.mDataByteSize)

        var blockBuffer: CMBlockBuffer?
        var sourceList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: format.channelCount, mDataByteSize: 0, mData: nil)
        )

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &sourceList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr,
              let source = sourceList.mBuffers.mData else { return nil }

        let byteCount = min(capacity, Int(sourceList.mBuffers.mDataByteSize))
        guard byteCount > 0 else { return nil }
        memcpy(destination, source, byteCount)

        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        if bytesPerFrame > 0 {
            pcmBuffer.frameLength = AVAudioFrameCount(byteCount / bytesPerFrame)
        }
        return pcmBuffer
    }
}
