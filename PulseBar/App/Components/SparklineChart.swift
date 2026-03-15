import SwiftUI

struct SparklineChart: View {
    let history: StatHistory
    let dayLabels: [String]

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

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

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    let isToday = index == values.count - 1
                    let height = CGFloat(value) / CGFloat(maxVal) * 40

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(isToday ? 0.4 : 0.15))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(height, value > 0 ? 3 : 1))
                }
            }
            .frame(height: 40)

            HStack(spacing: 0) {
                HStack(alignment: .center, spacing: 4) {
                    ForEach(Array(dayLabels.enumerated()), id: \.offset) { _, label in
                        Text(label)
                            .font(.system(size: 9))
                            .foregroundStyle(.quaternary)
                            .frame(maxWidth: .infinity)
                    }
                }
                Spacer()
                Text("avg: \(Self.numberFormatter.string(from: NSNumber(value: Int64(history.average))) ?? "0")")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}
