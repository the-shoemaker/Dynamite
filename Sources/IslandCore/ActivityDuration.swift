import Foundation

public enum ActivityDuration {
    public static let steps: [Double] = [0.5, 1, 2, 3, 4, 5, 7, 10, 15, 20, 30, 50, 60, 120, 300, 600, 1800, 3600]
    public static func validated(_ seconds: Double) -> Double {
        seconds.isFinite ? min(3600, max(0.5, seconds)) : 2
    }
    public static func index(for seconds: Double) -> Double {
        Double(steps.indices.min(by: { abs(steps[$0] - seconds) < abs(steps[$1] - seconds) }) ?? 2)
    }
    public static func seconds(at index: Double) -> Double {
        guard index.isFinite else { return 2 }
        return steps[Int(min(Double(steps.count - 1), max(0, index.rounded())))]
    }
    public static func label(_ seconds: Double, compact: Bool = false) -> String {
        let value = validated(seconds)
        let amount: Double
        let unit: String
        if value >= 3600 && value.truncatingRemainder(dividingBy: 3600) == 0 { amount = value / 3600; unit = compact ? "h" : "hour" }
        else if value >= 60 && value.truncatingRemainder(dividingBy: 60) == 0 { amount = value / 60; unit = compact ? "min" : "minute" }
        else { amount = value; unit = compact ? "s" : "second" }
        let number = amount == amount.rounded() ? String(Int(amount)) : String(amount)
        return "\(number) \(unit)\(!compact && amount != 1 ? "s" : "")"
    }
}
