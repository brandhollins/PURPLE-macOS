import SwiftUI

struct ConsolidateView: View {
    @ObservedObject var appState: AppState
    @StateObject private var folderAccessManager = FolderAccessManager()
    @AppStorage("consolidationHistory") private var consolidationHistory: Data = Data()
    
    var body: some View {
        VStack(spacing: 20) {
            Button("Select Source Folders") {
                let newFolders = selectFolders().map { FolderInfo(url: $0) }
                appState.sourceFolders.append(contentsOf: newFolders)
                updateTotalSourceSize()
            }
            .disabled(appState.isWorking)
            
            if !appState.sourceFolders.isEmpty {
                Text("Total size of selected folders: \(formatFileSize(appState.totalSourceSize))")
            }
            
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                    ForEach(appState.sourceFolders) { folder in
                        FolderView(folder: folder) {
                            appState.sourceFolders.removeAll { $0.id == folder.id }
                            updateTotalSourceSize()
                        }
                    }
                    
                    if let destination = appState.destinationURL {
                        DestinationFolderView(folderName: appState.newFolderName, path: destination.path)
                    }
                }
            }
            .frame(height: 200)
            
            HStack {
                TextField("New Folder Name", text: $appState.newFolderName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button("Select Destination") {
                    appState.destinationURL = selectDestinationFolder()
                }
                .disabled(appState.isWorking)
            }
            
            Toggle("Delete original folders after consolidation", isOn: $appState.deleteOriginals)
            
            Button("Consolidate Folders") {
                consolidateFolders()
            }
            .disabled(appState.isWorking || appState.sourceFolders.isEmpty || appState.destinationURL == nil)
            
            ProgressView(value: appState.progress)
                .opacity(appState.isWorking ? 1 : 0)
            
            if !appState.statusMessage.isEmpty {
                Text(appState.statusMessage)
            }
            
            if appState.consolidatedSize > 0 {
                Text("Consolidated folder size: \(formatFileSize(appState.consolidatedSize))")
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 500)
    }
    
    func selectFolders() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        
        if panel.runModal() == .OK {
            return panel.urls.compactMap { url in
                if folderAccessManager.requestAccess(to: url) {
                    return url
                } else {
                    appState.statusMessage = "Failed to get permission for folder: \(url.lastPathComponent)"
                    return nil
                }
            }
        }
        
