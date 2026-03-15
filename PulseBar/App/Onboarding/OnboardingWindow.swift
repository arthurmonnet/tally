import SwiftUI

struct OnboardingWindow: View {
    @State private var state = OnboardingState()

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch state.currentStep {
                case .welcome:
                    WelcomeView(state: state)
                case .privacy:
                    PrivacyView(state: state)
                case .accessibility:
                    AccessibilityView(state: state)
                case .screenshots:
                    ScreenshotsView(state: state)
                case .ready:
                    ReadyView(state: state)
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            Spacer(minLength: 0)

            StepIndicator(
                total: OnboardingStep.allCases.count,
                current: state.currentStep.rawValue
            )
            .padding(.bottom, 24)
        }
        .frame(width: 480, height: 520)
    }
}
