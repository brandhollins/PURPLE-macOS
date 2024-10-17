import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    
    var body: some View {
        List(selection: $selection) {
            NavigationLink(value: SidebarItem.consolidate) {
                Label("Consolidate", systemImage: "folder")
            }
            NavigationLink(value: SidebarItem.compress) {
                Label("Compress", systemImage: "archivebox")
            }
            NavigationLink(value: SidebarItem.settings) {
                Label("Settings", systemImage: "gear")
            }
            NavigationLink(value: SidebarItem.history) {
                Label("History", systemImage: "clock")
            }
        }
    }
}

enum SidebarItem: String, Identifiable, CaseIterable {
    case consolidate, compress, settings, history
    var id: String { self.rawValue }
}

#Preview {
    SidebarView(selection: .constant(.consolidate))
}
