import SwiftUI

/// A quiet collection of the exact keepsake lines that have appeared on the
/// user's posters. It is derived from completed walks and stores no new route
/// or location information.
struct NightMemoryCollectionView: View {
    let sessions: [WalkSession]
    @Environment(\.dismiss) private var dismiss
    @State private var firstPosterSession: WalkSession?

    static var localizedTitle: String { Copy.current.title }
    static var localizedNewImprint: String {
        switch L10n.languageCode {
        case "zh-Hant": return "新印記"
        case "ja": return "新しいしるし"
        case "ko": return "새 밤길의 흔적"
        case "fr": return "Nouvelle empreinte"
        case "de": return "Neue Nachtspur"
        case "es": return "Nueva huella"
        case "pt-BR": return "Nova marca"
        case "it": return "Nuova traccia"
        case "ru": return "Новый след"
        case "zh-Hans": return "新印记"
        default: return "New Imprint"
        }
    }

    private let themes: [(key: String, symbol: String)] = [
        ("tagline.rain", "cloud.rain.fill"),
        ("tagline.resumed", "play.fill"),
        ("tagline.streetlight", "circle.lefthalf.filled"),
        ("tagline.winding", "point.topleft.down.to.point.bottomright.curvepath"),
        ("tagline.adaptation", "figure.walk.motion"),
        ("tagline.moon", "moon.stars.fill"),
        ("tagline.quiet", "sparkles")
    ]

    private var copy: Copy { Copy.current }
    private var allMemories: [TaglineItem] { Tagline.nightMemoryPool }
    private var unlockedKeys: Set<String> {
        Set(sessions.compactMap(\.memoryTaglineKey))
    }
    private var knownUnlockedKeys: Set<String> {
        unlockedKeys.intersection(Set(allMemories.map(\.key)))
    }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 3)
    }

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.18, green: 0.16, blue: 0.11),
                        Color(red: 0.12, green: 0.12, blue: 0.12),
                        Color.gloBlackSurface
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        progressHeader
                        LazyVStack(spacing: 22) {
                            ForEach(Array(themes.enumerated()), id: \.element.key) { index, theme in
                                themeSection(theme, title: copy.themeTitles[index])
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle(copy.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(copy.done) { dismiss() }
                        .font(.gloBody(14))
                        .foregroundColor(.gloGold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { NightMemoryDiscovery.markSeen() }
        .fullScreenCover(item: $firstPosterSession) { session in
            HistoryPosterView(sessions: [session], initialIndex: 0)
        }
    }

    private var progressHeader: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: allMemories.isEmpty ? 0 : CGFloat(knownUnlockedKeys.count) / CGFloat(allMemories.count))
                    .stroke(Color.gloGold, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text("\(knownUnlockedKeys.count)")
                        .font(.gloHeadline(28))
                        .foregroundColor(.gloGold)
                    Text("/ \(allMemories.count)")
                        .font(.gloBody(11))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
            .frame(width: 92, height: 92)

            Text(copy.subtitle)
                .font(.gloBody(13))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func themeSection(_ theme: (key: String, symbol: String), title: String) -> some View {
        let memories = allMemories
            .filter { $0.key == theme.key || $0.key.hasPrefix(theme.key + ".") }
            .sorted { variantRank($0.key) < variantRank($1.key) }
        let unlockedCount = memories.filter { knownUnlockedKeys.contains($0.key) }.count

        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Image(systemName: theme.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(unlockedCount > 0 ? .gloGold : .white.opacity(0.48))
                    .frame(width: 22)
                Text(title)
                    .font(.gloHeadline(15))
                    .foregroundColor(.white.opacity(unlockedCount > 0 ? 0.95 : 0.68))
                Spacer()
                Text("\(unlockedCount) / \(memories.count)")
                    .font(.gloBody(11))
                    .foregroundColor(.white.opacity(0.3))
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(memories) { memory in
                    memoryCard(memory)
                }
            }
        }
    }

    private func memoryCard(_ memory: TaglineItem) -> some View {
        let matching = sessions
            .filter { $0.memoryTaglineKey == memory.key }
            .sorted { $0.wrappedStartTime < $1.wrappedStartTime }
        let first = matching.first
        let isUnlocked = first != nil

        return Button {
            if let first {
                Haptic.selection()
                firstPosterSession = first
            }
        } label: {
            Group {
                if let first {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Image(systemName: "sparkle")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.gloGold)
                            Spacer(minLength: 2)
                            Text("×\(matching.count)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(.gloGold.opacity(0.9))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.gloGold.opacity(0.13)))
                        }

                        Spacer(minLength: 10)

                        Text("\u{201C}\(memory.localizedPhrase)\u{201D}")
                            .font(.gloBody(13))
                            .foregroundColor(.gloGold)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Spacer(minLength: 10)

                        Text(first.wrappedStartTime, format: .dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute())
                            .font(.system(size: 10, weight: .regular, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.68))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                } else {
                    VStack(spacing: 9) {
                        Spacer(minLength: 0)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.white.opacity(0.06)))
                        Text(copy.locked)
                            .font(.gloBody(11))
                            .multilineTextAlignment(.center)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white.opacity(0.48))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(isUnlocked
                        ? Color(red: 0.16, green: 0.14, blue: 0.09)
                        : Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(isUnlocked ? Color.gloGold.opacity(0.3) : Color.white.opacity(0.13), lineWidth: 1)
                    )
            )
            .overlay {
                if isUnlocked {
                    LinearGradient(
                        colors: [Color.gloGold.opacity(0.08), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .allowsHitTesting(false)
                }
            }
            .shadow(color: isUnlocked ? Color.gloGold.opacity(0.1) : .clear,
                    radius: 12, y: 5)
        }
        .buttonStyle(ImprintCardButtonStyle())
        .disabled(!isUnlocked)
        .accessibilityLabel(isUnlocked
            ? Text(verbatim: "\(memory.localizedPhrase), \(copy.firstSeen), \(matching.count)")
            : Text(verbatim: copy.locked))
    }

    private func variantRank(_ key: String) -> Int {
        Int(key.split(separator: ".").last ?? "1") ?? 1
    }
}

private struct ImprintCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? 0.05 : 0)
            .animation(.interactiveSpring(response: 0.25, dampingFraction: 1),
                       value: configuration.isPressed)
    }
}

