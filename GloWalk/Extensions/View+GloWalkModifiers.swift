import SwiftUI

struct GloWalkHUDModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.gloBlack)
            .preferredColorScheme(.dark)
            .statusBar(hidden: true)
    }
}

extension View {
    func gloWalkHUD() -> some View {
        modifier(GloWalkHUDModifier())
    }
}
