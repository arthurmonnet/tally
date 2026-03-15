import SwiftUI

struct StatRow: View {
    let icon: String?
    let label: String
    let value: String
    let expandable: Bool
    let isExpanded: Bool
    var onTap: (() -> Void)?

    init(icon: String? = nil, label: String, value: String, expandable: Bool = false, isExpanded: Bool = false, onTap: (() -> Void)? = nil) {
        self.icon = icon
        self.label = label
        self.value = value
        self.expandable = expandable
        self.isExpanded = isExpanded
        self.onTap = onTap
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .center)
            }
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.primary)
            if expandable {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 24)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }
}
