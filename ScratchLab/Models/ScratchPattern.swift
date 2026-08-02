import Foundation

struct ScratchPattern: Codable {
    var id: String
    var name: String
    var bpm: Double
    var bars: Int
    var strokes: [TargetStroke]
    var beatLoopAsset: String?
    var defaultSampleAsset: String
}

struct TargetStroke: Codable {
    var beatPosition: Double
    var direction: Direction
    var relativeDisplacement: ClosedRange<Double>?
    var timingToleranceMs: Double
}