private extension NightMemoryCollectionView {
    struct Copy {
        let title: String
        let subtitle: String
        let locked: String
        let firstSeen: String
        let done: String
        let themeTitles: [String]

        static var current: Copy {
            switch L10n.languageCode {
            case "zh-Hant": return .init(title: "夜行印記", subtitle: "你走過的夜，正在一頁頁亮起", locked: "尚未遇見", firstSeen: "首次獲得", done: "完成", themeTitles: ["雨落在路上", "再次出發", "光影流轉", "路有轉折", "走得更遠", "月光同行", "靜靜走過"])
            case "ja": return .init(title: "夜のしるし", subtitle: "歩いた夜が、一頁ずつ灯っていく", locked: "まだ出会っていません", firstSeen: "最初の獲得", done: "完了", themeTitles: ["雨の道", "もう一度歩く", "移ろう光", "曲がる道", "遠くまで", "月と歩く", "静かな歩み"])
            case "ko": return .init(title: "밤길의 흔적", subtitle: "걸어온 밤이 한 장씩 빛납니다", locked: "아직 만나지 못함", firstSeen: "처음 획득", done: "완료", themeTitles: ["비 내리는 길", "다시 걷기", "흐르는 빛", "굽이진 길", "더 멀리", "달빛과 함께", "고요한 걸음"])
            case "fr": return .init(title: "Empreintes nocturnes", subtitle: "Les nuits parcourues s'éclairent une page après l'autre", locked: "Pas encore rencontrée", firstSeen: "Première rencontre", done: "Terminé", themeTitles: ["Sous la pluie", "Reprendre la marche", "Lumière changeante", "Chemins sinueux", "Marcher plus loin", "Avec la lune", "Marche silencieuse"])
            case "de": return .init(title: "Nachtspuren", subtitle: "Die Nächte deiner Wege leuchten Seite für Seite auf", locked: "Noch nicht begegnet", firstSeen: "Zuerst erhalten", done: "Fertig", themeTitles: ["Regen auf dem Weg", "Weitergehen", "Wechselndes Licht", "Kurvige Wege", "Weiter hinaus", "Mit dem Mond", "Stiller Weg"])
            case "es": return .init(title: "Huellas nocturnas", subtitle: "Las noches que caminaste se iluminan página a página", locked: "Aún no encontrada", firstSeen: "Primera vez", done: "Listo", themeTitles: ["Bajo la lluvia", "Volver a caminar", "Luz cambiante", "Caminos con giros", "Caminar más lejos", "Con la luna", "Paseo silencioso"])
            case "pt-BR": return .init(title: "Marcas da noite", subtitle: "As noites que você caminhou se acendem página a página", locked: "Ainda não encontrada", firstSeen: "Primeira vez", done: "Concluído", themeTitles: ["Sob a chuva", "Voltar a caminhar", "Luz em mudança", "Caminhos sinuosos", "Caminhar mais longe", "Com a lua", "Caminhada tranquila"])
            case "it": return .init(title: "Tracce notturne", subtitle: "Le notti percorse si accendono una pagina alla volta", locked: "Non ancora incontrata", firstSeen: "Prima volta", done: "Fine", themeTitles: ["Sotto la pioggia", "Riprendere il cammino", "Luce mutevole", "Sentieri tortuosi", "Camminare più lontano", "Con la luna", "Cammino silenzioso"])
            case "ru": return .init(title: "Следы ночи", subtitle: "Пройденные ночи загораются страница за страницей", locked: "Пока не встречено", firstSeen: "Впервые получено", done: "Готово", themeTitles: ["Под дождём", "Снова в путь", "Меняющийся свет", "Извилистый путь", "Дальше вперёд", "Вместе с луной", "Тихая прогулка"])
            case "zh-Hans": return .init(title: "夜行印记", subtitle: "你走过的夜，正在一页页亮起", locked: "尚未遇见", firstSeen: "首次获得", done: "完成", themeTitles: ["雨落在路上", "再次出发", "光影流转", "路有转折", "走得更远", "月光同行", "静静走过"])
            default: return .init(title: "Night Imprints", subtitle: "The nights you walked are lighting up, one page at a time", locked: "Not encountered yet", firstSeen: "First found", done: "Done", themeTitles: ["Rain on the road", "Setting out again", "Shifting light", "Turning paths", "Walking farther", "With the moon", "A quiet walk"])
            }
        }
    }
}
