import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var bluetoothMonitor = BluetoothRouteMonitor()
    @State private var step = 0
    @State private var isCalibrating = false
    @State private var detectedOrientation: ScreenOrientation?

    var body: some View {
        VStack(spacing: 24) {
            switch step {
            case 0: placementStep
            case 1: calibrationStep
            default: audioRouteStep
            }
        }
        .padding()
        .animation(.default, value: step)
    }

    private var placementStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "record.circle")
                .font(.system(size: 64))
            Text("Place your phone on the record")
                .font(.title2.bold())
            Text("Lay it flat, screen facing up, held in place with a grip pad or rubber band. It doesn't need to be centered — rotation reads the same anywhere on a rigid spinning surface.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Next") { step = 1 }
                .buttonStyle(.borderedProminent)
        }
    }

    private var calibrationStep: some View {
        VStack(spacing: 16) {
            Text("Calibrate orientation")
                .font(.title2.bold())
            Text("With the phone flat as you'll actually use it, tap Calibrate. This is a one-time check so scratches read the correct direction whether it ends up screen-up or screen-down.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if let detectedOrientation {
                Label(
                    detectedOrientation == .screenUp ? "Screen-up detected" : "Screen-down detected",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
            }

            Button(isCalibrating ? "Calibrating…" : "Calibrate") {
                calibrate()
            }
            .buttonStyle(.bordered)
            .disabled(isCalibrating)

            Button("Next") { step = 2 }
                .buttonStyle(.borderedProminent)
                .disabled(detectedOrientation == nil)
        }
    }

    private var audioRouteStep: some View {
        VStack(spacing: 16) {
            Text("Check your audio output")
                .font(.title2.bold())
            if bluetoothMonitor.isBluetoothRouteActive {
                Label(
                    "Bluetooth is connected — switch to wired headphones or a speaker. Bluetooth adds 100-200ms of lag that makes scratching feel broken.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                .multilineTextAlignment(.leading)
            } else {
                Label("Wired output detected — you're good to go.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Button("Get Started") { hasCompletedOnboarding = true }
                .buttonStyle(.borderedProminent)
        }
    }

    @MainActor
    private func calibrate() {
        isCalibrating = true
        Task {
            let stream = RotationStream()
            var gravitySamples: [Double] = []
            for await sample in stream.samples() {
                gravitySamples.append(sample.gravityZ)
                if gravitySamples.count >= 30 { break }
            }
            stream.stop()

            let averageGravityZ = gravitySamples.reduce(0, +) / Double(max(gravitySamples.count, 1))
            let orientation = OrientationCalibrator.orientation(gravityZ: averageGravityZ)
            CalibrationStore.signMultiplier = OrientationCalibrator.signMultiplier(for: orientation)
            detectedOrientation = orientation
            isCalibrating = false
        }
    }
}
