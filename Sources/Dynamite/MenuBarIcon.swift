import AppKit

enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { bounds in
            let height: CGFloat = 11
            let pill = NSRect(x: bounds.minX, y: bounds.midY - height / 2,
                              width: bounds.width, height: height)
            let shape = NSBezierPath(roundedRect: pill, xRadius: height / 2, yRadius: height / 2)
            let diameter: CGFloat = 4
            // Center the cutout in the rounded end for an even border around it.
            let inset = (height - diameter) / 2
            shape.appendOval(in: NSRect(x: pill.maxX - inset - diameter, y: bounds.midY - diameter / 2,
                                       width: diameter, height: diameter))
            shape.windingRule = .evenOdd
            NSColor.black.setFill()
            shape.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Dynamite"
        return image
    }
}
