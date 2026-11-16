import SmartTubeIOSCore
import SwiftUI

// MARK: - App glass

extension View {
    /// Background for the app's own translucent surfaces (player controls, mini player,
    /// panels), following Settings › Glass: `material` as designed, a heavier frosted
    /// material, or solid.
    func appGlass<S: Shape>(_ material: Material, in shape: S) -> some View {
        modifier(AppGlassBackground(material: material, shape: shape))
    }

    /// `appGlass(_:in:)` filling the view's whole frame.
    func appGlass(_ material: Material) -> some View {
        appGlass(material, in: Rectangle())
    }
}

private struct AppGlassBackground<S: Shape>: ViewModifier {
    let material: Material
    let shape: S
    /// Optional: a surface shown outside the settings environment keeps the standard look.
    @Environment(SettingsStore.self) private var store: SettingsStore?

    func body(content: Content) -> some View {
        switch store?.settings.glassStyle ?? .standard {
        case .standard:
            content.background(material, in: shape)
        case .frosted:
            content.background(.thickMaterial, in: shape)
        case .solid:
            content.background(.background.secondary, in: shape)
        }
    }
}
