import SwiftUI
import Photos

struct HistoryListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \WalkSession.startTime, ascending: false)],
        predicate: NSPredicate(format: "endType != %@ AND totalSteps > 0 AND totalDistance > 0", "abandoned"),
        animation: .default
    ) private var sessions: FetchedResults<WalkSession>
    /// True while a walk is in progress — shows the "Resume Walk" banner and
    /// hides "New Walk" so peeking at history keeps the current walk alive.
    let hasActiveWalk: Bool
    /// Return to the in-progress walk (HUD) without starting a new one.
    let onResume: () -> Void
    /// Start a fresh walk (fresh HUD view model) after the current one ends.
    let onNewWalk: () -> Void
    @State private var selectedSession: WalkSession?
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color.gloBlackSurface.ignoresSafeArea()

            VStack(spacing: 0) {
                // While a walk is in progress, give a prominent way back to it.
                if hasActiveWalk {
                    resumeBanner
                }

                if sessions.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .gesture(DragGesture(minimumDistance: 60, coordinateSpace: .local)
                            .onEnded { v in if v.translation.height > 60 { onNewWalk() } })
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
                            Text(L10n.historyTitle)
                                .font(.gloHeadline(17))
                                .foregroundColor(.gloGold)
                            Spacer()
                            // "New Walk" only when no walk is in progress — while a
                            // walk is active the resume banner is the primary action.
                            if !hasActiveWalk {
                                Button(L10n.historyNewWalk) { onNewWalk() }
                                    .font(.gloBody(14))
                                    .foregroundColor(.gloGold)
                            }
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
                                                Text("🦶\(session.totalSteps)\(L10n.historyUnitSteps)")
                                                    .font(.gloBody(12))
                                                Text("📏\(String(format: "%.0f", session.totalDistance))\(L10n.historyUnitMeters)")
                                                    .font(.gloBody(12))
                                                if let end = session.endTime {
                                                    let min = Int(end.timeIntervalSince(session.wrappedStartTime) / 60)
                                                    Text("⏱\(min)\(L10n.historyUnitMinutes)").font(.gloBody(12))
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
                        .refreshable { onNewWalk() }
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(item: $selectedSession) { session in
            HistoryPosterView(session: session)
        }
    }

    /// Prominent entry back to the in-progress walk (torch stays on, recording
    /// continues) — this is the primary action while a walk is active.
    private var resumeBanner: some View {
        Button(action: onResume) {
            HStack(spacing: 8) {
                Image(systemName: "figure.walk")
                Text(L10n.historyResumeWalk)
                    .font(.gloBody(15))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12))
            }
            .foregroundColor(.black)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.gloGold)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 48)).foregroundColor(.gloGold)
            Text(L10n.historyEmpty)
                .font(.gloHeadline(18)).foregroundColor(.white)
            VStack(spacing: 8) {
                Text(L10n.historyEmptyHint1)
                Text(L10n.historyEmptyHint2)
                Text(L10n.historyEmptyHint3)
            }
            .font(.gloBody(14)).foregroundColor(.white.opacity(0.5))

            HStack(spacing: 24) {
                Button(action: { showSettings = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                        Text(L10n.settingsTitle)
                    }
                    .font(.gloBody(14)).foregroundColor(.gloGold)
                }
                Button(L10n.historyStartWalk) {
                    onNewWalk()
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
                            if v.translation.height > 60 { dismiss() }
                        })
                    VStack {
                        Spacer()
                        HStack(spacing: 10) {
                            HUDButton(icon: "square.and.arrow.up", label: L10n.posterShare,
                                      bg: Color.gloGold, fg: .black) { showShareSheet = true }
                            HUDButton(icon: savedToPhotos ? "checkmark" : "square.and.arrow.down",
                                      label: savedToPhotos ? L10n.posterSaved : L10n.posterSave,
                                      bg: .clear, fg: .gloGold, border: true) {
                                guard let img = posterImage else { return }
                                PHPhotoLibrary.shared().performChanges({
                                    PHAssetChangeRequest.creationRequestForAsset(from: img)
                                }) { success, _ in
                                    DispatchQueue.main.async {
                                        if success { savedToPhotos = true; Haptic.medium() }
                                    }
                                }
                            }
                            HUDButton(icon: "checkmark", label: L10n.posterDone,
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
            posterImage = await PosterGenerator.generate(session: session)
        }
    }
}
