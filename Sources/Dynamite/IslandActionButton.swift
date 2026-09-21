import SwiftUI

/// Expanded-island actions keep the label inside a generous pill-shaped target.
struct IslandActionButton: View {
    let title: String
    let symbol: String
    var tint: Color = .white
    var prominent = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }.padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 48)
                .foregroundStyle(prominent ? Color.black : tint)
                .background(prominent ? tint : Color.white.opacity(0.14), in: Capsule())
                .contentShape(Capsule())
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
}
