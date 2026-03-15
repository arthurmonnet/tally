import SwiftUI

struct AppBar: View {
    let name: String
    let time: String
    let proportion: Double  // 0...1 relative to top app

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Text(time)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: geo.size.width * max(proportion, 0.02), height: 4)
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 16)
    }
}
