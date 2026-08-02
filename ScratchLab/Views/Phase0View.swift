import SwiftUI

struct Phase0View: View {
    @StateObject private var monitor = MotionMonitor()
    @State private var clickPlayer = LatencyClickPlayer(thresholdRadPerSec: 1.0)
    @State private var latencyProbeArmed = false
    @State private var isShowingShareSheet = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var sessionStart = Date()
    @AppStorage("hapticsEnabled") private var hapticsEnabled = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    captureSection
                    readoutSection
                    VelocityChartView(
                        samples: monitor.recentSamples,
                        clippingThresholdDegPerSec: MotionMonitor.gyroFullScaleRadPerSec
                            * MotionMonitor.clippingThresholdFraction * 180.0 / .pi
                    )
                    latencyProbeSection
                    exportSection
                    settingsSection
                    if let error = monitor.lastError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("Phase 0 — Diagnostics")
            .onChange(of: monitor.currentZ) { _, newValue in
                clickPlayer.evaluate(velocity: newValue, timestamp: monitor.allSamples.last?.timestamp ?? 0)
            }
            .sheet(isPresented: $isShowingShareSheet) {
                if let exportURL {
                    ShareSheet(activityItems: [exportURL])
                }
            }
        }
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(monitor.usingRawGyroFallback ? "Source: raw gyro (fallback)" : "Source: device motion")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(monitor.isCapturing ? "Stop Capture" : "Start Capture") {
                if monitor.isCapturing {
                    monitor.stop()
                } else {
                    sessionStart = Date()
                    monitor.start()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var readoutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            readoutRow("Z velocity", "\(format(monitor.currentZ.degrees)) deg/s  (\(format(monitor.currentZ.rpm)) RPM)")
            readoutRow("Session min / max", "\(format(monitor.sessionMin.degrees)) / \(format(monitor.sessionMax.degrees)) deg/s")
            readoutRow("Achieved sample rate", "\(format(monitor.achievedSampleRateHz)) Hz")
            readoutRow("Clipping count", "\(monitor.clippingCount)")
            readoutRow("Samples captured", "\(monitor.allSamples.count)")
        }
    }

    private func readoutRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.subheadline)
    }

    private var latencyProbeSection: some View {
        Toggle("Audio latency probe (click on threshold)", isOn: $latencyProbeArmed)
            .onChange(of: latencyProbeArmed) { _, armed in
                clickPlayer.setArmed(armed)
            }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Export Session CSV") {
                exportCSV()
            }
            .disabled(monitor.allSamples.isEmpty)

            if let exportError {
                Text(exportError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Haptic feedback on drill hit/miss", isOn: $hapticsEnabled)
            Text("Off by default: the phone sits on the platter during capture, and vibration pollutes the gyro reading.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Re-run Onboarding / Recalibrate") {
                hasCompletedOnboarding = false
            }
            .buttonStyle(.bordered)
        }
    }

    private func exportCSV() {
        do {
            let url = try CSVExporter.writeTemporaryFile(samples: monitor.allSamples, sessionStart: sessionStart)
            exportURL = url
            exportError = nil
            isShowingShareSheet = true
        } catch {
            exportError = "Export failed: \(error.localizedDescription)"
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

private extension Double {
    var degrees: Double { self * 180.0 / .pi }
    var rpm: Double { (self * 60.0) / (2 * .pi) }
}

#Preview {
    Phase0View()
}
