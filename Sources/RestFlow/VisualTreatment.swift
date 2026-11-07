import SwiftUI

/// Background and artwork fade together; controls remain readable at full transparency.
struct VisualTreatment: ViewModifier {
    let transparency: Double
    func body(content: Content) -> some View {
        content.compositingGroup().opacity(1 - transparency)
    }
}
