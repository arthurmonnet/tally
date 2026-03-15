import Foundation

enum PushFrequency: String, Codable, Sendable, CaseIterable {
    case fifteenMinutes = "15m"
    case thirtyMinutes = "30m"
    case oneHour = "1h"
    case threeHours = "3h"
    case manual = "manual"

    var displayName: String {
        switch self {
        case .fifteenMinutes: return "Every 15 minutes"
        case .thirtyMinutes: return "Every 30 minutes"
        case .oneHour: return "Every hour"
        case .threeHours: return "Every 3 hours"
        case .manual: return "Manual only"
        }
    }

    var intervalSeconds: TimeInterval? {
        switch self {
        case .fifteenMinutes: return 15 * 60
        case .thirtyMinutes: return 30 * 60
        case .oneHour: return 60 * 60
        case .threeHours: return 3 * 60 * 60
        case .manual: return nil
        }
    }
}

struct UserConfig: Codable, Sendable {
    let codeEditor: String
    let screenshotTool: String
    let screenshotFolders: [String]
    let screenshotPatterns: [String]
    let launcher: String
    let launcherShortcut: String
    let gitRepos: [String]
    let llmApps: [String]
    let llmBrowserTitles: [String]
    let remotePushUrl: String?
    let remotePushFrequency: PushFrequency?
    let onboardingCompleted: Bool
    let accessibilityGranted: Bool

    var isRemotePushEnabled: Bool {
        remotePushUrl != nil && remotePushFrequency != nil
    }

    enum CodingKeys: String, CodingKey {
        case codeEditor = "code_editor"
        case screenshotTool = "screenshot_tool"
        case screenshotFolders = "screenshot_folders"
        case screenshotPatterns = "screenshot_patterns"
        case launcher
        case launcherShortcut = "launcher_shortcut"
        case gitRepos = "git_repos"
        case llmApps = "llm_apps"
        case llmBrowserTitles = "llm_browser_titles"
        case remotePushUrl = "remote_push_url"
        case remotePushFrequency = "remote_push_frequency"
        case onboardingCompleted = "onboarding_completed"
        case accessibilityGranted = "accessibility_granted"
    }

    init(
        codeEditor: String,
        screenshotTool: String,
        screenshotFolders: [String],
        screenshotPatterns: [String],
        launcher: String,
        launcherShortcut: String,
        gitRepos: [String],
        llmApps: [String],
        llmBrowserTitles: [String],
        remotePushUrl: String?,
        remotePushFrequency: PushFrequency?,
        onboardingCompleted: Bool = true,
        accessibilityGranted: Bool = false
    ) {
        self.codeEditor = codeEditor
        self.screenshotTool = screenshotTool
        self.screenshotFolders = screenshotFolders
        self.screenshotPatterns = screenshotPatterns
        self.launcher = launcher
        self.launcherShortcut = launcherShortcut
        self.gitRepos = gitRepos
        self.llmApps = llmApps
        self.llmBrowserTitles = llmBrowserTitles
        self.remotePushUrl = remotePushUrl
        self.remotePushFrequency = remotePushFrequency
        self.onboardingCompleted = onboardingCompleted
        self.accessibilityGranted = accessibilityGranted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        codeEditor = try container.decode(String.self, forKey: .codeEditor)
        screenshotTool = try container.decode(String.self, forKey: .screenshotTool)
        screenshotFolders = try container.decode([String].self, forKey: .screenshotFolders)
        screenshotPatterns = try container.decode([String].self, forKey: .screenshotPatterns)
        launcher = try container.decode(String.self, forKey: .launcher)
        launcherShortcut = try container.decode(String.self, forKey: .launcherShortcut)
        gitRepos = try container.decode([String].self, forKey: .gitRepos)
        llmApps = try container.decode([String].self, forKey: .llmApps)
        llmBrowserTitles = try container.decode([String].self, forKey: .llmBrowserTitles)
        remotePushUrl = try container.decodeIfPresent(String.self, forKey: .remotePushUrl)
        remotePushFrequency = try container.decodeIfPresent(PushFrequency.self, forKey: .remotePushFrequency)
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? true
        accessibilityGranted = try container.decodeIfPresent(Bool.self, forKey: .accessibilityGranted) ?? false
    }

    static let defaultConfig = UserConfig(
        codeEditor: "cursor",
        screenshotTool: "macos",
        screenshotFolders: ["~/Desktop"],
        screenshotPatterns: [],
        launcher: "spotlight",
        launcherShortcut: "cmd+space",
        gitRepos: [],
        llmApps: [],
        llmBrowserTitles: ["claude.ai", "chatgpt.com"],
        remotePushUrl: nil,
        remotePushFrequency: nil
    )

    static var configURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let tallyDir = appSupport.appendingPathComponent("Tally")

        // Migrate from old "Pulse" directory if it exists
        let oldDir = appSupport.appendingPathComponent("Pulse")
        if FileManager.default.fileExists(atPath: oldDir.path) &&
           !FileManager.default.fileExists(atPath: tallyDir.path) {
            try? FileManager.default.moveItem(at: oldDir, to: tallyDir)
        }

        return tallyDir.appendingPathComponent("config.json")
    }

    static func load() -> UserConfig? {
        let url = configURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(UserConfig.self, from: data)
    }

    func save() throws {
        let url = UserConfig.configURL
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}
