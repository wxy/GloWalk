import SwiftUI

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
                            if v.translation.height > 40 || v.translation.width > 40 {
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
            posterImage = try await PosterGenerator.generate(session: session)
            if let data = posterImage?.jpegData(compressionQuality: 0.85) {
                session.posterImageData = data; PersistenceController.shared.save()
            }
        } catch { print("Poster error: \(error)") }
        isGenerating = false
    }

    private func saveToPhotos() {
        guard let image = posterImage else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        savedToPhotos = true
        Haptic.medium()
    }
}
