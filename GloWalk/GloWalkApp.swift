import SwiftUI

@main
struct GloWalkApp: App {
    let persistenceController = PersistenceController.shared

    init() {
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
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
