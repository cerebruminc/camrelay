import CamRelayCore
import Testing

@Test("Source switching resets media position without resetting camera time")
func switchesPlaybackClock() {
    var clock = PlaybackClock()
    #expect(clock.position(at: 500) == 500)
    clock.select(at: 500, paused: false)
    #expect(clock.position(at: 550) == 50)
    #expect(clock.position(at: 490) == 0)
    #expect(clock.generation == 2)
}

@Test("Pause holds source position and resume excludes the paused interval")
func pausesPlaybackClock() {
    var clock = PlaybackClock()
    clock.setPaused(true, at: 100)
    #expect(clock.position(at: 1_000) == 100)
    clock.setPaused(false, at: 1_000)
    #expect(clock.position(at: 1_050) == 150)
    #expect(clock.generation == 3)
    clock.setPaused(false, at: 1_100)
    #expect(clock.generation == 3)
}

@Test("Selecting paused holds the first source frame until play")
func selectsPaused() {
    var clock = PlaybackClock()
    clock.select(at: 500, paused: true)
    #expect(clock.position(at: 900) == 0)
    clock.setPaused(false, at: 900)
    #expect(clock.position(at: 950) == 50)
}
