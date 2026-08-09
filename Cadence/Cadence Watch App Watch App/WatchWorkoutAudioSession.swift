import AVFoundation

protocol WatchAudioSessioning: AnyObject {
    func setCategory(_ category: AVAudioSession.Category,
                     mode: AVAudioSession.Mode,
                     options: AVAudioSession.CategoryOptions) throws
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
}

extension AVAudioSession: WatchAudioSessioning {}

/// The only place watch workout sounds may configure the system audio session.
/// `.mixWithOthers` is mandatory: bells sit on top of music and podcasts and
/// never pause or duck them.
@MainActor
final class WatchWorkoutAudioSession {
    static let shared = WatchWorkoutAudioSession()

    private let session: any WatchAudioSessioning
    private(set) var isActive = false

    init(session: any WatchAudioSessioning = AVAudioSession.sharedInstance()) {
        self.session = session
    }

    func activateForCues() {
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
            isActive = true
        } catch {
            isActive = false
        }
    }

    func deactivate() {
        guard isActive else { return }
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        isActive = false
    }
}
