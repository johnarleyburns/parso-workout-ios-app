import CoreMotion
import Observation

@MainActor
final class RaiseToTalkMonitor: ObservableObject {
    @Published private(set) var isRaised = false
    private let motion = CMMotionManager()

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 15.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            // Phone upright and brought toward the user: deliberately broad so
            // a natural raise works with either hand, but stable enough not to
            // trigger while walking or scrolling.
            let upright = data.gravity.z < -0.55
            let facingUser = data.gravity.y < 0.65
            isRaised = upright && facingUser
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        isRaised = false
    }

}
