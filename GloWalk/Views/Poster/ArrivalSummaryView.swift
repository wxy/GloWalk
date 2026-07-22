import SwiftUI

struct ArrivalSummaryView: View {
    @ObservedObject var viewModel: HUDViewModel
    @EnvironmentObject var appState: AppState
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
                    Text("正在绘制你的夜路足迹...")
                        .font(.gloBody(14)).foregroundColor(.gloGold.opacity(0.6))
                }
            } else if let poster = posterImage {
                ZStack {
                    Image(uiImage: poster)
                        .resizable().scaledToFill()
                        .ignoresSafeArea()

                    VStack {
                        Spacer()
                        HStack(spacing: 10) {
                            miniButton("square.and.arrow.up", "分享",
                                       Color.gloGold, .black) { showShareSheet = true }
                            miniButton(savedToPhotos ? "checkmark" : "square.and.arrow.down",
                                       savedToPhotos ? "已保存" : "保存",
                                       .clear, .gloGold, border: true, action: saveToPhotos)
                            miniButton("checkmark", "完成",
                                       .clear, .white.opacity(0.6), border: true) {
                                viewModel.showArrivalSummary = false
                                appState.resetHUD = true
                                appState.showHistory = true
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 80)
                    }
                }
                .sheet(isPresented: $showShareSheet) { ShareSheet(items: [poster]) }
            } else {
                VStack(spacing: 16) {
                    Text("海报生成失败").foregroundColor(.white)
                    Button("关闭") { viewModel.showArrivalSummary = false }.foregroundColor(.gloGold)
                }
            }
        }
        .task { await generatePoster() }
    }

    private func miniButton(_ icon: String, _ label: String, _ bg: Color, _ fg: Color,
                            border: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.gloBody(15))
                Text(label).font(.gloBody(10))
            }
            .foregroundColor(fg)
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(bg)
            .cornerRadius(10)
            .overlay(border ? RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gloGold, lineWidth: 1) : nil)
        }
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
    }
}
