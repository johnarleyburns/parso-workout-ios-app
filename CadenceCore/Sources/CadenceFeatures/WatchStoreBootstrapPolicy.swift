import Foundation

/// Pure, injectable policy for the Watch local-store recovery boundary. The
/// Watch App supplies SwiftData/container and filesystem adapters; tests supply
/// doubles and therefore never touch the developer's Application Support.
public struct WatchStoreBootstrapPolicy<Container> {
    public enum State: Equatable { case idle, opening, quarantining, retrying, ready, recovered, degraded }
    public enum Failure: Error, Equatable {
        case open(String)
        case quarantine(String)
        case retry(String)
        case inMemory(String)
    }
    public struct Result {
        public let container: Container?
        public let state: State
        public let quarantinedAt: URL?
        public init(container: Container?, state: State, quarantinedAt: URL? = nil) {
            self.container = container; self.state = state; self.quarantinedAt = quarantinedAt
        }
    }
    public let createPersistent: () throws -> Container
    public let createInMemory: () throws -> Container
    public let quarantine: () throws -> URL?
    public let seed: (Container) throws -> Void

    public init(createPersistent: @escaping () throws -> Container,
                createInMemory: @escaping () throws -> Container,
                quarantine: @escaping () throws -> URL?,
                seed: @escaping (Container) throws -> Void) {
        self.createPersistent = createPersistent; self.createInMemory = createInMemory
        self.quarantine = quarantine; self.seed = seed
    }

    public func open() -> Result {
        do {
            let container = try createPersistent()
            try seed(container)
            return Result(container: container, state: .ready)
        } catch {
            do {
                let location = try quarantine()
                do {
                    let container = try createPersistent()
                    try seed(container)
                    return Result(container: container, state: .recovered, quarantinedAt: location)
                } catch {
                    return degraded(after: .retry(String(describing: error)))
                }
            } catch {
                return degraded(after: .quarantine(String(describing: error)))
            }
        }
    }

    private func degraded(after failure: Failure) -> Result {
        do { return Result(container: try createInMemory(), state: .degraded) }
        catch { return Result(container: nil, state: .degraded) }
    }
}

public enum WatchStoreFiles {
    public static let exactNames = ["default.store", "default.store-shm", "default.store-wal"]
    public static func recoveryDirectory(in applicationSupport: URL, id: UUID = UUID()) -> URL {
        applicationSupport.appendingPathComponent("Recovery-\(id.uuidString)", isDirectory: true)
    }
}
