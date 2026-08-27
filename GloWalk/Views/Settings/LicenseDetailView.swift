import SwiftUI

/// Displays a bundled open-source license text (SIL OFL) for a font.
struct LicenseDetailView: View {
    let title: String
    let fileName: String

    var body: some View {
        ZStack {
            Color.gloBlackSurface.ignoresSafeArea()
            ScrollView {
                if let text = licenseText {
                    Text(text)
                        .font(.gloBody(11))
                        .foregroundColor(.white.opacity(0.6))
                        .textSelection(.enabled)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(L10n.licenseUnavailable)
                        .font(.gloBody(12))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(20)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var licenseText: String? {
        // The synchronized folder flattens Resources into the bundle root;
        // check the Licenses/ subdirectory too for non-flattened layouts.
        if let url = Bundle.main.url(forResource: fileName, withExtension: "txt") {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        if let url = Bundle.main.url(forResource: fileName, withExtension: "txt",
                                     subdirectory: "Licenses") {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        return nil
    }
}
