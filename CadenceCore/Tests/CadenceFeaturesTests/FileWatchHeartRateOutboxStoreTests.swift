import Testing
import Foundation
@testable import CadenceFeatures

private final class MemoryFS: WatchOutboxFileSystem {
    var files: [String: Data] = [:]
    var failWrites = false
    struct Failure: Error {}
    func read(_ name: String) -> Data? { files[name] }
    func writeAtomically(_ data: Data, to name: String) throws {
        if failWrites { throw Failure() }
        files[name] = data
    }
    func move(_ name: String, to newName: String) throws {
        files[newName] = files.removeValue(forKey: name)
    }
}

private final class SpyLegacy: WatchOutboxLegacyReader {
    var values: [String: Data] = [:]
    var readKeys: [String] = []
    func data(forKey key: String) -> Data? { readKeys.append(key); return values[key] }
}

private func sampleState(_ tag: UInt8 = 1, retired: Bool = false) -> WatchHeartRateOutboxState {
    let id = { (n: UInt8) in UUID(uuid: (n, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, tag)) }
    var s = WatchHeartRateOutboxState(phoneWorkoutSessionID: id(1), watchRequestID: id(2), captureEpoch: id(3))
    s.nextSequence = 3
    let obs = WatchHRObservation(observationID: id(4), source: .watchHealthKit, sampleEnd: 1_800_000_000, bpm: 120, sampleID: "x")
    s.pending = [obs]
    s.batches = [.init(deliveryID: id(5), sequence: 2, observations: [obs], durableQueuedAt: 5)]
    s.seenKeys = ["id:x"]
    if retired { s.retired = [sampleState(9)] }
    return s
}

private func makeStore(_ fs: MemoryFS, _ legacy: SpyLegacy, strength: Bool = false) -> FileWatchHeartRateOutboxStore {
    FileWatchHeartRateOutboxStore(
        fileSystem: fs, legacy: legacy,
        fileName: strength ? FileWatchHeartRateOutboxStore.strengthCompletionFileName : FileWatchHeartRateOutboxStore.heartRateFileName,
        legacyKey: strength ? FileWatchHeartRateOutboxStore.strengthCompletionLegacyKey : FileWatchHeartRateOutboxStore.heartRateLegacyKey)
}

struct FileWatchHeartRateOutboxStoreTests {
    @Test func legacyHRJournalMigratesByteForByteSemanticallyBeforeFirstFileRead() throws {
        let fs = MemoryFS(), legacy = SpyLegacy()
        let state = sampleState(retired: true)
        legacy.values["watch.hrOutbox.v1"] = try JSONEncoder().encode(state)
        #expect(makeStore(fs, legacy).load() == state)
        let bytes = try #require(fs.files[FileWatchHeartRateOutboxStore.heartRateFileName])
        #expect(try JSONSerialization.jsonObject(with: bytes) is [String: Any])
        #expect(makeStore(fs, legacy).load() == state)
        #expect(String(decoding: bytes, as: UTF8.self).contains("\"version\":1"))
    }

    @Test func legacyStrengthCompletionJournalMigratesToItsOwnFileWithoutChangingLegacyDefaults() throws {
        let fs = MemoryFS(), legacy = SpyLegacy()
        let state = sampleState()
        legacy.values["watch.strengthCompletionOutbox.v1"] = try JSONEncoder().encode(state)
        let before = legacy.values
        #expect(makeStore(fs, legacy, strength: true).load() == state)
        #expect(Set(legacy.readKeys) == ["watch.strengthCompletionOutbox.v1"])
        #expect(legacy.values == before)
        #expect(Set(fs.files.keys) == [FileWatchHeartRateOutboxStore.strengthCompletionFileName])
    }

    @Test func committedEmptyTombstonePreventsLegacyJournalFromReturning() throws {
        let fs = MemoryFS(), legacy = SpyLegacy()
        legacy.values["watch.hrOutbox.v1"] = try JSONEncoder().encode(sampleState())
        let store = makeStore(fs, legacy)
        #expect(store.load() != nil)
        store.clear()
        legacy.readKeys = []
        let relaunched = makeStore(fs, legacy)
        #expect(relaunched.load() == nil)
        #expect(legacy.readKeys.isEmpty)
    }

    @Test func failedAtomicReplacementKeepsPreviousCommittedJournal() throws {
        let fs = MemoryFS(), legacy = SpyLegacy()
        let a = sampleState(1), b = sampleState(2)
        try makeStore(fs, legacy).save(a)
        fs.failWrites = true
        #expect(throws: MemoryFS.Failure.self) { try makeStore(fs, legacy).save(b) }
        #expect(makeStore(fs, legacy).load() == a)
    }

    @Test func failedLegacyMigrationDoesNotMarkMigrationComplete() throws {
        let fs = MemoryFS(), legacy = SpyLegacy()
        let state = sampleState()
        legacy.values["watch.hrOutbox.v1"] = try JSONEncoder().encode(state)
        let before = legacy.values
        fs.failWrites = true
        let store = makeStore(fs, legacy)
        #expect(store.load() == state)
        #expect(store.lastIssue == .legacyMigrationWriteFailed)
        #expect(fs.files.isEmpty)
        #expect(legacy.values == before)
        fs.failWrites = false
        #expect(makeStore(fs, legacy).load() == state)
        #expect(fs.files[FileWatchHeartRateOutboxStore.heartRateFileName] != nil)
    }

    @Test func unreadableFileIsQuarantinedWithoutCrashingOrSilentlyOverwritingBytes() {
        let fs = MemoryFS(), legacy = SpyLegacy()
        let junk = Data("not json".utf8)
        fs.files[FileWatchHeartRateOutboxStore.heartRateFileName] = junk
        let store = makeStore(fs, legacy)
        #expect(store.load() == nil)
        #expect(store.lastIssue == .unreadableFileQuarantined)
        #expect(fs.files[store.quarantineFileName] == junk)
        #expect(fs.files[FileWatchHeartRateOutboxStore.heartRateFileName] == nil)
    }

    @Test func twoStoreInstancesUseIndependentFileNames() throws {
        let fs = MemoryFS(), legacy = SpyLegacy()
        let hr = makeStore(fs, legacy), strength = makeStore(fs, legacy, strength: true)
        let a = sampleState(1), b = sampleState(2)
        try hr.save(a); try strength.save(b)
        strength.clear()
        #expect(makeStore(fs, legacy).load() == a)
        #expect(makeStore(fs, legacy, strength: true).load() == nil)
        #expect(fs.files.count == 2)
    }
}
