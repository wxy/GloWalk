import SwiftUI

struct HistoryListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \WalkSession.startTime, ascending: false)],
        animation: .default
    ) private var sessions: FetchedResults<WalkSession>

    @State private var showSplash = false
    @State private var selectedSession: WalkSession?

    var body: some View {
        NavigationView {
            ZStack {
                Color.gloBlackSurface.ignoresSafeArea()

                if sessions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "moon.stars.fill")
                            .font(.gloBody(48)).foregroundColor(.gloGold)
                        Text("还没有夜路记录")
                            .font(.gloHeadline(18)).foregroundColor(.white)
                        VStack(spacing: 8) {
                            Text("打开 GloWalk 开始一次夜间步行")
                                .font(.gloBody(14)).foregroundColor(.white.opacity(0.5))
                            Text("走完后轻点中央圆环熄灭灯笼")
                                .font(.gloBody(14)).foregroundColor(.white.opacity(0.5))
                            Text("即可生成你的第一张夜路海报")
                                .font(.gloBody(14)).foregroundColor(.white.opacity(0.5))
                        }
                        Button("开始步行") { showSplash = true }
                            .font(.gloHeadline(16))
                            .foregroundColor(.black)
                            .padding(.horizontal, 32).padding(.vertical, 12)
                            .background(Color.gloGold).cornerRadius(20)
                            .padding(.top, 8)
                    }
                } else {
                    List {
                        ForEach(sessions, id: \.objectID) { session in
                            Button(action: { selectedSession = session }) {
                                HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.wrappedStartTime, style: .date)
                                        .font(.gloHeadline(14)).foregroundColor(.white)
                                    + Text("  ")
                                    + Text(session.wrappedStartTime, style: .time)
                                        .font(.gloBody(14)).foregroundColor(.white.opacity(0.5))

                                    HStack(spacing: 12) {
                                        Text("🦶\(session.totalSteps)步").font(.gloBody(12))
                                        Text("📏\(String(format: "%.0f", session.totalDistance))m").font(.gloBody(12))
                                        if let end = session.endTime {
                                            let min = Int(end.timeIntervalSince(session.wrappedStartTime) / 60)
                                            Text("⏱\(min)min").font(.gloBody(12))
                                        }
                                    }
                                    .foregroundColor(.white.opacity(0.5))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.gloBody(12)).foregroundColor(.white.opacity(0.3))
                            }
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color.gloBlackSurface)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("步行记录")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("新步行") { showSplash = true }
                        .foregroundColor(.gloGold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showSplash) {
            ContentView()
        }
        .fullScreenCover(item: $selectedSession) { session in
            HistoryPosterView(session: session)
        }
    }
}

struct HistoryPosterView: View {
    let session: WalkSession
    @Environment(\.dismiss) private var dismiss
    @State private var posterImage: UIImage?
    @State private var showShareSheet = false

    var body: some View {
        ZStack {
            Color.gloBlack.ignoresSafeArea()
            if let poster = posterImage {
                ZStack {
                    Image(uiImage: poster).resizable().scaledToFill().ignoresSafeArea()
                    VStack {
                        Spacer()
                        HStack(spacing: 10) {
                            Button(action: { showShareSheet = true }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "square.and.arrow.up").font(.gloBody(15))
                                    Text("分享").font(.gloBody(10))
                                }
                                .foregroundColor(.black).frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(Color.gloGold).cornerRadius(10)
                            }
                            Button(action: {
                                guard let img = posterImage else { return }
                                UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "square.and.arrow.down").font(.gloBody(15))
                                    Text("保存").font(.gloBody(10))
                                }
                                .foregroundColor(.gloGold).frame(maxWidth: .infinity).padding(.vertical, 10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gloGold, lineWidth: 1))
                            }
                            Button(action: { dismiss() }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "checkmark").font(.gloBody(15))
                                    Text("完成").font(.gloBody(10))
                                }
                                .foregroundColor(.white.opacity(0.6)).frame(maxWidth: .infinity).padding(.vertical, 10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.3), lineWidth: 1))
                            }
                        }
                        .padding(.horizontal, 20).padding(.bottom, 44)
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
