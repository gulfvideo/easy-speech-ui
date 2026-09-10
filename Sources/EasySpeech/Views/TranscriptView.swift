import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TranscriptView: View {
    let job: Job?

    @AppStorage("transcriptShowTimestamps") private var showTimestamps = false
    @State private var searchText = ""

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
                        SegmentRow(segment: segment, showTimestamp: showTimestamps)
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

    private func statusBar(_ job: Job) -> some View {
        HStack(spacing: 12) {
            Label(SubtitleWriter.shortTimecode(job.transcript.totalDuration), systemImage: "timer")
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

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let contents: String = switch url.pathExtension.lowercased() {
        case "srt": SubtitleWriter.srt(for: job.transcript)
        case "vtt": SubtitleWriter.vtt(for: job.transcript)
        default: SubtitleWriter.text(for: job.transcript, timestamps: showTimestamps)
        }
        try? contents.write(to: url, atomically: true, encoding: .utf8)
    }
}

struct SegmentRow: View {
    let segment: TranscriptSegment
    let showTimestamp: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if showTimestamp {
                Text(SubtitleWriter.shortTimecode(segment.start))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .trailing)
            }
            Text(segment.text)
                .font(.system(size: 14))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
