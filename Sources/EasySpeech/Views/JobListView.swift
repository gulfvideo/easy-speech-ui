import AppKit
import SwiftUI

struct JobListView: View {
    @Environment(JobQueue.self) private var queue
    @Binding var selection: Job.ID?

    var body: some View {
        Group {
            if queue.jobs.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(minWidth: 220)
    }

    private var list: some View {
        List(selection: $selection) {
            Section("Files") {
                ForEach(queue.jobs) { job in
                    JobRow(job: job)
                        .tag(job.id)
                        .contextMenu { contextMenu(for: job) }
                }
                .onDelete { indexSet in
                    for index in indexSet { queue.remove(queue.jobs[index]) }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { footer }
        // Delete key removes the selection, as it does in every Mac list.
        .onDeleteCommand {
            guard let selection, let job = queue.jobs.first(where: { $0.id == selection }) else { return }
            queue.remove(job)
        }
    }

    @ViewBuilder
    private func contextMenu(for job: Job) -> some View {
        Button("Copy Transcript") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(job.transcript.plainText, forType: .string)
        }
        .disabled(job.transcript.isEmpty)

        Button("Reveal Output in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(job.outputs)
        }
        .disabled(job.outputs.isEmpty)

        Button("Show Original in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([job.url])
        }

        Divider()

        Button("Move to Top of Queue") { queue.moveToTopOfQueue(job) }
            .disabled(!queue.canMoveToTopOfQueue(job))

        Divider()

        Button("Transcribe Again") { queue.retry(job) }
            .disabled(!job.state.isTerminal)

        Button("Remove from Queue", role: .destructive) { queue.remove(job) }
            .disabled(job.state.isActive)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if queue.isProcessing {
                ProgressView().controlSize(.small)
                Text("\(queue.pendingCount) left")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(queue.jobs.count) file\(queue.jobs.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Clear") { queue.clearFinished() }
                .buttonStyle(.link)
                .disabled(!queue.jobs.contains { $0.state.isTerminal })
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Files", systemImage: "waveform")
        } description: {
            Text("Drop audio or video here, or press ⌘O.")
        } actions: {
            Button("Open…") { FilePicker.presentAndAdd(to: queue) }
        }
    }
}

struct JobRow: View {
    let job: Job

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(job.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if case .transcribing(let progress) = job.state {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                } else {
                    Text(detailLine)
                        .font(.caption)
                        .foregroundStyle(job.isFailed ? Color.red : Color.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
        .help(job.url.path)
        // Let the row be dragged back out to the Finder or another app.
        .draggable(job.outputs.first ?? job.url)
    }

    private var detailLine: String {
        switch job.state {
        case .finished:
            var parts: [String] = []
            if let duration = job.duration {
                parts.append(SubtitleWriter.shortTimecode(duration))
            }
            if let speed = job.speedFactor, speed > 0 {
                parts.append(String(format: "%.0f× realtime", speed))
            }
            return parts.isEmpty ? "Done" : parts.joined(separator: " · ")
        default:
            return job.state.label
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.state {
        case .queued:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .preparing, .writing:
            ProgressView().controlSize(.small)
        case .transcribing:
            Image(systemName: "waveform").foregroundStyle(Color.accentColor)
        case .translating:
            Image(systemName: "character.bubble").foregroundStyle(Color.accentColor)
        case .finished:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "xmark.circle").foregroundStyle(.secondary)
        }
    }
}

private extension Job {
    var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }
}
