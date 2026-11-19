import Testing
@testable import CadenceCore

struct CoachWarningModalityTests {
    @Test func modalityDefaultsToGeneralWhenNotSpecified() {
        let w = CoachWarning(id: "x", message: "m")
        #expect(w.modality == .general)
    }

    @Test func modalityIsStoredWhenSpecified() {
        let w = CoachWarning(id: "x", message: "m", modality: .strength)
        #expect(w.modality == .strength)
    }
}
