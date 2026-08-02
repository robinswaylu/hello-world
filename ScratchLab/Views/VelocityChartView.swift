import SwiftUI
import Charts

/// Live scrolling chart of Z angular velocity, last 5 seconds.
struct VelocityChartView: View {
    let samples: [GyroSample]
    let clippingThresholdDegPerSec: Double

    var body: some View {
        Chart {
            ForEach(samples) { sample in
                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Z (deg/s)", sample.zDegPerSec)
                )
            }
            RuleMark(y: .value("Clip", clippingThresholdDegPerSec))
                .foregroundStyle(.red.opacity(0.5))
            RuleMark(y: .value("Clip", -clippingThresholdDegPerSec))
                .foregroundStyle(.red.opacity(0.5))
        }
        .chartXAxis(.hidden)
        .chartYAxisLabel("deg/s")
        .frame(height: 220)
    }
}
