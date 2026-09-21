import AppKit

let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let rect = NSRect(x: 40, y: 40, width: 944, height: 944)
let path = NSBezierPath(roundedRect: rect, xRadius: 218, yRadius: 218)
NSGradient(starting: NSColor(calibratedRed: 0.99, green: 0.79, blue: 0.59, alpha: 1),
           ending: NSColor(calibratedRed: 0.85, green: 0.50, blue: 0.32, alpha: 1))!.draw(in: path, angle: -70)
let pill = NSBezierPath(roundedRect: NSRect(x: 170, y: 384, width: 684, height: 256), xRadius: 128, yRadius: 128)
NSColor(calibratedWhite: 0.045, alpha: 1).setFill()
pill.fill()
NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
pill.lineWidth = 3
pill.stroke()
NSColor(calibratedRed: 0.98, green: 0.73, blue: 0.5, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 668, y: 470, width: 84, height: 84)).fill()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
