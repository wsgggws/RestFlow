import SwiftUI

/// Apply equally to built-in drawings and imported media, leaving text untouched.
struct VisualTreatment: ViewModifier {
    let grayness: Double
    func body(content: Content) -> some View {
        content
            .compositingGroup()
            .saturation(1 - grayness)
            .blur(radius: grayness * 1.2)
            .opacity(1 - grayness * 0.4)
    }
}
