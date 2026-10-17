import SwiftUI

/// Single-line text that scrolls horizontally (ticker-tape) when it does not
/// fit, instead of truncating with an ellipsis.
struct WatchMarqueeText: View {
    let text: String
    var font: Font = .headline

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflow: CGFloat { max(0, textWidth - containerWidth) }

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .background(GeometryReader { proxy in
                Color.clear.onAppear { textWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, new in textWidth = new }
            })
            .offset(x: overflow > 0 ? offset : 0)
            .frame(maxWidth: .infinity, alignment: overflow > 0 ? .leading : .center)
            .background(GeometryReader { proxy in
                Color.clear.onAppear { containerWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, new in containerWidth = new }
            })
            .clipped()
            .task(id: overflow) { await scroll() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }

    private func scroll() async {
        offset = 0
        guard overflow > 0 else { return }
        let duration = Double(overflow) / 30 + 0.5
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: duration)) { offset = -overflow }
            try? await Task.sleep(for: .seconds(duration + 1))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { offset = 0 }
            try? await Task.sleep(for: .seconds(0.3))
        }
    }
}
