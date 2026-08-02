import Foundation

/// Maps a ScratchPattern's beat-based timeline to wall-clock seconds,
/// assuming a standard 4 beats per bar.
enum DrillTimeline {
    static let beatsPerBar = 4.0

    static func beatDuration(bpm: Double) -> TimeInterval {
        60.0 / bpm
    }

    static func totalDuration(pattern: ScratchPattern) -> TimeInterval {
        Double(pattern.bars) * beatsPerBar * beatDuration(bpm: pattern.bpm)
    }
}
