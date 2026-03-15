import SwiftUI
import AppKit

struct TallyAPISettingsView: View {
    @State var pushScheduler: PushScheduler
    @State private var endpointUrl: String = ""
    @State private var token: String = ""
    @State private var frequency: PushFrequency = .fifteenMinutes
    @State private var isEnabled: Bool = false
    @State private var urlError: String?
    @State private var isTesting: Bool = false
    @State private var connectionTestResult: ConnectionResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Tally API")
                    .font(.headline)
                Spacer()
                Button("Save") { saveConfig() }
                    .disabled(isEnabled && !isConfigValid)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.bottom, 16)

            // Toggle
            Toggle("Push stats to a remote endpoint", isOn: $isEnabled)

            if isEnabled {
                Divider()
                    .padding(.vertical, 12)

                // Quick Setup
                quickSetupSection

                Divider()
                    .padding(.vertical, 12)

                // Endpoint
                endpointSection

                Divider()
                    .padding(.vertical, 12)

                // Frequency
                frequencySection

                Divider()
                    .padding(.vertical, 12)

                // Status
                statusSection

                // Info note
                Text("Your token is stored securely in the macOS Keychain.\nThe app appends /api/tally to your URL automatically.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            }
        }
        .padding(20)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { loadCurrentConfig() }
        .onChange(of: isEnabled) { _, newValue in
            if !newValue { disablePush() }
        }
    }

    // MARK: - Sections

    private var quickSetupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Setup")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Button(action: openVercelDeploy) {
                HStack {
                    Image(systemName: "triangle.fill")
                        .font(.caption)
                    Text("Deploy to Vercel")
                }
            }
            .buttonStyle(.bordered)

            Text("Creates a free endpoint that receives your stats and serves them as JSON. No coding required.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text("Or set up manually \u{2192}")
                .font(.system(size: 12))
                .foregroundStyle(.blue)
                .onTapGesture {
                    if let url = URL(string: "https://github.com/arthurmonnet/tally-endpoint#self-hosting") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
        }
    }

    private var endpointSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Endpoint")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                HStack {
                    Text("Base URL")
                        .font(.system(size: 13))
                        .frame(width: 80, alignment: .leading)
                    TextField("https://your-app.vercel.app", text: $endpointUrl)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: endpointUrl) { _, newValue in
                            validateUrl(newValue)
                            connectionTestResult = nil
                        }
                }

                if let urlError {
                    Text(urlError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.leading, 80)
                }

                HStack {
                    Text("API Token")
                        .font(.system(size: 13))
                        .frame(width: 80, alignment: .leading)
                    SecureField("your-secret-token", text: $token)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: token) { _, _ in
                            connectionTestResult = nil
                        }
                }

                HStack {
                    if let result = connectionTestResult {
                        switch result {
                        case .success:
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Connected")
                                    .foregroundStyle(.green)
                            }
                            .font(.caption)
                        case .error(let message):
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()

                    Button("Test Connection") {
                        Task { await testConnection() }
                    }
                    .disabled(isTesting || !isConfigValid)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
        }
    }

    private var frequencySection: some View {
        HStack {
            Text("Push Frequency")
                .font(.system(size: 13))

            Spacer()

            Picker("", selection: $frequency) {
                ForEach(PushFrequency.allCases, id: \.self) { freq in
                    Text(freq.displayName).tag(freq)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 180)
        }
    }

    private var statusSection: some View {
        HStack {
            statusIndicator
            statusText
            Spacer()
            pushNowButton
        }
    }

    // MARK: - Vercel Deploy

    private func openVercelDeploy() {
        let deployURL = "https://vercel.com/new/clone?" + [
            "repository-url=https://github.com/arthurmonnet/tally-endpoint",
            "env=TALLY_API_TOKEN",
            "envDescription=Secret+token+for+Tally+app.+Pick+any+random+string.",
            "envLink=https://github.com/arthurmonnet/tally-endpoint%23setup",
            "project-name=tally-endpoint",
            "repository-name=tally-endpoint",
        ].joined(separator: "&")

        if let url = URL(string: deployURL) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Test Connection

    private func testConnection() async {
        isTesting = true
        connectionTestResult = nil

        let remotePush = RemotePush()
        connectionTestResult = await remotePush.testConnection(url: endpointUrl, token: token)

        isTesting = false
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

        let normalized = RemotePush.normalizeURL(url)
        guard let parsed = URL(string: normalized),
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

        let normalizedUrl = isEnabled ? RemotePush.normalizeURL(endpointUrl) : nil

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
            remotePushUrl: normalizedUrl,
            remotePushFrequency: isEnabled ? frequency : nil
        )

        do {
            try newConfig.save()
        } catch {
            print("[TallyAPISettings] Failed to save config: \(error)")
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
