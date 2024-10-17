import SwiftUI
import ZIPFoundation

struct FolderInfo: Identifiable {
    let id = UUID()
    let url: URL
    let size: Int64
    let fileCount: Int
    
    init(url: URL) {
        self.url = url
        let (size, count) = FolderInfo.getFolderInfo(url)
        self.size = size
        self.fileCount = count
    }
    
    static func getFolderInfo(_ url: URL) -> (Int64, Int) {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else {
            return (0, 0)
        }
        
        var totalSize: Int64 = 0
        var fileCount = 0
        
        for case let fileURL as URL in enumerator {
            guard let attributes = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]) else {
                continue
            }
            if attributes.isRegularFile == true {
                totalSize += Int64(attributes.fileSize ?? 0)
                fileCount += 1
            }
        }
        
        return (totalSize, fileCount)
    }
}

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

class FolderAccessManager: ObservableObject {
    @Published var accessibleFolders: [URL: Data] = [:]
    
    func requestAccess(to url: URL, forWriting: Bool = false) -> Bool {
        do {
            var options: URL.BookmarkCreationOptions = .withSecurityScope
            if forWriting {
                options.insert(.securityScopeAllowOnlyReadAccess)
            }
            let bookmarkData = try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
            accessibleFolders[url] = bookmarkData
            return true
        } catch {
            print("Failed to create security-scoped bookmark: \(error)")
            return false
        }
    }
    
    func accessFolder(_ url: URL, forWriting: Bool = false, perform action: () throws -> Void) throws {
        guard let bookmarkData = accessibleFolders[url] else {
            throw NSError(domain: "FolderAccessManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No access to folder"])
        }
        
        var isStale = false
        guard let accessedURL = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            throw NSError(domain: "FolderAccessManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to resolve bookmark"])
        }
        
        if isStale {
            _ = requestAccess(to: url, forWriting: forWriting)
        }
        
        guard accessedURL.startAccessingSecurityScopedResource() else {
            throw NSError(domain: "FolderAccessManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to access security-scoped resource"])
        }
        
        defer { accessedURL.stopAccessingSecurityScopedResource() }
        
        try action()
    }
}

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

