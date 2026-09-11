import SwiftUI

@main
struct GloWalkApp: App {
    @ObservedObject private var persistenceController = PersistenceController.shared

    init() {
        PersistenceController.shared.recoverInterruptedWalks()
        // Use the bundled handwriting family for all navigation bar titles
        // (Klee One in Japanese, LXGW WenKai KR in Korean, WenKai otherwise).
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.black
        appearance.titleTextAttributes = [
            .font: GloUIFont.headline(17),
            .foregroundColor: UIColor.white
        ]
        appearance.largeTitleTextAttributes = [
            .font: GloUIFont.headline(34),
            .foregroundColor: UIColor.white
        ]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if persistenceController.loadFailed {
                    VStack(spacing: 20) {
                        Text("storage.unavailable")
                        Text("storage.preserved").font(.body)
                        Button("storage.retry") {
                            persistenceController.loadStores()
                            persistenceController.recoverInterruptedWalks()
                        }
                    }.padding().preferredColorScheme(.dark)
                } else {
                    ContentView()
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                }
            }
        }
    }
}
