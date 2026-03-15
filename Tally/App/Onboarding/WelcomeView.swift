import SwiftUI

struct WelcomeView: View {
    let state: OnboardingState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.primary)

            VStack(spacing: 12) {
                Text("Welcome to Tally")
                    .font(.title.bold())

                Text("Track your daily activity — keystrokes, clicks, apps, git, screenshots — and surface fun stats about how you work.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                Text("Local-first. No cloud. No account.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.7))
            }
            .padding(.horizontal, 32)

            Spacer()

            Button("Get Started") {
                state.advance()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
    }
}
