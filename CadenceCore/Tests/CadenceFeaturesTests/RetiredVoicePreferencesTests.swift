import XCTest
import Foundation
import CadenceCore

final class RetiredVoicePreferencesTests: XCTestCase {
    func testOldVoiceSettingsAreIgnoredAndNotExported() throws {
        let old = Data(#"{"unit":"kg","voiceLoggingEnabled":true,"voiceConfirmationRequired":false,"voiceLanguage":"en-US","smarterVoiceUnderstanding":true,"raiseToTalk":true}"#.utf8)
        let preferences = try JSONDecoder().decode(ExportPreferences.self, from: old)
        XCTAssertEqual(preferences.unit, "kg")
        let exported = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String: Any])
        for key in ["voiceLoggingEnabled", "voiceConfirmationRequired", "voiceLanguage",
                    "smarterVoiceUnderstanding", "raiseToTalk"] {
            XCTAssertNil(exported[key])
        }
    }
}
