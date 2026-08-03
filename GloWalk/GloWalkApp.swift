import SwiftUI

@main
struct GloWalkApp: App {
    let persistenceController = PersistenceController.shared

    init() {
        // Use LXGW WenKai for all navigation bar titles
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.black
        appearance.titleTextAttributes = [
            .font: UIFont(name: "LXGW WenKai Medium", size: 17)
                ?? UIFont.systemFont(ofSize: 17, weight: .medium),
            .foregroundColor: UIColor.white
        ]
        appearance.largeTitleTextAttributes = [
            .font: UIFont(name: "LXGW WenKai Medium", size: 34)
                ?? UIFont.systemFont(ofSize: 34, weight: .medium),
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
