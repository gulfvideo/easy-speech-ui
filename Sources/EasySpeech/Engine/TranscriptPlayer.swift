import AVFoundation
import Foundation
import Observation

/// Plays the source media alongside its transcript so a line can be checked by ear.
///
/// Uses `AVPlayer` rather than `AVAudioPlayer` because the sources are just as likely to
/// be video — a lecture recording or a service — and this way the audio track plays
/// without any special casing.
@MainActor
@Observable
final class TranscriptPlayer {

    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// The file currently loaded, so the view knows whether playback belongs to it.
    private(set) var url: URL?

    private var player: AVPlayer?
    private var observer: Any?

    deinit {
        // AVPlayer's observer token is safe to drop; the player is torn down with self.
    }

    /// Loads `url` if it isn't already loaded. Returns false when the file has gone.
    @discardableResult
    func prepare(_ url: URL) -> Bool {
        if self.url == url, player != nil { return true }
        guard FileManager.default.fileExists(atPath: url.path) else {
            unload()
            return false
        }

        unload()
        let player = AVPlayer(url: url)
        self.player = player
        self.url = url

        // Quarter-second ticks: fine enough to track the spoken line, coarse enough not
        // to redraw the transcript constantly.
        observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = time.seconds
                if let item = player.currentItem, item.duration.isNumeric {
                    self.duration = item.duration.seconds
                }
                if player.timeControlStatus == .paused,
                   self.isPlaying,
                   self.currentTime >= self.duration - 0.05 {
                    self.isPlaying = false
                }
            }
        }
        return true
    }

    func unload() {
        if let observer, let player { player.removeTimeObserver(observer) }
        observer = nil
        player?.pause()
        player = nil
        url = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    /// Jumps to `time` and starts playing — the click-a-line gesture.
    func play(_ url: URL, at time: TimeInterval) {
        guard prepare(url) else { return }
        seek(to: time)
        player?.play()
        isPlaying = true
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func seek(to time: TimeInterval) {
        // Exact seeking; the default tolerance would land on a keyframe and miss the line.
        player?.seek(to: CMTime(seconds: max(0, time), preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = max(0, time)
    }

    /// The segment being spoken now, so the view can highlight it.
    func activeSegmentID(in transcript: Transcript) -> TranscriptSegment.ID? {
        guard isPlaying || currentTime > 0 else { return nil }
        return transcript.segments.first { currentTime >= $0.start && currentTime < $0.end }?.id
    }
}