        return []
    }
    
    func selectDestinationFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Select the destination for the consolidated folder"
        
        if panel.runModal() == .OK, let url = panel.urls.first {
            if folderAccessManager.requestAccess(to: url, forWriting: true) {
                return url
            } else {
                appState.statusMessage = "Failed to get write permission for the selected folder"
                return nil
            }
        }
        
        return nil
    }
    
    func consolidateFolders() {
        guard let destination = appState.destinationURL else { return }
        let consolidatedFolder = destination.appendingPathComponent(appState.newFolderName)
        
        appState.isWorking = true
        appState.statusMessage = "Working..."
        appState.progress = 0
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try folderAccessManager.accessFolder(destination, forWriting: true) {
                    let fileManager = FileManager.default
                    
                    if fileManager.fileExists(atPath: consolidatedFolder.path) {
                        try fileManager.removeItem(at: consolidatedFolder)
                    }
                    
                    try fileManager.createDirectory(at: consolidatedFolder, withIntermediateDirectories: true, attributes: nil)
                    
                    var totalItems = appState.sourceFolders.reduce(0) { $0 + $1.fileCount }
                    var processedItems = 0
                    
                    for folder in appState.sourceFolders {
                        try folderAccessManager.accessFolder(folder.url) {
                            if let enumerator = fileManager.enumerator(at: folder.url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                                while let fileURL = enumerator.nextObject() as? URL {
                                    let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                                    if resourceValues.isRegularFile == true {
                                        let relativePath = fileURL.relativePath(from: folder.url)
                                        let destinationURL = consolidatedFolder.appendingPathComponent(relativePath)
                                        
                                        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                                        
                                        if fileManager.fileExists(atPath: destinationURL.path) {
                                            let newName = generateUniqueFileName(for: destinationURL.lastPathComponent, at: destinationURL.deletingLastPathComponent())
                                            let newDestinationURL = destinationURL.deletingLastPathComponent().appendingPathComponent(newName)
                                            try fileManager.copyItem(at: fileURL, to: newDestinationURL)
                                        } else {
                                            try fileManager.copyItem(at: fileURL, to: destinationURL)
                                        }
                                        
                                        processedItems += 1
                                        DispatchQueue.main.async {
                                            appState.progress = Float(processedItems) / Float(totalItems)
                                            appState.statusMessage = "Processed \(processedItems) of \(totalItems) items"
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    if appState.deleteOriginals {
                        for folder in appState.sourceFolders {
                            try folderAccessManager.accessFolder(folder.url, forWriting: true) {
                                try fileManager.removeItem(at: folder.url)
                            }
                        }
                    }
                    
                    let consolidatedSize = calculateFolderSize(consolidatedFolder)
                    let operation = ConsolidationOperation(
                        id: UUID(),
                        date: Date(),
                        sourceFolders: appState.sourceFolders.map { $0.url.path },
                        destinationFolder: consolidatedFolder.path,
                        itemCount: processedItems,
                        totalSize: consolidatedSize
                    )
                    saveOperation(operation)
                    
                    DispatchQueue.main.async {
                        appState.consolidatedSize = consolidatedSize
                        appState.isWorking = false
                        appState.statusMessage = "Completed! Consolidated \(processedItems) items."
                        if appState.deleteOriginals {
                            appState.statusMessage += " Original folders deleted."
                        }
                        appState.sourceFolders.removeAll()
                        updateTotalSourceSize()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    appState.isWorking = false
                    appState.statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func generateUniqueFileName(for fileName: String, at folder: URL) -> String {
        var newName = fileName
        var counter = 1
        let fileManager = FileManager.default
        
        while fileManager.fileExists(atPath: folder.appendingPathComponent(newName).path) {
            let fileExtension = (fileName as NSString).pathExtension
            let fileNameWithoutExtension = (fileName as NSString).deletingPathExtension
            newName = "\(fileNameWithoutExtension)_\(counter).\(fileExtension)"
            counter += 1
        }
        
        return newName
    }
    
    func saveOperation(_ operation: ConsolidationOperation) {
        do {
            var operations = try JSONDecoder().decode([ConsolidationOperation].self, from: consolidationHistory)
            operations.append(operation)
            consolidationHistory = try JSONEncoder().encode(operations)
        } catch {
            let operations = [operation]
            consolidationHistory = (try? JSONEncoder().encode(operations)) ?? Data()
        }
    }
    
    func updateTotalSourceSize() {
        appState.totalSourceSize = appState.sourceFolders.reduce(0) { $0 + $1.size }
    }
    
    func calculateFolderSize(_ url: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let attributes = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]) else {
                continue
            }
            if attributes.isDirectory == false {
                totalSize += Int64(attributes.fileSize ?? 0)
            }
        }
        return totalSize
    }
}

struct FolderView: View {
    let folder: FolderInfo
    let onRemove: () -> Void
    
    var body: some View {
        VStack {
            Image(systemName: "folder.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 50, height: 50)
                .foregroundColor(.gray)
            Text(folder.url.lastPathComponent)
                .lineLimit(1)
            Text(formatFileSize(folder.size))
            Text("\(folder.fileCount) files")
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
        .overlay(
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
            .padding(5),
            alignment: .topTrailing
        )
    }
    
    func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

struct DestinationFolderView: View {
    let folderName: String
    let path: String
    
    var body: some View {
        VStack {
            Image(systemName: "folder.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 50, height: 50)
                .foregroundColor(.black)
            Text(folderName)
                .lineLimit(1)
            Text(path)
                .lineLimit(1)
                .font(.caption)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

#Preview {
    let appState = AppState()
    appState.sourceFolders = [
        FolderInfo(url: URL(fileURLWithPath: "/Users/example/Documents")),
        FolderInfo(url: URL(fileURLWithPath: "/Users/example/Downloads"))
    ]
    appState.destinationURL = URL(fileURLWithPath: "/Users/example/Desktop")
    appState.newFolderName = "Consolidated Folder"
    appState.progress = 0.5
    appState.statusMessage = "Consolidating files..."
    return ConsolidateView(appState: appState)
}
