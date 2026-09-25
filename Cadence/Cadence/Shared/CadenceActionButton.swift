import SwiftUI
import CadenceFeatures

/// The one full-width action control. Every primary/secondary full-width button
/// on Home, Start Workout, Workout Plan and the live workout uses this (or, for
/// `NavigationLink` labels, `cadenceActionLabel()`) so the heights and typography
/// cannot drift again (field test 2026-08-18 issue 3).
///
/// It draws its own fill rather than using `.borderedProminent`/`.bordered`:
/// those styles add their own vertical padding *on top of* a `minHeight`, so a
/// bordered button and a gradient hero label with the same declared height still
/// render 14pt apart. Owning the fill makes `LayoutMetrics.actionButtonHeight`
/// the actual rendered height on every surface, and gives the corner radius the
/// plan asks for. Accessibility identifiers are deliberately NOT baked in — the
/// call site keeps its existing id so the smoke test and unit tests stay valid.
struct CadenceActionButton: View {
    enum Emphasis { case primary, secondary }

    let title: String
    let systemImage: String
    var emphasis: Emphasis = .primary
    /// Defaults to green for primary actions and the app accent for secondary,
    /// matching what `.borderedProminent`/`.bordered` rendered before.
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .tint(tint ?? (emphasis == .primary ? CadenceTheme.accent : .accentColor))
        .controlSize(.large)
        .modifier(CadenceSystemButtonStyle(emphasis: emphasis))
    }
}

private struct CadenceSystemButtonStyle: ViewModifier {
    let emphasis: CadenceActionButton.Emphasis
    @ViewBuilder
    func body(content: Content) -> some View {
        if emphasis == .primary {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

extension View {
    /// Applies the canonical full-width action geometry to a label. System button
    /// styles own the visual treatment; this only keeps hit targets consistent.
    func cadenceActionLabel(alignment: Alignment = .leading) -> some View {
        font(.headline)
        .frame(maxWidth: .infinity,
                   minHeight: CGFloat(LayoutMetrics.actionButtonHeight),
                   alignment: alignment)
        .contentShape(Rectangle())
    }
}

/// The shape every full-width action is clipped/filled with.
enum CadenceActionShape {
    static var rounded: RoundedRectangle {
        RoundedRectangle(cornerRadius: CGFloat(LayoutMetrics.actionButtonCornerRadius),
                         style: .continuous)
    }
}
