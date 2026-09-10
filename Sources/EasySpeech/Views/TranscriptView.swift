import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TranscriptView: View {
    let job: Job?

    @AppStorage("transcriptShowTimestamps") private var showTimestamps = false
    @State private var searchText = ""
    @State private var player = TranscriptPlayer()

    var body: some View {
        Group {
            if let job {
                if job.transcript.isEmpty {
                    placeholder(for: job)
                } else {
                    transcript(job)
                }
            } else {
                ContentUnavailableView("No Transcript",
                                       systemImage: "text.alignleft",
                                       description: Text("Select a file to see its transcript."))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportTranscript)) { _ in
            if let job, !job.transcript.isEmpty { export(job) }
        }
        // Selecting a different file shouldn't leave the previous one playing.
        .onChange(of: job?.id) { player.unload() }
        .onDisappear { player.unload() }
    }

    // MARK: - States

    @ViewBuilder
    private func placeholder(for job: Job) -> some View {
        switch job.state {
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't Transcribe", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
        case .queued:
            ContentUnavailableView("Waiting", systemImage: "clock",
                                   description: Text("\(job.displayName) is queued."))
        case .cancelled:
            ContentUnavailableView("Cancelled", systemImage: "xmark.circle",
                                   description: Text("Transcription was stopped."))
        default:
            VStack(spacing: 14) {
                ProgressView()
                Text(job.state.label).foregroundStyle(.secondary)
            }
        }
    }

    private func transcript(_ job: Job) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(filteredSegments(job)) { segment in
                        SegmentRow(segment: segment,
                                   showTimestamp: showTimestamps,
                                   isActive: activeSegment == segment.id,
                                   canPlay: mediaExists(job)) {
                            player.play(job.url, at: segment.start)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .textSelection(.enabled)

            Divider()
            statusBar(job)
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Find in transcript")
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $showTimestamps) {
                    Label("Timestamps", systemImage: "clock")
                }
                .help("Show a timestamp beside each line")
            }
            ToolbarItem {
                Menu {
                    Button("Copy Plain Text") { copy(job.transcript.plainText) }
                    Button("Copy with Timestamps") {
                        copy(SubtitleWriter.text(for: job.transcript, timestamps: true))
                    }
                    Button("Copy as SRT") { copy(SubtitleWriter.srt(for: job.transcript)) }
                    Divider()
                    Button("Export…") { export(job) }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .help("Copy or export this transcript")
            }
        }
    }

    private func mediaExists(_ job: Job) -> Bool {
        FileManager.default.fileExists(atPath: job.url.path)
    }

    private var activeSegment: TranscriptSegment.ID? {
        guard let job, player.url == job.url else { return nil }
        return player.activeSegmentID(in: job.transcript)
    }

    private func statusBar(_ job: Job) -> some View {
        HStack(spacing: 12) {
            Button {
                if player.url == job.url {
                    player.togglePlayPause()
                } else {
                    player.play(job.url, at: 0)
                }
            } label: {
                Image(systemName: player.isPlaying && player.url == job.url
                      ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Play the original audio — or click any line to hear it")
            .disabled(!FileManager.default.fileExists(atPath: job.url.path))

            if player.url == job.url, player.duration > 0 {
                Text("\(SubtitleWriter.shortTimecode(player.currentTime)) / \(SubtitleWriter.shortTimecode(player.duration))")
                    .font(.callout.monospacedDigit())
            } else {
                Label(SubtitleWriter.shortTimecode(job.transcript.totalDuration), systemImage: "timer")
            }
            Label("\(job.transcript.plainText.split(separator: " ").count) words", systemImage: "text.word.spacing")
            if let speed = job.speedFactor, speed > 0 {
                Label(String(format: "%.0f× realtime", speed), systemImage: "bolt.fill")
            }
            Spacer()
            if !job.outputs.isEmpty {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(job.outputs)
                } label: {
                    Label("\(job.outputs.count) file\(job.outputs.count == 1 ? "" : "s") written",
                          systemImage: "folder")
                }
                .buttonStyle(.link)
                .help(job.outputs.map(\.lastPathComponent).joined(separator: "\n"))
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func filteredSegments(_ job: Job) -> [TranscriptSegment] {
        guard !searchText.isEmpty else { return job.transcript.segments }
        return job.transcript.segments.filter {
            $0.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Actions

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func export(_ job: Job) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = job.url.deletingPathExtension().lastPathComponent
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "srt") ?? .plainText,
                                     UTType(filenameExtension: "vtt") ?? .plainText]
        panel.message = "Choose a format by extension: .txt, .srt or .vtt"

        PanelPresentation.present(panel) { accepted in
            guard accepted, let url = panel.url else { return }
            let contents: String = switch url.pathExtension.lowercased() {
            case "srt": SubtitleWriter.srt(for: job.transcript)
            case "vtt": SubtitleWriter.vtt(for: job.transcript)
            default: SubtitleWriter.text(for: job.transcript, timestamps: showTimestamps)
            }
            try? contents.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

struct SegmentRow: View {
    let segment: TranscriptSegment
    let showTimestamp: Bool
    var isActive = false
    var canPlay = false
    var play: () -> Void = {}

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // A real button in its own gutter, rather than a tap on the text: selectable
            // text swallows tap gestures, and losing selection to gain seeking would be a
            // bad trade. The gutter keeps its width so lines don't shift on hover.
            Button(action: play) {
                Image(systemName: isActive ? "speaker.wave.2.fill" : "play.fill")
                    .font(.caption)
                    .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor)
                                              : AnyShapeStyle(Color.secondary))
                    // Dimmed rather than hidden: a control that pops in and out as the
                    // pointer crosses lines reads as flicker.
                    .opacity(isActive ? 1 : (isHovering ? 0.9 : 0.22))
            }
            .buttonStyle(.plain)
            .disabled(!canPlay)
            .frame(width: 14)
            .help("Play from \(SubtitleWriter.shortTimecode(segment.start))")
            .accessibilityLabel("Play from \(SubtitleWriter.shortTimecode(segment.start))")

            if showTimestamp {
                Text(SubtitleWriter.shortTimecode(segment.start))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .frame(width: 50, alignment: .trailing)
            }

            Text(segment.text)
                .font(.system(size: 14))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.accentColor.opacity(0.12) : .clear)
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isActive)
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
