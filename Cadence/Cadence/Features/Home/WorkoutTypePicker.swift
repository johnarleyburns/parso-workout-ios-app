import SwiftUI
import CadenceCore
import CadenceFeatures

struct WorkoutTypePicker: View {
    let onSelect: (WorkoutType) -> Void
    let onEditorStart: (EditablePlan) -> Void
    let onOtherCardio: (_ description: String, _ gps: Bool) -> Void
    var recommendation: Recommendation? = nil
    var types: [WorkoutType] = WorkoutType.allCases
    var title: String = "Start Workout"
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 16),
                           GridItem(.flexible(), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(types) { type in
                        switch type {
                        case .weights:
                            NavigationLink {
                                WeightsStartView(onEditorStart: onEditorStart,
                                                 recommendation: recommendation)
                            } label: { WorkoutHero(type: type) }
                                .buttonStyle(.plain)
                                .tapHaptic()
                                .accessibilityIdentifier("startType.\(type.rawValue)")
                                .accessibilityLabel(type.displayName)
                        case .other:
                            NavigationLink {
                                OtherCardioEntryView(onStart: onOtherCardio)
                            } label: { WorkoutHero(type: type) }
                                .buttonStyle(.plain)
                                .tapHaptic()
                                .accessibilityIdentifier("startType.\(type.rawValue)")
                                .accessibilityLabel(type.displayName)
                        default:
                            Button { onSelect(type) } label: { WorkoutHero(type: type) }
                                .buttonStyle(.plain)
                                .tapHaptic()
                                .accessibilityIdentifier("startType.\(type.rawValue)")
                                .accessibilityLabel(type.displayName)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("startType.cancel")
                }
            }
        }
    }
}

struct WorkoutHero: View {
    let type: WorkoutType

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            gradient
            if let ui = UIImage(named: "hero-\(type.rawValue)") {
                Image(uiImage: ui).resizable().scaledToFill()
                    .overlay(LinearGradient(colors: [.clear, .black.opacity(0.5)],
                                            startPoint: .top, endPoint: .bottom))
            }
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: type.symbol).scaledSystemFont(30, relativeTo: .title, weight: .bold)
                Text(type.displayName).font(.title3.bold())
                if type.usesGPS { Text("GPS").font(.caption2).opacity(0.85) }
            }
            .foregroundStyle(.white)
            .padding(12)
            .cadenceGlassIfAvailable(
                in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                interactive: true)
            .padding(2)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .bottomLeading)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var gradient: some View {
        LinearGradient(colors: Self.colors(type), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func colors(_ type: WorkoutType) -> [Color] {
        switch type {
        case .weights: return [.indigo, .purple]
        case .run: return [.blue, .teal]
        case .walk: return [.teal, .green]
        case .cycle: return [.orange, .yellow]
        case .swim: return [.cyan, .blue]
        case .hiit: return [.pink, .red]
        case .boxing: return [.red, .orange]
        case .other: return [.gray, .blue]
        }
    }
}
