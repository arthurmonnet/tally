import SwiftUI

struct PulseAPISettingsView: View {
    @State var pushScheduler: PushScheduler
    @State private var endpointUrl: String = ""
    @State private var token: String = ""
    @State private var frequency: PushFrequency = .oneHour
    @State private var isEnabled: Bool = false
    @State private var urlError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Push stats to a remote endpoint", isOn: $isEnabled)
            }

            if isEnabled {
                Section("Endpoint") {
                    TextField("https://yoursite.com/api/pulse", text: $endpointUrl)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: endpointUrl) { _, newValue in
                            validateUrl(newValue)
                        }

                    if let urlError {
                        Text(urlError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    SecureField("API Token", text: $token)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Push Frequency") {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(PushFrequency.allCases, id: \.self) { freq in
                            Text(freq.displayName).tag(freq)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Status") {
                    HStack {
                        statusIndicator
                        statusText
                        Spacer()
                        pushNowButton
                    }
                }

                Section {
                    Text("Set up an endpoint to receive your stats.\nYour token is stored securely in the macOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: isEnabled ? 420 : 120)
        .padding()
        .onAppear { loadCurrentConfig() }
        .onChange(of: isEnabled) { _, newValue in
            if !newValue { disablePush() }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveConfig() }
                    .disabled(isEnabled && !isConfigValid)
            }
        }
    }

    // MARK: - Status Views

    @ViewBuilder
    private var statusIndicator: some View {
        if pushScheduler.isPushing {
            ProgressView()
                .controlSize(.small)
        } else if let result = pushScheduler.lastPushResult {
            Circle()
                .fill(result.success ? .green : .red)
                .frame(width: 8, height: 8)
        } else {
            Circle()
                .fill(.gray)
                .frame(width: 8, height: 8)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if pushScheduler.isPushing {
            Text("Pushing...")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let result = pushScheduler.lastPushResult {
            if result.success {
                Text("Pushed \(result.timeAgoString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Failed: \(result.errorMessage ?? "unknown error")")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } else {
            Text("Never pushed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var pushNowButton: some View {
        Button("Push Now") {
            Task { await pushScheduler.pushNow() }
        }
        .disabled(pushScheduler.isPushing || !isConfigValid)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Validation

    private var isConfigValid: Bool {
        urlError == nil && !endpointUrl.isEmpty && !token.isEmpty
    }

    private func validateUrl(_ url: String) {
        guard !url.isEmpty else {
            urlError = nil
            return
        }

        guard let parsed = URL(string: url),
              let scheme = parsed.scheme?.lowercased(),
              parsed.host != nil else {
            urlError = "Enter a valid URL"
            return
        }

        let isLocalhost = parsed.host?.lowercased() == "localhost"
            || parsed.host?.lowercased() == "127.0.0.1"

        if scheme != "https" && !isLocalhost {
            urlError = "HTTPS is required"
            return
        }

        urlError = nil
    }

    // MARK: - Config

    private func loadCurrentConfig() {
        guard let config = UserConfig.load() else { return }

        if let url = config.remotePushUrl {
            endpointUrl = url
            isEnabled = true
        }
        if let freq = config.remotePushFrequency {
            frequency = freq
        }
        if let savedToken = KeychainHelper.remotePushToken {
            token = savedToken
        }
    }

    private func saveConfig() {
        guard let existingConfig = UserConfig.load() else { return }

        let newConfig = UserConfig(
            codeEditor: existingConfig.codeEditor,
            screenshotTool: existingConfig.screenshotTool,
            screenshotFolders: existingConfig.screenshotFolders,
            screenshotPatterns: existingConfig.screenshotPatterns,
            launcher: existingConfig.launcher,
            launcherShortcut: existingConfig.launcherShortcut,
            gitRepos: existingConfig.gitRepos,
            llmApps: existingConfig.llmApps,
            llmBrowserTitles: existingConfig.llmBrowserTitles,
            remotePushUrl: isEnabled ? endpointUrl : nil,
            remotePushFrequency: isEnabled ? frequency : nil
        )

        do {
            try newConfig.save()
        } catch {
            print("[PulseAPISettings] Failed to save config: \(error)")
            return
        }

        if isEnabled && !token.isEmpty {
            KeychainHelper.setRemotePushToken(token)
        } else {
            KeychainHelper.clearRemotePushToken()
        }

        pushScheduler.updateSchedule()
    }

    private func disablePush() {
        endpointUrl = ""
        token = ""
        saveConfig()
    }
}
