import Foundation

struct ScratchPattern: Codable {
    var id: String
    var name: String
    var bpm: Double
    var bars: Int
    var strokes: [TargetStroke]
    var beatLoopAsset: String?
    var defaultSampleAsset: String

    /// Overrides `PerfectRunCurve.nominalStrokeDisplacement` for this drill,
    /// in radians of platter rotation per stroke. `nil` uses the default.
    ///
    /// Exists because faster subdivisions aren't played with the same
    /// throw: a double-time scratch is a shorter, tighter motion, not the
    /// same distance covered at twice the speed. Without an override, a
    /// drill on sixteenths would inherit the eighth-note throw and demand
    /// double the peak velocity to hit on-target amplitude.
    var nominalStrokeDisplacement: Double?
}

struct TargetStroke: Codable {
    var beatPosition: Double
    var direction: Direction
    var relativeDisplacement: ClosedRange<Double>?
    var timingToleranceMs: Double
}
