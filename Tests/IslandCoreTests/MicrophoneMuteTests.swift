import Testing
@testable import IslandCore

struct MicrophoneMuteTests {
    @Test func deviceMuteAndZeroInputBothCountAsMuted() {
        #expect(MicrophoneMuteState.resolve(masterMute: true, levels: [0.8], channelMutes: nil) == true)
        #expect(MicrophoneMuteState.resolve(masterMute: false, levels: [0], channelMutes: nil) == true)
        #expect(MicrophoneMuteState.resolve(masterMute: false, levels: [0.001], channelMutes: nil) == false)
        #expect(MicrophoneMuteState.resolve(masterMute: nil, levels: [0, 0.5], channelMutes: nil) == false)
        #expect(MicrophoneMuteState.resolve(masterMute: nil, levels: [0, 0.5], channelMutes: [false, true]) == true)
        #expect(MicrophoneMuteState.resolve(masterMute: nil, levels: [.nan], channelMutes: nil) == nil)
        #expect(MicrophoneMuteState.resolve(masterMute: nil, levels: [], channelMutes: []) == nil)
    }
    @Test func onlyRealEdgesAnnounceAndDeviceSwitchesAreQuiet() {
        var state = MicrophoneMuteState()
        #expect(state.consume(device: 1, muted: false) == nil)
        let mute = state.consume(device: 1, muted: true)
        #expect(mute?.feature == .microphoneMute)
        #expect(mute?.symbol == "mic.slash.fill")
        #expect(mute?.isActive == false)
        #expect(state.consume(device: 1, muted: true) == nil)
        let unmute = state.consume(device: 1, muted: false)
        #expect(unmute?.symbol == "mic.fill")
        #expect(unmute?.isActive == true)
        #expect(state.consume(device: 2, muted: true) == nil)
        #expect(state.consume(device: 2, muted: nil) == nil)
        #expect(state.consume(device: 2, muted: false) == nil)
        #expect(Feature.microphoneMute.defaultDuration == 2)
    }
}
