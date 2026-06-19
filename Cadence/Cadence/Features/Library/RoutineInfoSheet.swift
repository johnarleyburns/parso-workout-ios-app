import SwiftUI
import CadenceCore

struct RoutineInfoSheet: View {
    let info: RoutineInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(info.summary)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(info.citations) { citation in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("The Science").font(.headline)
                            Text(citation.title)
                                .font(.subheadline.weight(.medium))
                            Text(citation.shortText)
                                .font(.caption).foregroundStyle(.secondary)
                            if let url = URL(string: citation.url) {
                                Link(destination: url) {
                                    HStack(spacing: 4) {
                                        Text("Read the paper")
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption2)
                                    }
                                    .font(.subheadline)
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .navigationTitle(info.groupName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("routineInfo")
    }
}
