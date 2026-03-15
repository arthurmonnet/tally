import SwiftUI

struct SparklineChart: View {
    let history: StatHistory
    let dayLabels: [String]

    @State private var hoveredIndex: Int?

    private static let dayInitialFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f
    }()

    private static let dateParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(history: StatHistory) {
        self.history = history
        self.dayLabels = history.days.suffix(7).map { day in
            if let date = Self.dateParser.date(from: day.date) {
                return Self.dayInitialFormatter.string(from: date)
            }
            return "?"
        }
    }

    var body: some View {
        let values = history.days.suffix(7).map(\.value)
        let maxVal = max(values.max() ?? 1, 1)
        let average = history.average

        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottom) {
                // Average dashed line
                GeometryReader { geo in
                    let y = geo.size.height - CGFloat(average / Double(maxVal)) * geo.size.height
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }

                // Bars
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        let isToday = index == values.count - 1
                        let isHovered = hoveredIndex == index
                        let height = CGFloat(value) / CGFloat(maxVal) * 40

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(
                                isHovered ? 0.5 : (isToday ? 0.4 : 0.15)
                            ))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(height, value > 0 ? 3 : 1))
                            .onHover { hovering in
                                hoveredIndex = hovering ? index : nil
                            }
                    }
                }
            }
            .frame(height: 40)

            // Labels: value on hover/today, day initial otherwise, dot for zero days
            HStack(spacing: 4) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    let isToday = index == values.count - 1
                    let isHovered = hoveredIndex == index
                    let showValue = isHovered || (isToday && hoveredIndex == nil)
                    let label: String = {
                        if showValue {
                            return formatCompact(value)
                        }
                        return index < dayLabels.count ? dayLabels[index] : "?"
                    }()

                    Text(label)
                        .font(.system(size: 9, weight: showValue ? .medium : .regular))
                        .foregroundStyle(showValue ? .primary : .quaternary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private func formatCompact(_ value: Int64) -> String {
        if value >= 1000 { return "\(value / 1000)k" }
        return "\(value)"
    }
}
