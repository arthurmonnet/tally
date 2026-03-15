import SwiftUI

struct WindowChart: View {
    let points: [(time: String, value: Int64)]
    let current: Int64
    let peak: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(current) open \u{00B7} peak \(peak)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if points.count >= 2 {
                GeometryReader { geo in
                    let maxVal = Double(points.map(\.value).max() ?? 1)
                    let w = geo.size.width
                    let h = geo.size.height

                    let stepX = w / Double(points.count - 1)
                    let pathPoints: [CGPoint] = points.enumerated().map { i, p in
                        CGPoint(
                            x: Double(i) * stepX,
                            y: h - (maxVal > 0 ? Double(p.value) / maxVal : 0) * (h - 4) - 2
                        )
                    }

                    // Area fill
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: h))
                        path.addLine(to: pathPoints[0])
                        for point in pathPoints.dropFirst() {
                            path.addLine(to: point)
                        }
                        path.addLine(to: CGPoint(x: pathPoints.last?.x ?? w, y: h))
                        path.closeSubpath()
                    }
                    .fill(Color.primary.opacity(0.05))

                    // Line
                    Path { path in
                        path.move(to: pathPoints[0])
                        for point in pathPoints.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(Color.primary.opacity(0.3), lineWidth: 1.5)

                    // Current value dot
                    if let last = pathPoints.last {
                        Circle()
                            .fill(Color.primary.opacity(0.5))
                            .frame(width: 4, height: 4)
                            .position(last)
                    }
                }
                .frame(height: 40)

                // Time labels
                HStack {
                    if let first = points.first {
                        Text(formatHour(first.time))
                            .font(.system(size: 9))
                            .foregroundStyle(.quaternary)
                    }
                    Spacer()
                    Text("now")
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                }
            } else {
                Text("Collecting data...")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(height: 40)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func formatHour(_ time: String) -> String {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard let hour = parts.first else { return time }
        if hour == 0 { return "12am" }
        if hour < 12 { return "\(hour)am" }
        if hour == 12 { return "12pm" }
        return "\(hour - 12)pm"
    }
}