struct ConsolidationOperation: Codable, Identifiable {
    let id: UUID
    let date: Date
    let sourceFolders: [String]
    let destinationFolder: String
    let itemCount: Int
    let totalSize: Int64
}

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
                                                          
                                                          func formatFileSize(_ size: Int64) -> String {
                                                              let formatter = ByteCountFormatter()
                                                              formatter.allowedUnits = [.useKB, .useMB, .useGB]
                                                              formatter.countStyle = .file
                                                              return formatter.string(fromByteCount: size)
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

                                                      struct CompressView: View {
                                                          @State private var sourceFolders: [URL] = []
                                                          @State private var destinationURL: URL?
                                                          @State private var isWorking = false
                                                          @State private var statusMessage = ""
                                                          @State private var progress: Float = 0
                                                          @State private var zipFileName = "Compressed.zip"
                                                          
                                                          var body: some View {
                                                              VStack(spacing: 20) {
                                                                  Button("Select Folders to Compress") {
                                                                      let newFolders = selectFolders()
                                                                      sourceFolders.append(contentsOf: newFolders)
                                                                  }
                                                                  .disabled(isWorking)
                                                                  
                                                                  HStack {
                                                                      Circle()
                                                                          .fill(sourceFolders.isEmpty ? .red : .green)
                                                                          .frame(width: 10, height: 10)
                                                                      Text(sourceFolders.isEmpty ? "No folders selected" : "\(sourceFolders.count) folder(s) selected")
                                                                          .foregroundColor(sourceFolders.isEmpty ? .red : .green)
                                                                  }
                                                                  
                                                                  List {
                                                                      ForEach(sourceFolders, id: \.self) { folder in
                                                                          HStack {
                                                                              Text(folder.lastPathComponent)
                                                                              Spacer()
                                                                              Button(action: {
                                                                                  sourceFolders.removeAll { $0 == folder }
                                                                              }) {
                                                                                  Image(systemName: "xmark.circle.fill")
                                                                                      .foregroundColor(.red)
                                                                              }
                                                                              .buttonStyle(PlainButtonStyle())
                                                                          }
                                                                      }
                                                                  }
                                                                  .frame(height: 100)
                                                                  
                                                                  Button("Select Destination Folder") {
                                                                      destinationURL = selectFolder()
                                                                  }
                                                                  .disabled(isWorking)
                                                                  
                                                                  TextField("Zip File Name", text: $zipFileName)
                                                                      .textFieldStyle(RoundedBorderTextFieldStyle())
                                                                  
                                                                  Button("Compress Folders") {
                                                                      compressFolders()
                                                                  }
                                                                  .disabled(isWorking || sourceFolders.isEmpty || destinationURL == nil)
                                                                  
                                                                  ProgressView(value: progress)
                                                                      .opacity(isWorking ? 1 : 0)
                                                                  
                                                                  if !statusMessage.isEmpty {
                                                                      Text(statusMessage)
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
                                                                  return panel.urls
                                                              }
                                                              
                                                              return []
                                                          }
                                                          
                                                          func selectFolder() -> URL? {
                                                              let panel = NSOpenPanel()
                                                              panel.allowsMultipleSelection = false
                                                              panel.canChooseDirectories = true
                                                              panel.canChooseFiles = false
                                                              
                                                              if panel.runModal() == .OK {
                                                                  return panel.urls.first
                                                              }
                                                              
                                                              return nil
                                                          }
                                                          
                                                          func compressFolders() {
                                                              guard let destination = destinationURL else { return }
                                                              let zipFileURL = destination.appendingPathComponent(zipFileName)
                                                              
                                                              isWorking = true
                                                              statusMessage = "Compressing..."
                                                              progress = 0
                                                              
                                                              DispatchQueue.global(qos: .userInitiated).async {
                                                                  do {
                                                                      let fileManager = FileManager.default
                                                                      
                                                                      guard let archive = Archive(url: zipFileURL, accessMode: .create) else {
                                                                          throw NSError(domain: "CompressView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create zip archive"])
                                                                      }
                                                                      
                                                                      var totalItems = 0
                                                                      var processedItems = 0
                                                                      
                                                                      for sourceURL in sourceFolders {
                                                                          if let enumerator = fileManager.enumerator(at: sourceURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                                                                              while let fileURL = enumerator.nextObject() as? URL {
                                                                                  let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                                                                                  if resourceValues.isRegularFile == true {
                                                                                      totalItems += 1
                                                                                  }
                                                                              }
                                                                          }
                                                                      }
                                                                      
                                                                      for sourceURL in sourceFolders {
                                                                          let folderName = sourceURL.lastPathComponent
                                                                          if let enumerator = fileManager.enumerator(at: sourceURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                                                                              while let fileURL = enumerator.nextObject() as? URL {
                                                                                  let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                                                                                  if resourceValues.isRegularFile == true {
                                                                                      let relativePath = fileURL.relativePath(from: sourceURL)
                                                                                      let entryPath = "\(folderName)/\(relativePath)"
                                                                                      try archive.addEntry(with: entryPath, fileURL: fileURL)
                                                                                      
                                                                                      processedItems += 1
                                                                                      DispatchQueue.main.async {
                                                                                          progress = Float(processedItems) / Float(totalItems)
                                                                                          statusMessage = "Compressed \(processedItems) of \(totalItems) items"
                                                                                      }
                                                                                  }
                                                                              }
                                                                          }
                                                                      }
                                                                      
                                                                      DispatchQueue.main.async {
                                                                          isWorking = false
                                                                          statusMessage = "Completed! Compressed \(processedItems) items into \(zipFileURL.lastPathComponent)"
                                                                      }
                                                                  } catch {
                                                                      DispatchQueue.main.async {
                                                                          isWorking = false
                                                                          statusMessage = "Error: \(error.localizedDescription)"
                                                                      }
                                                                  }
                                                              }
                                                          }
                                                      }

                                                      extension URL {
                                                          func relativePath(from base: URL) -> String {
                                                              let basePath = base.standardizedFileURL.path
                                                              let filePath = self.standardizedFileURL.path
                                                              
                                                              if filePath.hasPrefix(basePath) {
                                                                  let relativePath = String(filePath.dropFirst(basePath.count))
                                                                  return relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
                                                              }
                                                              
                                                              return filePath
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
