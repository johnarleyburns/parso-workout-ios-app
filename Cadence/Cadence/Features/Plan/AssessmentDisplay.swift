import SwiftUI
import CadenceCore
import CadenceFeatures

// View-layer mapping of `AssessmentTrend` to SwiftUI `Color`/SF Symbols. The
// pure `AssessmentDisplay` formatting lives in `CadenceFeatures` (test-pyramid
// Phase 1); only the presentation tint/symbol stays here.
extension AssessmentTrend {
    var symbol: String {
        switch self {
        case .improved: return "arrow.up.right"
        case .declined: return "arrow.down.right"
        case .unchanged: return "equal"
        case .single: return "circle"
        }
    }
    var tint: Color {
        switch self {
        case .improved: return .green
        case .declined: return .orange
        case .unchanged, .single: return .secondary
        }
    }
    var label: String {
        switch self {
        case .improved: return "Improving"
        case .declined: return "Down"
        case .unchanged: return "Holding"
        case .single: return "Baseline"
        }
    }
}
