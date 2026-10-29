import AVFoundation
import CadenceFeatures

protocol WatchAudioSessioning: AnyObject {
    func setCategory(_ category: AVAudioSession.Category,
                     mode: AVAudioSession.Mode,
                     options: AVAudioSession.CategoryOptions) throws
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
}

extension AVAudioSession: WatchAudioSessioning {}

/// AV adapter for `WatchCueAudioCoordinator`, the only owner of the cue session.
/// `.mixWithOthers` is mandatory: speech and bells sit on top of music and podcasts and
/// never pause or duck them. Only deactivation carries `.notifyOthersOnDeactivation`.
@MainActor
final class WatchWorkoutAudioSession: WatchCueSessionDriving {
    private let session: any WatchAudioSessioning

    init(session: any WatchAudioSessioning = AVAudioSession.sharedInstance()) {
        self.session = session
    }

    func activateMixingPlayback() throws {
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            throw Self.classify(error)
        }
    }

    func deactivateNotifyingOthers() throws {
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            throw Self.classify(error)
        }
    }

    /// `isBusy` is reported while the session is still deactivating.
    static func classify(_ error: Error) -> WatchCueSessionError {
        let ns = error as NSError
        if ns.domain == NSOSStatusErrorDomain,
           ns.code == AVAudioSession.ErrorCode.isBusy.rawValue {
            return .busy
        }
        return .failed(domain: ns.domain, code: ns.code)
    }
}
