import SwiftUI

struct AccessibilityView: View {
    let state: OnboardingState

    @State private var permissionTimer: Timer?
    @State private var showGranted = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            if showGranted {
                grantedContent
            } else {
                requestContent
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .onAppear {
            if AXIsProcessTrusted() {
                state.accessibilityGranted = true
                showGranted = true
            }
        }
        .onDisappear {
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }

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

            VStack(alignment: .leading, spacing: 6) {
                instructionRow(number: "1", text: "Click \"Open System Settings\"")
                instructionRow(number: "2", text: "Find Tally in the list")
                instructionRow(number: "3", text: "Toggle it on")
                instructionRow(number: "4", text: "Come back here")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))
            )

            Button("Open System Settings") {
                openAccessibilitySettings()
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
        .onAppear {
            // Auto-advance after 1.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if showGranted {
                    state.advance()
                }
            }
        }
    }

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
                    state.accessibilityGranted = true
                    withAnimation(.spring(duration: 0.4)) {
                        showGranted = true
                    }
                }
            }
        }
    }
}
