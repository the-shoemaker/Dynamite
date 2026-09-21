import Foundation

/// Accept only fresh receipts explicitly attributed to sharingd. A Downloads
/// write by itself is not evidence of AirDrop.
public struct AirDropReceipt: Equatable {
    /// Downloads can append a collision number while the native banner keeps
    /// the sender's original name. Keep both spellings, including the extension.
    public static func notificationNames(for filename: String) -> Set<String> {
        var names: Set<String> = [filename]
        let path = filename as NSString
        let stem = path.deletingPathExtension
        if let space = stem.lastIndex(of: " "), let number = Int(stem[stem.index(after: space)...]), number >= 2 {
            let original = String(stem[..<space])
            if !original.isEmpty {
                names.insert(path.pathExtension.isEmpty ? original : original + "." + path.pathExtension)
            }
        }
        return names
    }
    public let identifier: String
    public let receivedAt: TimeInterval
    public init?(quarantine: String, since: TimeInterval, now: TimeInterval) {
        let fields = quarantine.split(separator: ";", omittingEmptySubsequences: false)
        guard fields.count == 4, fields[2] == "sharingd",
              let stamp = UInt64(fields[1], radix: 16),
              let uuid = UUID(uuidString: String(fields[3])) else { return nil }
        let date = TimeInterval(stamp)
        guard date >= floor(since), date <= now + 5 else { return nil }
        identifier = uuid.uuidString
        receivedAt = date
    }
}
