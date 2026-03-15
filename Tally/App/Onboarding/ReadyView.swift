import SwiftUI

struct ReadyView: View {
    let state: OnboardingState
    var liveStats: LiveStats

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("You're all set.")
                .font(.title.bold())

            Text("Tally is now tracking in your menubar.\nClick the icon anytime to see today's stats.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Live preview card
            VStack(spacing: 12) {
                statRow(icon: "keyboard", value: liveStats.keystrokes, label: "keystrokes")
                statRow(icon: "cursorarrow.click", value: liveStats.clicksLeft + liveStats.clicksRight, label: "clicks")
                statRow(icon: "camera.viewfinder", value: liveStats.screenshots, label: "screenshots")

                if liveStats.keystrokes == 0 && liveStats.clicksLeft + liveStats.clicksRight == 0 && liveStats.screenshots == 0 {
                    Text("Waiting for first events...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }

                if state.accessibilitySkipped {
                    Text("Grant Accessibility for full tracking")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.top, 4)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 32)

            // Quick tips
            VStack(alignment: .leading, spacing: 6) {
                Text("Quick tips")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                tipRow("Click the menubar icon for stats")
                tipRow("\"Open Dashboard\" for the full view")
                tipRow("Settings to adjust anytime")
            }
            .padding(.horizontal, 40)

            Spacer()

            Button("Start Tracking") {
                state.completeOnboarding()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
    }

    private func statRow(icon: String, value: Int64, label: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: value)
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func tipRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text("\u{2022}")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
