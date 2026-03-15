import SwiftUI
import AppKit

struct AppBar: View {
    let name: String
    let time: String
    let proportion: Double  // 0...1 relative to top app
    let icon: NSImage

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .cornerRadius(3)

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
                    .frame(width: geo.size.width * max(proportion, 0.02), height: 3)
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }
}
