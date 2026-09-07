import CadenceCore

struct ActiveIntervalSession {
    let plan: IntervalPlan
    let kind: String
}

extension WatchRootView {
    func cardioType(from raw: String?) -> CardioType {
        guard let raw, let type = CardioType(rawValue: raw) else { return .other }
        return type
    }

    var cardioTypes: [CardioType] {
        [.run, .walk, .cycle, .swim, .hiit, .boxing, .rowing, .other]
    }
}
