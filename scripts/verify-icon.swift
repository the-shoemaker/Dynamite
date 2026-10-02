import Foundation
import ImageIO
import CoreGraphics

// Decode every representation with Apple's image decoder. A large preview
// alone misses malformed small slots used by Finder and application launchers.
let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/Dynamite.icns"
let data = try Data(contentsOf: URL(fileURLWithPath: path))
guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { fatalError("Invalid ICNS") }
precondition(CGImageSourceGetCount(source) == 10, "Missing standard/Retina icon representations")
var sizes = Set<Int>()
for index in 0..<CGImageSourceGetCount(source) {
    guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { fatalError("Undecodable icon representation \(index)") }
    let size = image.width
    precondition(size == image.height, "Non-square icon")
    sizes.insert(size)
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    pixels.withUnsafeMutableBytes { bytes in
        let context = CGContext(data: bytes.baseAddress, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    }
    func pixel(_ x: Double, _ y: Double) -> [UInt8] {
        let offset = (Int(y * Double(size)) * size + Int(x * Double(size))) * 4
        return Array(pixels[offset..<offset + 4])
    }
    let center = pixel(0.5, 0.5), background = pixel(0.1, 0.5), light = pixel(0.69, 0.5)
    precondition(center[0] < 60 && center[1] < 60 && center[2] < 60 && center[3] > 240,
                 "Corrupted black pill at \(size)px")
    precondition(background[0] > 180 && background[1] > 80 && background[3] > (size == 16 ? 180 : 240),
                 "Corrupted peach background at \(size)px")
    // The indicator is only 1.3 pixels across at 16px; downsampling blends it
    // with the pill. At all larger sizes its center must remain peach.
    precondition(light[0] > (size == 16 ? 40 : 180) && light[1] > (size == 16 ? 30 : 80) && light[3] > 240,
                 "Corrupted indicator at \(size)px")
    precondition(pixel(0, 0)[3] < 30, "Lost transparent corner at \(size)px")
}
precondition(sizes.isSuperset(of: [16, 32, 64, 128, 256, 512, 1024]), "Missing icon sizes: \(sizes)")
print("Icon decoder: all \(CGImageSourceGetCount(source)) representations, small/large pixel checks and transparency passed")
