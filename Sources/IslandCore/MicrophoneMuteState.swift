import Foundation

public struct MicrophoneMuteState {
    private var device: UInt32?
    private var previous: Bool?
    public init() {}
    public static func resolve(masterMute: Bool?, levels: [Float]?, channelMutes: [Bool]?) -> Bool? {
        if masterMute == true { return true }
        let validLevels = levels.flatMap { !$0.isEmpty && $0.allSatisfy { $0.isFinite && $0 >= 0 } ? $0 : nil }
        if let validLevels, validLevels.allSatisfy({ $0 == 0 }) { return true }
        if let channelMutes, !channelMutes.isEmpty, channelMutes.allSatisfy({ $0 }) { return true }
        if let validLevels, let channelMutes, validLevels.count == channelMutes.count,
           zip(validLevels, channelMutes).allSatisfy({ $0.0 == 0 || $0.1 }) { return true }
        if masterMute != nil || validLevels != nil || channelMutes?.isEmpty == false { return false }
        return nil
    }
    public mutating func consume(device: UInt32, muted: Bool?) -> Activity? {
        defer { self.device = device; previous = muted }
        guard self.device == device, let muted, let previous, muted != previous else { return nil }
        return Activity(.microphoneMute, value: 0, label: "Microphone",
            symbol: muted ? "mic.slash.fill" : "mic.fill", isActive: !muted)
    }
}
