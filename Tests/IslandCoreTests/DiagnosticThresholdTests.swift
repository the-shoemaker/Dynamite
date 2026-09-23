import Testing
@testable import IslandCore
struct DiagnosticThresholdTests {
    @Test func sustainedLoadAndCooldown() {
        var state = DiagnosticThreshold()
        let result1 = state.observe(cpuPercent: 90, footprint: 0, baseline: 0, elapsed: 60); #expect(!result1)
        let result2 = state.observe(cpuPercent: 0, footprint: 0, baseline: 0, elapsed: 120); #expect(!result2)
        for time in [180.0, 240] { let result3 = state.observe(cpuPercent: 30, footprint: 0, baseline: 0, elapsed: time); #expect(!result3) }
        let result4 = state.observe(cpuPercent: 30, footprint: 0, baseline: 0, elapsed: 300); #expect(result4)
        for time in stride(from: 360.0, to: 2100, by: 60) { let result5 = state.observe(cpuPercent: 30, footprint: 0, baseline: 0, elapsed: time); #expect(!result5) }
        let result6 = state.observe(cpuPercent: 30, footprint: 0, baseline: 0, elapsed: 2100); #expect(result6)
        _ = state.observe(cpuPercent: 30, footprint: 0, baseline: 0, elapsed: 2160)
        _ = state.observe(cpuPercent: 30, footprint: 0, baseline: 0, elapsed: 2220)
        let result7 = state.observe(cpuPercent: 30, footprint: 0, baseline: 0, elapsed: 3900); #expect(result7)
        for time in stride(from: 4000.0, to: 43000, by: 60) { let result8 = state.observe(cpuPercent: 90, footprint: 0, baseline: 0, elapsed: time); #expect(!result8) }
    }
    @Test func memoryGrowthAndDrop() {
        var state = DiagnosticThreshold()
        for time in [60.0, 120] { let result9 = state.observe(cpuPercent: 0, footprint: 200 * 1_048_576, baseline: 30 * 1_048_576, elapsed: time); #expect(!result9) }
        let result10 = state.observe(cpuPercent: 0, footprint: 200 * 1_048_576, baseline: 30 * 1_048_576, elapsed: 180); #expect(result10)
        let result11 = state.observe(cpuPercent: 0, footprint: 20, baseline: 30, elapsed: 240); #expect(!result11)
    }
}
