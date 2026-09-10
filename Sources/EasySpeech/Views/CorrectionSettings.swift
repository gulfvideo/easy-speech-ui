import AppKit
import SwiftUI

/// Editor for the "heard → should say" rules applied to every transcript.
struct CorrectionSettings: View {
    @Environment(AppSettings.self) private var settings
    @State private var selection = Set<Correction.ID>()
    @State private var heard = ""
    @State private var replacement = ""

    private var rules: [Correction] { settings.corrections }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recognition errors cluster on names the model has no reason to expect. When you spot one, add it here and it's fixed in every transcript from then on.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)

            Table(rules, selection: $selection) {
                TableColumn("EasySpeech hears") { rule in
                    Text(rule.heard).foregroundStyle(.secondary)
                }
                TableColumn("It should say") { rule in
                    Text(rule.replacement)
                }
            }
            .tableStyle(.bordered)
            .onDeleteCommand(perform: removeSelected)
            .overlay {
                if rules.isEmpty {
                    ContentUnavailableView("No Corrections",
                                           systemImage: "character.cursor.ibeam",
                                           description: Text("Add a name the recognizer keeps getting wrong."))
                }
            }

            HStack(spacing: 8) {
                TextField("Hears", text: $heard)
                    .textFieldStyle(.roundedBorder)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                TextField("Should say", text: $replacement)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add).disabled(!canAdd)
                Button("Remove", action: removeSelected).disabled(selection.isEmpty)
            }
            .padding(12)
        }
        .frame(minHeight: 300)
    }

    private var canAdd: Bool {
        !heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func add() {
        guard canAdd else { return }
        let rule = Correction(heard: heard.trimmingCharacters(in: .whitespacesAndNewlines),
                              replacement: replacement.trimmingCharacters(in: .whitespacesAndNewlines))
        // Editing an existing rule replaces it rather than adding a duplicate.
        var updated = rules.filter { $0.id != rule.id }
        updated.append(rule)
        settings.corrections = updated.sorted { $0.replacement.localizedStandardCompare($1.replacement) == .orderedAscending }
        heard = ""
        replacement = ""
    }

    private func removeSelected() {
        guard !selection.isEmpty else { return }
        settings.corrections = rules.filter { !selection.contains($0.id) }
        selection.removeAll()
    }
}
