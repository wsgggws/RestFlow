import SwiftUI

/// Opacity affects only the visual layer, retaining the original colors and sharpness.
struct VisualTreatment: ViewModifier {
    let opacity: Double
    func body(content: Content) -> some View {
        content.compositingGroup().opacity(opacity)
    }
}
