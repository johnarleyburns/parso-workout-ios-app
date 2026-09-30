import SwiftUI

extension ExerciseCardView {
    @ViewBuilder
    func setIndexBadge(_ label: String, isWarmup: Bool) -> some View {
        Group {
            if isWarmup {
                Text("W").font(.caption2.weight(.bold)).foregroundStyle(.orange)
                    .frame(width: 22, height: 22).background(.orange.opacity(0.15), in: Circle())
            } else {
                Text(label).font(.subheadline.weight(.medium)).monospacedDigit()
            }
        }
        .frame(width: SetCol.num, alignment: .leading)
    }
}
