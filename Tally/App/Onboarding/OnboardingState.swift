import SwiftUI
import os

private let logger = Logger(subsystem: "arthurmonnet.Tally", category: "OnboardingState")

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case privacy = 1
    case accessibility = 2
    case screenshots = 3
    case ready = 4
}

extension Notification.Name {
    static let onboardingCompleted = Notification.Name("onboardingCompleted")
}

@MainActor
@Observable
final class OnboardingState {
    var currentStep: OnboardingStep
    var accessibilityGranted: Bool = false
    var accessibilitySkipped: Bool = false

    // Tool selections
    var selectedEditors: Set<String> = []
    var selectedLauncher: String = "spotlight"
    var launcherShortcut: String = "cmd+space"
    var selectedLLMApps: Set<String> = ["Claude.ai", "ChatGPT"]

    // Screenshot config
    var screenshotFolders: [URL] = [
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    ]
    var detectedTools: [DetectedScreenshotTool] = []
    var isScanning: Bool = false

    init() {
        // Check for post-permission-restart resume step first
        let resumeStep = UserDefaults.standard.integer(forKey: "onboardingResumeStep")
        if resumeStep > 0, let step = OnboardingStep(rawValue: resumeStep) {
            currentStep = step
        } else {
            let savedStep = UserDefaults.standard.integer(forKey: "onboarding_current_step")
            currentStep = OnboardingStep(rawValue: savedStep) ?? .welcome
        }
        accessibilityGranted = AXIsProcessTrusted()
    }

    func advance() {
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else {
            completeOnboarding()
            return
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = next
        }
        UserDefaults.standard.set(next.rawValue, forKey: "onboarding_current_step")
    }

    func completeOnboarding() {
        let launcherShortcutValue: String
        switch selectedLauncher {
        case "raycast": launcherShortcutValue = launcherShortcut
        case "alfred": launcherShortcutValue = "alt+space"
        default: launcherShortcutValue = "cmd+space"
        }

        let llmTitles: [String] = selectedLLMApps.compactMap { app in
            switch app {
            case "Claude.ai": return "claude.ai"
            case "ChatGPT": return "chatgpt.com"
            case "Claude Code": return "claude code"
            case "Cursor (AI)": return "cursor"
            default: return nil
            }
        }

        let screenshotTool = detectedTools.first?.name.lowercased() ?? "macos"
        let patterns = detectedTools.map(\.pattern)

        let config = UserConfig(
            codeEditor: selectedEditors.first ?? "cursor",
            screenshotTool: screenshotTool,
            screenshotFolders: screenshotFolders.map(\.path),
            screenshotPatterns: patterns,
            launcher: selectedLauncher,
            launcherShortcut: launcherShortcutValue,
            llmApps: Array(selectedLLMApps),
            llmBrowserTitles: llmTitles,
            remotePushUrl: nil,
            remotePushFrequency: nil,
            onboardingCompleted: true,
            accessibilityGranted: accessibilityGranted
        )

        do {
            try config.save()
        } catch {
            logger.error("Failed to save config: \(error)")
        }

        UserDefaults.standard.removeObject(forKey: "onboarding_current_step")
        UserDefaults.standard.removeObject(forKey: "onboardingResumeStep")
        NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
    }
}

struct DetectedScreenshotTool: Identifiable {
    let id = UUID()
    let name: String
    let pattern: String
    let matchCount: Int
}
