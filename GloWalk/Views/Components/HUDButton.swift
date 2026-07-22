import SwiftUI

struct HUDButton: View {
    let icon: String
    let label: LocalizedStringKey
    let bg: Color
    let fg: Color
    var border: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 15))
                Text(label).font(.gloBody(10))
            }
            .foregroundColor(fg)
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(bg)
            .cornerRadius(10)
            .overlay(border ? RoundedRectangle(cornerRadius: 10)
                .stroke(fg, lineWidth: 1) : nil)
        }
    }
}
