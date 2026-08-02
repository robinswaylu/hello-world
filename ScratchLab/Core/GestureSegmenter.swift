import Foundation

struct ScratchStroke {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let direction: Direction
    let peakVelocity: Double
    let displacement: Double

    var duration: TimeInterval { endTime - startTime }
}

/// Splits a velocity stream into discrete strokes with hysteresis + debounce:
/// a stroke starts once |velocity| crosses `startThreshold`, and ends once it
/// drops below `stopThreshold` and stays there for `debounceInterval` (or the
/// direction reverses outright, which closes the stroke immediately).
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
        var displacement: Double
        var lastAboveStop: TimeInterval
    }

    func segment(_ samples: [(timestamp: TimeInterval, velocity: Double)]) -> [ScratchStroke] {
        var strokes: [ScratchStroke] = []
        var active: ActiveStroke?

        for i in 0..<samples.count {
            let (t, v) = samples[i]
            let dt = i == 0 ? 0 : t - samples[i - 1].timestamp
            let sampleDirection: Direction = v >= 0 ? .forward : .back

            guard var current = active else {
                if abs(v) >= startThreshold {
                    active = ActiveStroke(start: t, direction: sampleDirection, peak: abs(v), displacement: 0, lastAboveStop: t)
                }
                continue
            }

            let belowStop = abs(v) < stopThreshold
            let reversed = !belowStop && sampleDirection != current.direction

            if belowStop, t - current.lastAboveStop >= debounceInterval {
                strokes.append(makeStroke(current))
                active = nil
            } else if reversed {
                strokes.append(makeStroke(current))
                active = ActiveStroke(start: t, direction: sampleDirection, peak: abs(v), displacement: 0, lastAboveStop: t)
            } else {
                current.peak = max(current.peak, abs(v))
                current.displacement += v * dt
                if !belowStop {
                    current.lastAboveStop = t
                }
                active = current
            }
        }

        if let current = active {
            strokes.append(makeStroke(current))
        }

        return strokes
    }

    private func makeStroke(_ active: ActiveStroke) -> ScratchStroke {
        ScratchStroke(
            startTime: active.start,
            endTime: active.lastAboveStop,
            direction: active.direction,
            peakVelocity: active.peak,
            displacement: active.displacement
        )
    }
}
