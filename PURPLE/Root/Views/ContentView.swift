import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()
    @State private var selectedSidebarItem: SidebarItem? = .consolidate
    
    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedSidebarItem)
        } detail: {
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .ignoresSafeArea()
                
                switch selectedSidebarItem {
                case .consolidate:
                    ConsolidateView(appState: appState)
                case .compress:
                    CompressView()
                case .settings:
                    Text("Settings View")
                case .history:
                    Text("History View")
                case .none:
                    Text("Select an item from the sidebar")
                }
            }
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }
    
    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}

#Preview {
    ContentView()
}
