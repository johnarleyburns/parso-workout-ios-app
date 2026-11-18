import Foundation
import Testing
import CadenceCore

struct RetiredVoicePreferencesTests {
    @Test func oldVoiceSettingsAreIgnoredAndNotExported() throws {
        let old = Data(#"{"unit":"kg","voiceLoggingEnabled":true,"voiceConfirmationRequired":false,"voiceLanguage":"en-US","smarterVoiceUnderstanding":true,"raiseToTalk":true}"#.utf8)
        let preferences = try JSONDecoder().decode(ExportPreferences.self, from: old)
        #expect(preferences.unit == "kg")
        let exported = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String: Any])
        for key in ["voiceLoggingEnabled", "voiceConfirmationRequired", "voiceLanguage",
                    "smarterVoiceUnderstanding", "raiseToTalk"] {
            #expect(exported[key] == nil)
        }
    }
}
