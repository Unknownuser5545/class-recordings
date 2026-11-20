import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        Downloader.shared.backgroundCompletion = completionHandler
        Downloader.shared.wake()
    }
}

@main
struct ZainabRecordingsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var library = Library.shared
    @StateObject private var player = Player.shared
    @Environment(\.scenePhase) private var phase

    init() {
        Downloader.shared.wake()
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Theme.bg)
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: UIColor(Theme.text)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.text)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(player)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task { await library.refresh(); await Downloader.shared.syncStates() }
                .onChange(of: phase) { _, p in
                    if p == .active { Task { await library.refresh() } }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var player: Player
    var body: some View {
        NavigationStack {
            HomeView()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if player.current != nil { PlayerBar() }
        }
    }
}
