import SwiftUI

struct HistoryListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \WalkSession.startTime, ascending: false)],
        animation: .default
    ) private var sessions: FetchedResults<WalkSession>
    let goToSplash: () -> Void
    @State private var selectedSession: WalkSession?
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color.gloBlackSurface.ignoresSafeArea()

            if sessions.isEmpty {
                emptyState
                    .gesture(DragGesture(minimumDistance: 60, coordinateSpace: .local)
                        .onEnded { v in if v.translation.height > 60 { goToSplash() } })
            } else {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 16))
                                .foregroundColor(.gloGold.opacity(0.4))
                        }
                        Spacer()
                        Text("步行记录")
                            .font(.gloHeadline(17))
                            .foregroundColor(.gloGold)
                        Spacer()
                        Button("新步行") { goToSplash() }
                            .font(.gloBody(14))
                            .foregroundColor(.gloGold)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                    // List
                    List {
                        ForEach(sessions, id: \.objectID) { session in
                            Button(action: { selectedSession = session }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text(session.wrappedStartTime, style: .date)
                                                .font(.gloBody(14)).foregroundColor(.white)
                                            Text(session.wrappedStartTime, style: .time)
                                                .font(.gloBody(13)).foregroundColor(.white.opacity(0.4))
                                        }
                                        HStack(spacing: 10) {
                                            Text("🦶\(session.totalSteps)步").font(.gloBody(12))
                                            Text("📏\(String(format: "%.0f", session.totalDistance))m").font(.gloBody(12))
                                            if let end = session.endTime {
                                                let min = Int(end.timeIntervalSince(session.wrappedStartTime) / 60)
                                                Text("⏱\(min)min").font(.gloBody(12))
                                            }
                                        }
                                        .foregroundColor(.white.opacity(0.4))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10)).foregroundColor(.white.opacity(0.2))
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 20)
                            }
                            .listRowBackground(Color.gloBlackSurface)
                            .listRowInsets(EdgeInsets())
                        }
                        .onDelete(perform: deleteSessions)
                    }
                    .listStyle(.plain)
                    .refreshable { goToSplash() }
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(item: $selectedSession) { session in
            HistoryPosterView(session: session)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 48)).foregroundColor(.gloGold)
            Text("还没有夜路记录")
                .font(.gloHeadline(18)).foregroundColor(.white)
            VStack(spacing: 8) {
                Text("打开 GloWalk 开始一次夜间步行")
                Text("走完后轻点中央圆环熄灭灯笼")
                Text("即可生成你的第一张夜路海报")
            }
            .font(.gloBody(14)).foregroundColor(.white.opacity(0.5))

            HStack(spacing: 24) {
                Button(action: { showSettings = true }) {
                    Label("设置", systemImage: "gearshape")
                        .font(.gloBody(14)).foregroundColor(.gloGold)
                }
                Button("开始步行") {
                    goToSplash()
                }
                .font(.gloHeadline(16)).foregroundColor(.black)
                .padding(.horizontal, 28).padding(.vertical, 10)
                .background(Color.gloGold).cornerRadius(20)
            }
            .padding(.top, 8)
        }
    }

    private func deleteSessions(offsets: IndexSet) {
        offsets.map { sessions[$0] }.forEach(viewContext.delete)
        PersistenceController.shared.save()
    }
}

// MARK: - History Poster

struct HistoryPosterView: View {
    let session: WalkSession
    @Environment(\.dismiss) private var dismiss
    @State private var posterImage: UIImage?
    @State private var showShareSheet = false
    @State private var savedToPhotos = false

    var body: some View {
        ZStack {
            Color.gloBlack.ignoresSafeArea()
            if let poster = posterImage {
                ZStack {
                    Image(uiImage: poster).resizable().scaledToFill().ignoresSafeArea()
                        .gesture(DragGesture(minimumDistance: 40).onEnded { v in
                            if v.translation.height > 40 || v.translation.width > 40 { dismiss() }
                        })
                    VStack {
                        Spacer()
                        HStack(spacing: 10) {
                            HUDButton(icon: "square.and.arrow.up", label: "分享",
                                      bg: Color.gloGold, fg: .black) { showShareSheet = true }
                            HUDButton(icon: savedToPhotos ? "checkmark" : "square.and.arrow.down",
                                      label: savedToPhotos ? "已保存" : "保存",
                                      bg: .clear, fg: .gloGold, border: true) {
                                guard let img = posterImage else { return }
                                UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                                savedToPhotos = true; Haptic.medium()
                            }
                            HUDButton(icon: "checkmark", label: "完成",
                                      bg: .clear, fg: .white.opacity(0.6), border: true) { dismiss() }
                        }
                        .padding(.horizontal, 20).padding(.bottom, 24)
                    }
                }
                .sheet(isPresented: $showShareSheet) { ShareSheet(items: [poster]) }
            } else {
                ProgressView().tint(.gloGold)
            }
        }
        .task {
            do { posterImage = try await PosterGenerator.generate(session: session) }
            catch { print("History poster error: \(error)") }
        }
    }
}
