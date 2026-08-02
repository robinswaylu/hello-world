import SwiftUI

struct Phase2View: View {
    @StateObject private var bluetoothMonitor = BluetoothRouteMonitor()
    @StateObject private var controller: ScratchController

    init() {
        let engine = ScratchAudioEngine(
            samples: ScratchSampleProvider.loadDefaultSample(),
            sampleRate: SampleLibrary.engineSampleRate
        )
        _controller = StateObject(wrappedValue: ScratchController(audioEngine: engine))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if bluetoothMonitor.isBluetoothRouteActive {
                        bluetoothWarning
                    }
                    statusSection
                    if let startError = controller.startError {
                        Text(startError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("Scratch")
            .onAppear { controller.start() }
            .onDisappear { controller.stop() }
        }
    }

    private var bluetoothWarning: some View {
        Label(
            "Bluetooth audio adds 100-200ms of lag — use wired headphones or a speaker to actually feel the scratch.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.footnote)
        .foregroundStyle(.orange)
        .padding(8)
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sample: Scratch Sentence")
                .font(.caption)
                .foregroundStyle(.secondary)
            readoutRow("Platter state", "\(controller.platterState)")
            readoutRow("Playback rate", String(format: "%.2fx", controller.currentRate))
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
}

#Preview {
    Phase2View()
}
