import SwiftUI

struct SetupView: View {
    @Binding var isSetupComplete: Bool
    @State private var currentStep = 0
    @State private var accessibilityGranted = false
    @State private var accessibilityTimer: Timer?

    // Step 2 — Tools
    @State private var codeEditor = "cursor"
    @State private var screenshotTool = "macos"
    @State private var launcher = "raycast"
    @State private var gitRepos: [String] = []
    @State private var llmApps: Set<String> = ["Claude"]

    // Step 3 — Screenshots
    @State private var screenshotFolder = "~/Desktop"
    @State private var detectedPatterns: [(tool: String, count: Int)] = []
    @State private var screenshotPatterns: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<3) { step in
                    Capsule()
                        .fill(step <= currentStep ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(height: 3)
                }
            }
            .padding()

            Spacer()

            switch currentStep {
            case 0:
                permissionsStep
            case 1:
                toolsStep
            case 2:
                screenshotStep
            default:
                EmptyView()
            }

            Spacer()
        }
        .frame(minWidth: 460, minHeight: 500)
        .onDisappear {
            accessibilityTimer?.invalidate()
        }
    }

    // MARK: - Step 1: Permissions

    private var permissionsStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Accessibility Permission")
                .font(.title2.bold())

            Text("Pulse needs Accessibility permission to count\nkeystrokes, clicks, and scroll distance.\n\nNo content is ever recorded — only counts.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if accessibilityGranted {
                Label("Permission granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            HStack(spacing: 12) {
                Button("Open System Settings") {
                    openAccessibilitySettings()
                    startAccessibilityPolling()
                }
                .buttonStyle(.borderedProminent)

                Button("I'll do it later") {
                    currentStep = 1
                }
                .buttonStyle(.bordered)
            }

            if accessibilityGranted {
                Button("Continue") {
                    currentStep = 1
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(32)
        .onAppear {
            accessibilityGranted = AXIsProcessTrusted()
            if !accessibilityGranted {
                startAccessibilityPolling()
            }
        }
    }

    // MARK: - Step 2: Tools

    private var toolsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your Tools")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .center)

            Group {
                Text("Code Editor")
                    .font(.headline)
                Picker("", selection: $codeEditor) {
                    Text("Cursor").tag("cursor")
                    Text("VS Code").tag("vscode")
                    Text("Xcode").tag("xcode")
                    Text("Vim/Neovim").tag("vim")
                    Text("Other").tag("other")
                }
                .pickerStyle(.segmented)
            }

            Group {
                Text("Launcher")
                    .font(.headline)
                Picker("", selection: $launcher) {
                    Text("Raycast").tag("raycast")
                    Text("Spotlight").tag("spotlight")
                    Text("Alfred").tag("alfred")
                }
                .pickerStyle(.segmented)
            }

            Group {
                Text("LLM Apps")
                    .font(.headline)
                HStack {
                    toggleChip("Claude", set: $llmApps)
                    toggleChip("ChatGPT", set: $llmApps)
                    toggleChip("Cursor AI", set: $llmApps)
                    toggleChip("Claude Code", set: $llmApps)
                }
            }

            Spacer()

            Button("Continue") {
                currentStep = 2
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(32)
    }

    // MARK: - Step 3: Screenshots

    private var screenshotStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Screenshot Folder")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                TextField("Folder path", text: $screenshotFolder)
                    .textFieldStyle(.roundedBorder)
                Button("Browse...") {
                    browseForFolder()
                }
            }

            if !detectedPatterns.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Detected:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(detectedPatterns, id: \.tool) { pattern in
                        Label("\(pattern.count) \(pattern.tool) screenshots", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            Button("Finish Setup") {
                saveConfig()
                isSetupComplete = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(32)
        .onAppear {
            scanScreenshotFolder()
        }
    }

    // MARK: - Helpers

    private func toggleChip(_ label: String, set: Binding<Set<String>>) -> some View {
        let isSelected = set.wrappedValue.contains(label)
        return Button(label) {
            if isSelected {
                set.wrappedValue.remove(label)
            } else {
                set.wrappedValue.insert(label)
            }
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? .accentColor : .secondary)
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                let trusted = AXIsProcessTrusted()
                accessibilityGranted = trusted
                if trusted {
                    accessibilityTimer?.invalidate()
                    accessibilityTimer = nil
                    currentStep = 1
                }
            }
        }
    }

    private func browseForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            screenshotFolder = url.path
            scanScreenshotFolder()
        }
    }

    private func scanScreenshotFolder() {
        let expandedPath = NSString(string: screenshotFolder).expandingTildeInPath
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: expandedPath) else { return }

        let imageExtensions = Set(["png", "jpg", "jpeg", "webp", "gif"])
        let imageFiles = contents
            .filter { file in
                let ext = (file as NSString).pathExtension.lowercased()
                return imageExtensions.contains(ext)
            }
            .suffix(30)

        let patterns: [(name: String, regex: String)] = [
            ("macOS native", "Screenshot \\d{4}-\\d{2}-\\d{2} at"),
            ("CleanShot X", "CleanShot \\d{4}-\\d{2}-\\d{2} at"),
            ("Old macOS", "Screen Shot \\d{4}-\\d{2}-\\d{2}"),
            ("Xnapper", "Xnapper-"),
            ("Kap", "Kapture \\d{4}-\\d{2}-\\d{2}"),
        ]

        var detected: [(tool: String, count: Int)] = []
        var matchedPatterns: [String] = []

        for (name, pattern) in patterns {
            let count = imageFiles.filter { file in
                file.range(of: pattern, options: .regularExpression) != nil
            }.count
            if count > 0 {
                detected.append((tool: name, count: count))
                matchedPatterns.append(pattern)
            }
        }

        detectedPatterns = detected
        screenshotPatterns = matchedPatterns
    }

    private func saveConfig() {
        let launcherShortcut: String
        switch launcher {
        case "raycast": launcherShortcut = "cmd+space"
        case "alfred": launcherShortcut = "alt+space"
        default: launcherShortcut = "cmd+space"
        }

        let llmTitles: [String] = llmApps.compactMap { app in
            switch app {
            case "Claude": return "claude.ai"
            case "ChatGPT": return "chatgpt.com"
            default: return nil
            }
        }

        let config = UserConfig(
            codeEditor: codeEditor,
            screenshotTool: screenshotTool,
            screenshotFolders: [screenshotFolder],
            screenshotPatterns: screenshotPatterns,
            launcher: launcher,
            launcherShortcut: launcherShortcut,
            gitRepos: gitRepos,
            llmApps: Array(llmApps),
            llmBrowserTitles: llmTitles,
            remotePushUrl: nil,
            remotePushFrequency: nil
        )

        do {
            try config.save()
        } catch {
            print("[SetupView] Failed to save config: \(error)")
        }
    }
}
