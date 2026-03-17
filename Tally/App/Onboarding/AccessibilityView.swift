import SwiftUI

private enum PermissionState {
    case notGranted
    case waitingForUser
    case grantedNeedsRestart
    case alreadyGranted
}

struct AccessibilityView: View {
    let state: OnboardingState

    @State private var permissionState: PermissionState = .notGranted
    @State private var permissionTimer: Timer?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            switch permissionState {
            case .notGranted:
                requestContent
            case .waitingForUser:
                waitingContent
            case .grantedNeedsRestart:
                restartContent
            case .alreadyGranted:
                grantedContent
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .onAppear {
            if AXIsProcessTrusted() {
                permissionState = .alreadyGranted
                state.accessibilityGranted = true
                // Auto-advance after brief confirmation
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if permissionState == .alreadyGranted {
                        state.advance()
                    }
                }
            }
        }
        .onDisappear {
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }

    // MARK: - Not Granted

    private var requestContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Accessibility Access")
                .font(.title2.bold())

            Text("Tally needs Accessibility permission to count keystrokes, clicks, and scroll distance.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("macOS requires this for any app that monitors input events. Tally uses it only for counting — never recording.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Grant Access") {
                requestPermission()
                permissionState = .waitingForUser
                startPolling()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Skip for now — Tally will run with limited tracking") {
                state.accessibilitySkipped = true
                state.advance()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Waiting for User

    private var waitingContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Accessibility Access")
                .font(.title2.bold())

            Text("Waiting for permission...")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                instructionRow(number: "1", text: "Find Tally in the list")
                instructionRow(number: "2", text: "Toggle it on")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))
            )

            Button("Open System Settings") {
                openAccessibilitySettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Skip for now — Tally will run with limited tracking") {
                state.accessibilitySkipped = true
                permissionTimer?.invalidate()
                permissionTimer = nil
                state.advance()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Granted, Needs Restart

    private var restartContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))

            Text("Permission granted!")
                .font(.title3.weight(.medium))

            Text("Restarting Tally...")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Already Granted

    private var grantedContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))

            Text("Accessibility access granted.")
                .font(.title3.weight(.medium))

            Text("Tally can now track your activity.")
                .font(.body)
                .foregroundStyle(.secondary)

            Button("Continue") {
                state.advance()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Helpers

    private func instructionRow(number: String, text: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.secondary.opacity(0.2)))

            Text(text)
                .font(.system(size: 13))
        }
    }

    private func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startPolling() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                if AXIsProcessTrusted() {
                    permissionTimer?.invalidate()
                    permissionTimer = nil
                    onPermissionGranted()
                }
            }
        }
    }

    private func onPermissionGranted() {
        state.accessibilityGranted = true

        // Save progress so onboarding resumes at the step after accessibility
        UserDefaults.standard.set(
            OnboardingStep.screenshots.rawValue,
            forKey: "onboardingResumeStep"
        )

        withAnimation(.spring(duration: 0.4)) {
            permissionState = .grantedNeedsRestart
        }

        // Auto-restart after 2 seconds — CGEventTap requires a fresh process
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            relaunchApp()
        }
    }

    private func relaunchApp() {
        let bundlePath = Bundle.main.bundlePath

        // Shell relaunch with delay — ensures current process quits first
        let script = "sleep 1; open \"\(bundlePath)\""
        Process.launchedProcess(launchPath: "/bin/sh", arguments: ["-c", script])

        NSApplication.shared.terminate(nil)
    }
}
