import SwiftUI

/// Muted sage tones share the background's hue; brightness establishes a quiet hierarchy.
struct BreakPalette {
    let scrim = Color(red: 0.045, green: 0.10, blue: 0.08)
    let message = Color(red: 0.70, green: 0.77, blue: 0.73)
    let time = Color(red: 0.63, green: 0.72, blue: 0.67)
    let secondary = Color(red: 0.60, green: 0.69, blue: 0.64)
}

/// Background and artwork fade together; controls remain readable at full transparency.
struct VisualTreatment: ViewModifier {
    let transparency: Double
    func body(content: Content) -> some View {
        content.compositingGroup().opacity(1 - transparency)
    }
}
