import Foundation

public struct ClockReading: Equatable {
    private static let durationUnit = try! NSRegularExpression(pattern: #"(\d+)\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b"#, options: .caseInsensitive)
    /// Parse Clock's original-duration label, never the decreasing countdown.
    public static func durationLabel(_ text: String) -> Int? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = text as NSString
        let matches = durationUnit.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return nil }
        var end = 0, total = 0
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
        for match in matches {
            guard source.substring(with: NSRange(location: end, length: match.range.location - end)).trimmingCharacters(in: separators).isEmpty,
                  let number = Int(source.substring(with: match.range(at: 1))), number < 86400 else { return nil }
            let unit = source.substring(with: match.range(at: 2)).lowercased()
            total += number * (unit.hasPrefix("h") ? 3600 : unit.hasPrefix("m") ? 60 : 1)
            end = NSMaxRange(match.range)
        }
        guard source.substring(from: end).trimmingCharacters(in: separators).isEmpty, total > 0, total < 86400 else { return nil }
        return total
    }
    public let identifier: String
    public let remaining: Int
    public let paused: Bool
    public init(identifier: String, remaining: Int, paused: Bool) {
        self.identifier = identifier
        self.remaining = remaining
        self.paused = paused
    }
    public static func seconds(_ text: String) -> Int? {
        let fields = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(fields.count), fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let numbers = fields.compactMap { Int($0) }
        guard numbers.count == fields.count, numbers.dropFirst().allSatisfy({ $0 < 60 }), numbers[0] < 100 else { return nil }
        return numbers.reduce(0) { $0 * 60 + $1 }
    }
    public static func formatted(_ seconds: Int) -> String {
        let value = max(0, seconds)
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) :
            String(format: "%d:%02d", value / 60, value % 60)
    }
}

public enum FocusReading: Equatable {
    case off
    case active(String)
    public static func decode(_ data: Data) throws -> FocusReading {
        struct Root: Decodable { let data: [Entry] }
        struct Entry: Decodable { let storeAssertionRecords: [Record]? }
        struct Record: Decodable { let assertionDetails: Details? }
        struct Details: Decodable { let assertionDetailsModeIdentifier: String? }
        let root = try JSONDecoder().decode(Root.self, from: data)
        for entry in root.data {
            for record in entry.storeAssertionRecords ?? [] {
                if let id = record.assertionDetails?.assertionDetailsModeIdentifier, !id.isEmpty { return .active(id) }
            }
        }
        return .off
    }
}
