import SwiftUI
import Photos

struct ArrivalSummaryView: View {
    @ObservedObject var viewModel: HUDViewModel
    let onComplete: () -> Void
    @State private var posterImage: UIImage?
    @State private var isGenerating = true
    @State private var showShareSheet = false
    @State private var savedToPhotos = false

    var body: some View {
        ZStack {
            Color.gloBlack.ignoresSafeArea()

            if isGenerating {
                VStack(spacing: 16) {
                    ProgressView().tint(.gloGold).scaleEffect(1.5)
                    Text(L10n.hudDrawing)
                        .font(.gloBody(14)).foregroundColor(.gloGold.opacity(0.6))
                }
            } else if let poster = posterImage {
                ZStack {
                    Image(uiImage: poster)
                        .resizable().scaledToFill()
                        .ignoresSafeArea()
                        .gesture(DragGesture(minimumDistance: 40).onEnded { v in
                            if v.translation.height > 60 {
                                viewModel.showArrivalSummary = false
                                onComplete()
                            }
                        })

                    VStack {
                        Spacer()
                        HStack(spacing: 10) {
                            HUDButton(icon: "square.and.arrow.up", label: L10n.posterShare,
                                      bg: Color.gloGold, fg: .black) { showShareSheet = true }
                            HUDButton(icon: savedToPhotos ? "checkmark" : "square.and.arrow.down",
                                      label: savedToPhotos ? L10n.posterSaved : L10n.posterSave,
                                      bg: .clear, fg: .gloGold, border: true, action: saveToPhotos)
                            HUDButton(icon: "checkmark", label: L10n.posterDone,
                                      bg: .clear, fg: .white.opacity(0.6), border: true) {
                                viewModel.showArrivalSummary = false
                                onComplete()
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                }
                .sheet(isPresented: $showShareSheet) { ShareSheet(items: [poster]) }
            } else {
                VStack(spacing: 16) {
                    Text(L10n.posterGenerateFailed).foregroundColor(.white)
                    Button(L10n.posterClose) { viewModel.showArrivalSummary = false }.foregroundColor(.gloGold)
                }
            }
        }
        .task { await generatePoster() }
    }

    private func generatePoster() async {
        guard let session = viewModel.currentWalkSession else { isGenerating = false; return }
        do {
            var image = try await PosterGenerator.generate(session: session)
            // Scale down to max 1200px before storing to save Core Data space
            image = image.scaledToMaxDimension(1200)
            posterImage = image
            if let data = image.jpegData(compressionQuality: 0.85) {
                session.posterImageData = data; PersistenceController.shared.save()
            }
        } catch { print("Poster error: \(error)") }
        isGenerating = false
    }

    private func saveToPhotos() {
        guard let image = posterImage else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { success, _ in
            DispatchQueue.main.async {
                if success { self.savedToPhotos = true; Haptic.medium() }
            }
        }
    }
}

extension UIImage {
    func scaledToMaxDimension(_ maxDim: CGFloat) -> UIImage {
        let scale = min(maxDim / size.width, maxDim / size.height, 1.0)
        guard scale < 1.0 else { return self }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in self.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
