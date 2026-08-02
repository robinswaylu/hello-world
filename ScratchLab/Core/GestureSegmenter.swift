import Foundation

struct ScratchStroke {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let direction: Direction
    let peakVelocity: Double
    let displacement: Double

    /// When during the stroke |velocity| was highest. This, not
    /// `startTime`, is what timing is graded on: `startTime` is defined by
    /// crossing the segmenter's start threshold, so it slides around
    /// depending on how gently the stroke is eased into, while the peak is
    /// a sharp, well-defined feature of the motion. It's also the point
    /// the practice chart draws each target dot at, so "peak on the dot"
    /// means the same thing to the eye as it does to the scorer.
    let peakTime: TimeInterval

    var duration: TimeInterval { endTime - startTime }

    init(
        startTime: TimeInterval,
        endTime: TimeInterval,
        direction: Direction,
        peakVelocity: Double,
        displacement: Double,
        peakTime: TimeInterval? = nil
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.direction = direction
        self.peakVelocity = peakVelocity
        self.displacement = displacement
        self.peakTime = peakTime ?? (startTime + endTime) / 2
    }
}

/// Splits a velocity stream into discrete strokes with hysteresis + debounce:
/// a stroke starts once |velocity| crosses `startThreshold`, and ends once it
/// drops below `stopThreshold` and stays there for `debounceInterval` (or the
/// direction reverses outright, which closes the stroke immediately).
///
/// `ingest(timestamp:velocity:)` is the live-capture entry point: O(1) per
/// sample, carrying the in-progress stroke's state across calls. `segment(_:)`
/// is a one-shot convenience (existing tests, offline analysis) that replays
/// a whole array through a fresh copy - don't call it in a live per-sample
/// loop, since re-scanning a growing buffer from scratch on every sample is
/// O(n) per call and O(n^2) over a whole session (this is exactly what made
/// practice mode feel laggy, and get progressively laggier as a drill went
/// on: the buffer it was rescanning kept growing).
struct GestureSegmenter {
    var startThreshold: Double
    var stopThreshold: Double
    var debounceInterval: TimeInterval

    init(startThreshold: Double = 0.3, stopThreshold: Double = 0.1, debounceInterval: TimeInterval = 0.03) {
        self.startThreshold = startThreshold
        self.stopThreshold = stopThreshold
        self.debounceInterval = debounceInterval
    }

    private struct ActiveStroke {
        var start: TimeInterval
        var direction: Direction
        var peak: Double
        var peakTime: TimeInterval
        var displacement: Double
        var lastAboveStop: TimeInterval
    }

    private var active: ActiveStroke?
    private var lastTimestamp: TimeInterval?

    /// The in-progress stroke, if any, as it would look if it ended right
    /// now - lets live scoring match against a stroke that hasn't actually
    /// closed yet, without mutating the segmenter's state.
    var pendingStroke: ScratchStroke? {
        active.map(makeStroke)
    }

    /// Feeds one new sample in O(1). Returns a completed stroke exactly when
    /// one closes (dropped below the stop threshold past the debounce
    /// window, or a hard direction reversal) - nil otherwise.
    @discardableResult
    mutating func ingest(timestamp: TimeInterval, velocity: Double) -> ScratchStroke? {
        let dt = lastTimestamp.map { timestamp - $0 } ?? 0
        lastTimestamp = timestamp
        let sampleDirection: Direction = velocity >= 0 ? .forward : .back

        guard var current = active else {
            if abs(velocity) >= startThreshold {
                active = ActiveStroke(start: timestamp, direction: sampleDirection, peak: abs(velocity), peakTime: timestamp, displacement: 0, lastAboveStop: timestamp)
            }
            return nil
        }

        let belowStop = abs(velocity) < stopThreshold
        let reversed = !belowStop && sampleDirection != current.direction

        if belowStop, timestamp - current.lastAboveStop >= debounceInterval {
            active = nil
            return makeStroke(current)
        } else if reversed {
            active = ActiveStroke(start: timestamp, direction: sampleDirection, peak: abs(velocity), peakTime: timestamp, displacement: 0, lastAboveStop: timestamp)
            return makeStroke(current)
        } else {
            if abs(velocity) > current.peak {
                current.peak = abs(velocity)
                current.peakTime = timestamp
            }
            current.displacement += velocity * dt
            if !belowStop {
                current.lastAboveStop = timestamp
            }
            active = current
            return nil
        }
    }

    /// One-shot convenience: replays `samples` through a fresh copy of this
    /// segmenter's configuration, ignoring any state already accumulated on
    /// `self`. See the type doc for why this isn't for live per-sample use.
    func segment(_ samples: [(timestamp: TimeInterval, velocity: Double)]) -> [ScratchStroke] {
        var copy = self
        copy.active = nil
        copy.lastTimestamp = nil

        var strokes: [ScratchStroke] = []
        for sample in samples {
            if let stroke = copy.ingest(timestamp: sample.timestamp, velocity: sample.velocity) {
                strokes.append(stroke)
            }
        }
        if let pending = copy.pendingStroke {
            strokes.append(pending)
        }
        return strokes
    }

    private func makeStroke(_ active: ActiveStroke) -> ScratchStroke {
        ScratchStroke(
            startTime: active.start,
            endTime: active.lastAboveStop,
            direction: active.direction,
            peakVelocity: active.peak,
            displacement: active.displacement,
            peakTime: active.peakTime
        )
    }
}
