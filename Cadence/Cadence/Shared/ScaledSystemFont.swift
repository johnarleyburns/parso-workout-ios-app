import SwiftUI

extension View {
    /// A fixed-design system font (specific point size, weight, rounded design)
    /// that **scales with Dynamic Type**. Drop-in replacement for the non-scaling
    /// `.font(.system(size:weight:design:))` on large numerics, timers, and icons.
    /// `relativeTo` sets which text style drives the scaling curve.
    func scaledSystemFont(_ size: CGFloat,
                          relativeTo textStyle: Font.TextStyle = .body,
                          weight: Font.Weight = .regular,
                          design: Font.Design = .default) -> some View {
        modifier(ScaledSystemFontModifier(size: size, relativeTo: textStyle,
                                          weight: weight, design: design))
    }
}

private struct ScaledSystemFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    init(size: CGFloat, relativeTo textStyle: Font.TextStyle,
         weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}
