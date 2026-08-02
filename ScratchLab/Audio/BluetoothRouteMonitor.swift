import AVFoundation

/// The spec treats Bluetooth output as a correctness bug, not a preference:
/// BT typically adds 100-200ms of extra latency on top of the scratch
/// engine's own budget, enough to make scratching feel broken.
@MainActor
final class BluetoothRouteMonitor: ObservableObject {
    @Published private(set) var isBluetoothRouteActive = false

    private var observer: NSObjectProtocol?

    init() {
        refresh()
        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func refresh() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        isBluetoothRouteActive = outputs.contains { output in
            switch output.portType {
            case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
                return true
            default:
                return false
            }
        }
    }
}
