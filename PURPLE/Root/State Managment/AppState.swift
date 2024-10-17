import SwiftUI

class AppState: ObservableObject {
    @Published var sourceFolders: [FolderInfo] = []
    @Published var destinationURL: URL?
    @Published var isWorking = false
    @Published var statusMessage = ""
    @Published var progress: Float = 0
    @Published var newFolderName = "Consolidated Midjourney"
    @Published var deleteOriginals = false
    @Published var totalSourceSize: Int64 = 0
    @Published var consolidatedSize: Int64 = 0
}
