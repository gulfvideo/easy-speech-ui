import AVFoundation
import Speech

enum AudioSourceError: LocalizedError {
    case noAudioTrack
    case unreadable(String)
    case damaged
    case bufferAllocationFailed

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            "This file has no audio track."
        case .unreadable(let detail):
            detail
        case .damaged:
            // The caller always shows the filename alongside this, so don't repeat it.
            "The file couldn't be opened. It may be empty, incomplete, or not really the format its name suggests."
        case .bufferAllocationFailed:
            "Could not allocate an audio buffer."
        }
    }
}

/// Decodes any AVFoundation-readable media into the PCM format SpeechAnalyzer wants.
///
/// AVFoundation decodes and resamples in one pass, in-process, so there is no temporary
/// WAV written beside the source, no conversion wait before recognition starts, and no
/// transcoder binary to bundle. FFmpeg is used only as a fallback for the containers
/// AVFoundation refuses (ogg, opus, mkv, wma), and only if the user happens to have it.
enum AudioSource {

    /// Extensions AVFoundation handles natively.
    static let nativeExtensions: Set<String> = [
        "wav", "aiff", "aif", "aifc", "caf", "mp3", "m4a", "aac", "adts",
        "mp4", "m4v", "mov", "flac", "au", "snd", "amr", "3gp", "3g2"
    ]

    /// Extensions we can still open, but only by way of FFmpeg.
    static let ffmpegExtensions: Set<String> = ["ogg", "oga", "opus", "mkv", "webm", "wma", "avi", "flv", "wmv", "ts"]

    /// Membership set, built once — this is consulted for every file added to the queue.
    static let supportedExtensions: Set<String> = nativeExtensions.union(ffmpegExtensions)

    // MARK: - Duration

    static func duration(of url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            return duration.isNumeric ? duration.seconds : 0
        } catch {
            // This is the first thing that touches the file, so a truncated or
            // mislabelled one fails here — with an AVFoundation message like
            // "Operation Stopped" that means nothing to anyone.
            throw AudioSourceError.damaged
        }
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

        /// Decodes the file's audio into the analyzer's format, one chunk at a time.
        ///
        /// Two backends. `AVAudioFile` is tried first and handles every audio-only container;
        /// it reads through ExtAudioFile and brings up no pipeline of its own. `AVAssetReader`
        /// is the fallback, for video containers `AVAudioFile` cannot open.
        ///
        /// The order matters for more than tidiness. Each `AVAssetReader` audio decode starts a
        /// CoreMedia pipeline with its own `coremedia.audioqueue`, `readerOfflineMixer` and
        /// `audiomentor` threads. Six of those at once deadlocked inside AudioToolbox's
        /// AudioQueue XPC bridge — "dispatch_sync called on queue already owned by current
        /// thread" — after nineteen hours of batch work. There are no app frames on that stack,
        /// so it is not a bug this code can fix; routing ordinary audio away from that pipeline
        /// avoids provoking it, and decodes faster besides.
        final class Iterator: AsyncIteratorProtocol {
            private let url: URL
            private let format: AVAudioFormat

            private enum Backend {
                case audioFile(AVAudioFile, AVAudioConverter, AVAudioPCMBuffer)
                case assetReader(AVAssetReader, AVAssetReaderTrackOutput)
            }
            private var backend: Backend?
            private var finished = false
            /// Output frames emitted so far, which is what dates each buffer.
            private var framesEmitted: Int64 = 0

            /// Input frames per read. Large enough that per-chunk overhead disappears, small
            /// enough that memory stays flat on a multi-hour file.
            private static let chunkFrames: AVAudioFrameCount = 16384

            init(url: URL, format: AVAudioFormat) {
                self.url = url
                self.format = format
            }

            deinit {
                if case .assetReader(let reader, _) = backend, reader.status == .reading {
                    reader.cancelReading()
                }
            }

            func next() async throws -> AnalyzerInput? {
                if finished { return nil }
                if backend == nil { try await start() }

                switch backend {
                case .audioFile(let file, let converter, let scratch):
                    return try nextFromAudioFile(file, converter, scratch)
                case .assetReader(let reader, let output):
                    return try nextFromAssetReader(reader, output)
                case nil:
                    return nil
                }
            }

            // MARK: - AVAudioFile

            private func nextFromAudioFile(_ file: AVAudioFile,
                                           _ converter: AVAudioConverter,
                                           _ scratch: AVAudioPCMBuffer) throws -> AnalyzerInput? {
                while true {
                    try Task.checkCancellation()

                    guard file.framePosition < file.length else {
                        finished = true
                        return nil
                    }

                    scratch.frameLength = 0
                    do {
                        try file.read(into: scratch)
                    } catch {
                        // Running off the end mid-read is an ordinary stop, not a failure.
                        finished = true
                        return nil
                    }
                    guard scratch.frameLength > 0 else {
                        finished = true
                        return nil
                    }

                    let ratio = format.sampleRate / file.processingFormat.sampleRate
                    let capacity = AVAudioFrameCount(Double(scratch.frameLength) * ratio) + 1024
                    guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                        throw AudioSourceError.unreadable("Could not allocate a decode buffer.")
                    }

                    var conversionError: NSError?
                    var supplied = false
                    converter.convert(to: out, error: &conversionError) { _, status in
                        if supplied {
                            status.pointee = .noDataNow
                            return nil
                        }
                        supplied = true
                        status.pointee = .haveData
                        return scratch
                    }
                    if let conversionError {
                        throw AudioSourceError.unreadable(conversionError.localizedDescription)
                    }
                    guard out.frameLength > 0 else { continue }

                    let start = CMTime(value: framesEmitted, timescale: CMTimeScale(format.sampleRate))
                    framesEmitted += Int64(out.frameLength)
                    return AnalyzerInput(buffer: out, bufferStartTime: start)
                }
            }

            // MARK: - AVAssetReader

            private func nextFromAssetReader(_ reader: AVAssetReader,
                                             _ output: AVAssetReaderTrackOutput) throws -> AnalyzerInput? {
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

            // MARK: - Setup

            private func start() async throws {
                if let audioFile = try? AVAudioFile(forReading: url),
                   audioFile.length > 0,
                   let converter = AVAudioConverter(from: audioFile.processingFormat, to: format),
                   let scratch = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat,
                                                  frameCapacity: Self.chunkFrames) {
                    backend = .audioFile(audioFile, converter, scratch)
                    return
                }
                try await startAssetReader()
            }

            private func startAssetReader() async throws {
                let asset = AVURLAsset(url: url,
                                       options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

                // AVFoundation reports a truncated or mislabelled file with messages like
                // "Operation Stopped", which tells the user nothing.
                let tracks: [AVAssetTrack]
                do {
                    tracks = try await asset.loadTracks(withMediaType: .audio)
                } catch {
                    throw AudioSourceError.damaged
                }
                guard let track = tracks.first else {
                    throw AudioSourceError.noAudioTrack
                }

                let reader: AVAssetReader
                do {
                    reader = try AVAssetReader(asset: asset)
                } catch {
                    throw AudioSourceError.damaged
                }

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

                backend = .assetReader(reader, output)
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
