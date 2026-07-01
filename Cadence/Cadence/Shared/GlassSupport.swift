import SwiftUI

/// Master switch for custom Liquid Glass call sites. iOS 17-25 always use the
/// material fallback regardless of this flag.
enum GlassFeature {
    static var isEnabled = true
}

extension View {
    /// Liquid Glass on iOS 26+, the call site's existing material on iOS 17-25
    /// or when the feature flag is disabled.
    @ViewBuilder
    func cadenceGlass<S: Shape>(
        in shape: S = Capsule(),
        tint: Color? = nil,
        interactive: Bool = false,
        fallback: Material = .ultraThinMaterial
    ) -> some View {
        if GlassFeature.isEnabled, #available(iOS 26.0, *) {
            glassEffect(GlassFactory.regular(tint: tint, interactive: interactive), in: shape)
        } else {
            background(fallback, in: shape)
        }
    }

    /// Liquid Glass on iOS 26+, otherwise the call site's original non-material
    /// background style. Use this for existing solid/gradient entry controls.
    @ViewBuilder
    func cadenceGlassBackground<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        fallback: AnyShapeStyle
    ) -> some View {
        if GlassFeature.isEnabled, #available(iOS 26.0, *) {
            glassEffect(GlassFactory.regular(tint: tint, interactive: interactive), in: shape)
        } else {
            background(fallback, in: shape)
        }
    }

    /// Adds glass only when the SDK/runtime supports it; older OSes render the
    /// view exactly as provided by the caller.
    @ViewBuilder
    func cadenceGlassIfAvailable<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if GlassFeature.isEnabled, #available(iOS 26.0, *) {
            glassEffect(GlassFactory.regular(tint: tint, interactive: interactive), in: shape)
        } else {
            self
        }
    }

    /// Glass button on iOS 26+, matching bordered button style elsewhere.
    @ViewBuilder
    func cadenceGlassButton(prominent: Bool = false, tint: Color? = nil) -> some View {
        if GlassFeature.isEnabled, #available(iOS 26.0, *) {
            glassButtonStyled(prominent: prominent, tint: tint)
        } else {
            borderedButtonStyled(prominent: prominent, tint: tint)
        }
    }

    @ViewBuilder
    func glassGroup(spacing: CGFloat = 12) -> some View {
        if GlassFeature.isEnabled, #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    private func glassButtonStyled(prominent: Bool, tint: Color?) -> some View {
        if prominent {
            buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(tint)
        } else {
            buttonStyle(.glass)
                .controlSize(.large)
                .tint(tint)
        }
    }

    @ViewBuilder
    private func borderedButtonStyled(prominent: Bool, tint: Color?) -> some View {
        if prominent {
            buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(tint)
        } else {
            buttonStyle(.bordered)
                .controlSize(.large)
                .tint(tint)
        }
    }
}

@available(iOS 26.0, *)
private enum GlassFactory {
    static func regular(tint: Color?, interactive: Bool) -> Glass {
        var glass: Glass = .regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}
