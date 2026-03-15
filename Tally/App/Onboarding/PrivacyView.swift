import SwiftUI

struct PrivacyView: View {
    let state: OnboardingState

    private let tracks = [
        "How many keys you press",
        "How many times you click",
        "Which apps you use and for how long",
        "How far your mouse travels",
        "Files created, git commits",
    ]

    private let neverDoes = [
        "Record what you type",
        "Read your clipboard content",
        "Take screenshots of your screen",
        "Send anything without your consent",
        "Access files, emails, or messages",
    ]

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("What Tally tracks")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 8) {
                ForEach(tracks, id: \.self) { item in
                    Label(item, systemImage: "checkmark")
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                }
            }

            Divider()
                .padding(.horizontal, 40)

            Text("What Tally never does")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 8) {
                ForEach(neverDoes, id: \.self) { item in
                    Label(item, systemImage: "xmark")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Text("All data stays in a local SQLite file you can inspect anytime.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer()

            Button("Continue") {
                state.advance()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .padding(.horizontal, 32)
    }
}
