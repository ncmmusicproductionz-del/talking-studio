import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var model = StudioModel()
    @State private var tab = 0

    init() {
        let tabs = UITabBarAppearance()
        tabs.configureWithTransparentBackground()
        tabs.backgroundEffect = UIBlurEffect(style: .systemChromeMaterialDark)
        tabs.backgroundColor = UIColor(red: 7 / 255, green: 11 / 255, blue: 26 / 255, alpha: 0.55)
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
    }

    var body: some View {
        TabView(selection: $tab) {
            CreateView()
                .tabItem { Label("Create", systemImage: "wand.and.stars") }
                .tag(0)
            LibraryView(onCreate: { tab = 0 })
                .tabItem { Label("My Videos", systemImage: "film.stack") }
                .tag(1)
        }
        .environmentObject(model)
        .tint(Theme.blue)
        .fullScreenCover(isPresented: $model.busy) {
            RunningView().environmentObject(model)
        }
        .sheet(isPresented: $model.showResult) {
            ResultView().environmentObject(model)
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView().environmentObject(model)
        }
    }
}
