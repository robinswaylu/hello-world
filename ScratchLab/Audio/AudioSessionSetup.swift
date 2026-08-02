import AVFoundation

/// Shared audio-session configuration, plus the output latency reading that
/// depends on it.
///
/// This exists as its own step because *when* the session is activated
/// matters. `AVAudioSession.outputLatency` only reports a meaningful value
/// once the session is active, and `PracticeSession` needs it before it
/// takes its timing anchor - earlier than `ScratchAudioEngine.start()`,
/// which is where session setup used to live.
enum AudioSessionSetup {
    static let preferredIOBufferDuration: TimeInterval = 0.005

    /// Configures the shared session for playback and activates it.
    /// Idempotent - safe to call from every engine that needs it.
    static func activate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setPreferredIOBufferDuration(preferredIOBufferDuration)
        try? session.setActive(true)
    }

    /// How long after a buffer is scheduled it actually reaches the
    /// listener's ears: the route's own latency plus the render quantum a
    /// "play now" buffer has to wait for.
    ///
    /// Roughly 20-40ms on wired output and 150-250ms over Bluetooth. That
    /// upper end is more than two full grading bands, which is why the
    /// drill's timeline is offset by this rather than ignoring it - the
    /// click a player is following is heard this much after the moment it
    /// was scheduled for, and their motion (which the gyro timestamps
    /// with no such delay) follows what they hear.
    ///
    /// Call `activate()` first; before the session is active this reads 0.
    static var outputLatency: TimeInterval {
        let session = AVAudioSession.sharedInstance()
        return session.outputLatency + session.ioBufferDuration
    }
}
