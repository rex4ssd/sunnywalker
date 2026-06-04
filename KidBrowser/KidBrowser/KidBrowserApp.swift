import SwiftUI

@main
struct KidBrowserApp: App {
    @StateObject private var store = SiteStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
        }
    }
}
