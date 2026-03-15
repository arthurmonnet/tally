import SwiftUI

struct ScreenshotsView: View {
    let state: OnboardingState

    private let knownPatterns: [(name: String, regex: String)] = [
        ("CleanShot X", #"CleanShot \d{4}-\d{2}-\d{2} at"#),
        ("macOS native", #"Screenshot \d{4}-\d{2}-\d{2} at \d{2}\.\d{2}\.\d{2}"#),
        ("macOS (old)", #"Screen Shot \d{4}-\d{2}-\d{2} at"#),
        ("Xnapper", #"Xnapper-"#),
        ("Kap", #"Kapture \d{4}-\d{2}-\d{2}"#),
        ("ShareX", #"SCR-\d{8}"#),
        ("Shottr", #"Shottr \d{4}-\d{2}-\d{2}"#),
    ]

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Screenshots")
                .font(.title2.bold())

            Text("Where do your screenshots land?")
                .font(.body)
                .foregroundStyle(.secondary)

            // Folder list
            ForEach(Array(state.screenshotFolders.enumerated()), id: \.offset) { index, folder in
                HStack {
                    Text(folder.path.replacingOccurrences(
                        of: FileManager.default.homeDirectoryForCurrentUser.path,
                        with: "~"
                    ))
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                    Spacer()

                    Button("Browse") {
                        browseForFolder(at: index)
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.08))
                )
            }
            .padding(.horizontal, 32)

            // Scan results
            if state.isScanning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !state.detectedTools.isEmpty {
                let totalCount = state.detectedTools.reduce(0) { $0 + $1.matchCount }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Found \(totalCount) screenshots:")
                        .font(.caption.weight(.medium))

                    ForEach(state.detectedTools) { tool in
                        HStack {
                            Text(tool.name)
                                .font(.system(size: 13))
                            Spacer()
                            Text("\(tool.matchCount) files")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding(.horizontal, 32)
            } else {
                Text("No screenshots found in this folder.\nTry a different folder, or skip and Tally will detect them as they come.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Add another folder
            Button {
                addFolder()
            } label: {
                Label("Add another folder", systemImage: "plus")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: 8) {
                Button("Continue") {
                    state.advance()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Skip — I'll set this up later") {
                    state.advance()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .onAppear {
            scanFolders()
        }
    }

    private func browseForFolder(at index: Int) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            state.screenshotFolders[index] = url
            scanFolders()
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            state.screenshotFolders.append(url)
            scanFolders()
        }
    }

    private func scanFolders() {
        state.isScanning = true
        state.detectedTools = []

        DispatchQueue.global(qos: .userInitiated).async {
            let results = performScan(folders: state.screenshotFolders)
            DispatchQueue.main.async {
                state.detectedTools = results
                state.isScanning = false
            }
        }
    }

    private func performScan(folders: [URL]) -> [DetectedScreenshotTool] {
        let imageExtensions = Set(["png", "jpg", "jpeg", "webp", "gif"])
        var counts: [String: (pattern: String, count: Int)] = [:]

        for folder in folders {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            let imageFiles = contents
                .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
                .sorted { a, b in
                    let dateA = (try? a.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                    let dateB = (try? b.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                    return dateA > dateB
                }
                .prefix(30)

            for file in imageFiles {
                let name = file.lastPathComponent
                for (toolName, regex) in knownPatterns {
                    if name.range(of: regex, options: .regularExpression) != nil {
                        let existing = counts[toolName]
                        counts[toolName] = (pattern: regex, count: (existing?.count ?? 0) + 1)
                    }
                }
            }
        }

        return counts.map { DetectedScreenshotTool(name: $0.key, pattern: $0.value.pattern, matchCount: $0.value.count) }
            .sorted { $0.matchCount > $1.matchCount }
    }
}
