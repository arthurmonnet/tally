import SwiftUI

struct ToolsView: View {
    @Bindable var state: OnboardingState

    @State private var showOtherEditor = false
    @State private var otherEditorName = ""
    @State private var isRecordingShortcut = false

    private let editors = ["Cursor", "VS Code", "Xcode", "Vim/Neovim"]
    private let launchers = ["Raycast", "Spotlight", "Alfred"]
    private let llmApps = ["Claude.ai", "ChatGPT", "Claude Code", "Cursor (AI)"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("What do you use?")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .center)

                // Code editor
                VStack(alignment: .leading, spacing: 8) {
                    Text("Code editor")
                        .font(.headline)

                    ChipGroup(
                        options: editors + ["Other"],
                        selection: Binding(
                            get: {
                                var set = state.selectedEditors
                                if showOtherEditor { set.insert("Other") }
                                return set
                            },
                            set: { newValue in
                                let hadOther = showOtherEditor
                                showOtherEditor = newValue.contains("Other")
                                var filtered = newValue
                                filtered.remove("Other")
                                state.selectedEditors = filtered
                                if !hadOther && showOtherEditor {
                                    otherEditorName = ""
                                }
                            }
                        )
                    )

                    if showOtherEditor {
                        TextField("App name", text: $otherEditorName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)
                            .onSubmit {
                                if !otherEditorName.isEmpty {
                                    state.selectedEditors.insert(otherEditorName)
                                }
                            }
                    }
                }

                // Launcher
                VStack(alignment: .leading, spacing: 8) {
                    Text("Launcher")
                        .font(.headline)

                    SingleChipGroup(
                        options: launchers,
                        selection: Binding(
                            get: { state.selectedLauncher.capitalized },
                            set: { state.selectedLauncher = $0.lowercased() }
                        )
                    )

                    if state.selectedLauncher != "spotlight" {
                        HStack(spacing: 8) {
                            Text("Launcher shortcut:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(state.launcherShortcut)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.secondary.opacity(0.1))
                                )

                            Button(isRecordingShortcut ? "Press keys..." : "Change") {
                                isRecordingShortcut = true
                            }
                            .font(.caption)
                            .disabled(isRecordingShortcut)
                        }
                        .onKeyPress(phases: .down) { keyPress in
                            guard isRecordingShortcut else { return .ignored }
                            let parts = shortcutParts(from: keyPress)
                            if !parts.isEmpty {
                                state.launcherShortcut = parts
                                isRecordingShortcut = false
                            }
                            return .handled
                        }
                    }
                }

                // LLM apps
                VStack(alignment: .leading, spacing: 8) {
                    Text("LLM apps (to track AI time)")
                        .font(.headline)

                    ChipGroup(
                        options: llmApps,
                        selection: $state.selectedLLMApps
                    )
                }

                // Git repos
                VStack(alignment: .leading, spacing: 8) {
                    Text("Git repos (for commit/stash tracking)")
                        .font(.headline)

                    FolderDropZone(label: "Drop folders or browse...") { urls in
                        let validRepos = urls.filter { url in
                            let gitDir = url.appendingPathComponent(".git")
                            return FileManager.default.fileExists(atPath: gitDir.path)
                        }
                        for repo in validRepos where !state.gitRepos.contains(repo) {
                            state.gitRepos.append(repo)
                        }
                    }

                    ForEach(state.gitRepos, id: \.path) { repo in
                        HStack {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(.green)
                            Text(repo.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                                .font(.system(size: 12, design: .monospaced))
                            Spacer()
                            Button {
                                state.gitRepos.removeAll { $0 == repo }
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button("Browse...") {
                        browseForRepo()
                    }
                    .font(.caption)
                }
            }
            .padding(32)
        }

        VStack(spacing: 8) {
            Button("Continue") {
                if showOtherEditor && !otherEditorName.isEmpty {
                    state.selectedEditors.insert(otherEditorName)
                }
                state.advance()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Skip — use defaults") {
                state.advance()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }

    private func browseForRepo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "Select folders containing git repos"

        if panel.runModal() == .OK {
            for url in panel.urls {
                let gitDir = url.appendingPathComponent(".git")
                if FileManager.default.fileExists(atPath: gitDir.path) {
                    if !state.gitRepos.contains(url) {
                        state.gitRepos.append(url)
                    }
                }
            }
        }
    }

    private func shortcutParts(from keyPress: KeyPress) -> String {
        var parts: [String] = []
        if keyPress.modifiers.contains(.command) { parts.append("cmd") }
        if keyPress.modifiers.contains(.option) { parts.append("alt") }
        if keyPress.modifiers.contains(.control) { parts.append("ctrl") }
        if keyPress.modifiers.contains(.shift) { parts.append("shift") }

        let char = keyPress.characters.lowercased()
        if char == " " {
            parts.append("space")
        } else if !char.isEmpty {
            parts.append(char)
        }

        return parts.joined(separator: "+")
    }
}
