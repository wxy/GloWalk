import SwiftUI
import UIKit

struct MoonCornerView: View {
    private var moonImage: UIImage? {
        PosterGenerator.currentMoonImage()
    }

    var body: some View {
        VStack {
            HStack {
                if let img = moonImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .opacity(0.5)
                        .clipShape(Circle())
                        .padding(.leading, 16)
                        .padding(.top, 12)
                }
                Spacer()
            }
            Spacer()
        }
    }
}
