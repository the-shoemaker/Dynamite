import SwiftUI

struct IslandCloseButton: View {
    let visible: Bool
    let title: String
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.75)).frame(width: 28, height: 28)
                .background(.white.opacity(0.12), in: Circle()).contentShape(Circle())
        }.buttonStyle(.plain).help(title).accessibilityLabel(title)
            .opacity(visible ? 1 : 0).scaleEffect(visible ? 1 : 0.75)
            .allowsHitTesting(visible)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.25, dampingFraction: 0.75), value: visible)
    }
}

/// Vector fallback because the AirDrop symbol is absent from some macOS symbol sets.
struct AirDropGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.44)
            ZStack {
                Path { path in
                    for radius in [0.18, 0.30, 0.42] {
                        let angle = 48.0 * Double.pi / 180
                        path.move(to: CGPoint(x: center.x + size * radius * cos(angle), y: center.y + size * radius * sin(angle)))
                        path.addArc(center: center, radius: size * radius, startAngle: .degrees(48), endAngle: .degrees(132), clockwise: true)
                    }
                }.stroke(style: StrokeStyle(lineWidth: size * 0.055, lineCap: .round))
                Path { path in
                    path.move(to: CGPoint(x: center.x, y: center.y + size * 0.08))
                    path.addLine(to: CGPoint(x: center.x - size * 0.22, y: size * 0.96))
                    path.addLine(to: CGPoint(x: center.x + size * 0.22, y: size * 0.96))
                    path.closeSubpath()
                }.fill()
            }
        }.accessibilityLabel("AirDrop")
    }
}
