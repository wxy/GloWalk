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
                                        if session.healthSyncState == HealthSyncState.synced.rawValue {
                                            Image(systemName: "star.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(.red)
                                        }
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
            HistoryPosterView(
                sessions: Array(sessions),
                initialIndex: sessions.firstIndex(where: { $0.objectID == session.objectID }) ?? 0
            )
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
    /// All history records, newest first (same order as the list) — the poster
    /// drags left/right through them like a photo album.
    let sessions: [WalkSession]
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    /// Generated posters for the current record and its neighbours — keyed by
    /// session index, capped to [index-1, index+1] so memory stays bounded.
    @State private var posters: [Int: UIImage] = [:]
    /// Follows the finger while dragging; springs back or slides the page out
    /// on release.
    @State private var dragOffset: CGFloat = 0
    /// True while the slide-out/slide-in animation is running.
    @State private var isSwitching = false
    @State private var showShareSheet = false
    @State private var savedToPhotos = false

    private var screenWidth: CGFloat { UIScreen.main.bounds.width }
    /// Magnetic start: the first ~14pt of a drag move damped (×0.35), so the
    /// page feels "stuck" to the screen edge and only unsticks once the finger
    /// pulls past it.
    private let snapStartDistance: CGFloat = 14
    private let snapStartDamping: CGFloat = 0.35

    init(sessions: [WalkSession], initialIndex: Int) {
        self.sessions = sessions
        _index = State(initialValue: min(max(initialIndex, 0), max(sessions.count - 1, 0)))
    }

    var body: some View {
        ZStack {
            Color.gloBlack.ignoresSafeArea()

            if let current = posters[index] {
                ZStack {
                    // Previous page peeking in from the left while dragging.
                    if let prev = posters[index - 1] {
                        Image(uiImage: prev).resizable().scaledToFill().ignoresSafeArea()
                            .offset(x: dragOffset - screenWidth)
                    }
                    // Next page peeking in from the right.
                    if let next = posters[index + 1] {
                        Image(uiImage: next).resizable().scaledToFill().ignoresSafeArea()
                            .offset(x: dragOffset + screenWidth)
                    }
                    // The page being dragged.
                    Image(uiImage: current).resizable().scaledToFill().ignoresSafeArea()
                        .offset(x: dragOffset)
                }
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { v in
                            guard !isSwitching else { return }
                            let raw = v.translation.width
                            let sign: CGFloat = raw >= 0 ? 1 : -1
                            // Snap-start: damped until the unstick distance,
                            // then 1:1 tracking. Haptic when it unsticks.
                            if abs(raw) <= snapStartDistance {
                                dragOffset = raw * snapStartDamping
                            } else {
                                if abs(dragOffset) < snapStartDistance * snapStartDamping {
                                    Haptic.light()
                                }
                                dragOffset = snapStartDistance * snapStartDamping * sign
                                    + (raw - snapStartDistance * sign)
                            }
                        }
                        .onEnded(handleDrag)
                )

                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        HUDButton(icon: "square.and.arrow.up", label: L10n.posterShare,
                                  bg: Color.gloGold, fg: .black) { showShareSheet = true }
                        HUDButton(icon: savedToPhotos ? "checkmark" : "square.and.arrow.down",
                                  label: savedToPhotos ? L10n.posterSaved : L10n.posterSave,
                                  bg: .clear, fg: .gloGold, border: true) {
                            guard let img = posters[index] else { return }
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
            } else {
                ProgressView().tint(.gloGold)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let img = posters[index] { ShareSheet(items: [img]) }
        }
        .task(id: index) {
            await loadPoster(for: index)
            if index > 0 { await loadPoster(for: index - 1) }
            if index + 1 < sessions.count { await loadPoster(for: index + 1) }
        }
    }

    /// Generate (or reuse) the poster for the session at `i`.
    private func loadPoster(for i: Int) async {
        guard posters[i] == nil else { return }
        posters[i] = await PosterGenerator.generate(session: sessions[i])
    }

    /// Decide where the finger-release should land: down dismisses, a big
    /// horizontal swipe slides to the next/previous record, anything else
    /// springs the page back.
    private func handleDrag(_ v: DragGesture.Value) {
        let w = v.translation.width
        if v.translation.height > 60 {
            dismiss()
            return
        }
        if w < -80, index + 1 < sessions.count {
            slide(to: index + 1)
        } else if w > 80, index > 0 {
            slide(to: index - 1)
        } else {
            withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.86)) {
                dragOffset = 0
            }
            Haptic.selection()
        }
    }

    /// Slide the current page out in the drag direction and swap the index.
    /// The new page has already slid in to its resting position during the
    /// drag/slide-out, so we land it exactly at 0 — no re-slide, no reload.
    private func slide(to newIndex: Int) {
        isSwitching = true
        let direction: CGFloat = newIndex > index ? -1 : 1
        withAnimation(.easeOut(duration: 0.18)) {
            dragOffset = direction * screenWidth
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            savedToPhotos = false
            index = newIndex
            // Keep only the pages we can still reach, so memory stays bounded.
            posters = posters.filter { abs($0.key - newIndex) <= 1 }
            dragOffset = 0
            isSwitching = false
            Haptic.medium()
        }
    }
}
