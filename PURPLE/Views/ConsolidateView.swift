//import SwiftUI
//import ZIPFoundation
//
//struct ConsolidateView: View {
//    @State private var sourceFolders: [FolderInfo] = []
//    @State private var destinationURL: URL?
//    @State private var isWorking = false
//    @State private var statusMessage = ""
//    @State private var progress: Float = 0
//    @State private var newFolderName = "Consolidated Midjourney"
//    @State private var deleteOriginals = false
//    @State private var totalSourceSize: Int64 = 0
//    @State private var consolidatedSize: Int64 = 0
//    @AppStorage("consolidationHistory") private var consolidationHistory: Data = Data()
//    
//    var body: some View {
//        VStack(spacing: 20) {
//            Button("Select Source Folders") {
//                let newFolders = selectFolders().map { FolderInfo(url: $0) }
//                sourceFolders.append(contentsOf: newFolders)
//                updateTotalSourceSize()
//            }
//            .disabled(isWorking)
//            
//            if !sourceFolders.isEmpty {
//                Text("Total size of selected folders: \(formatFileSize(totalSourceSize))")
//            }
//            
//            ScrollView {
//                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
//                    ForEach(sourceFolders) { folder in
//                        VStack {
//                            Image(systemName: "folder.fill")
//                                .resizable()
//                                .aspectRatio(contentMode: .fit)
//                                .frame(width: 50, height: 50)
//                                .foregroundColor(.gray)
//                            Text(folder.url.lastPathComponent)
//                                .lineLimit(1)
//                            Text(formatFileSize(folder.size))
//                            Text("\(folder.fileCount) files")
//                        }
//                        .padding()
//                        .background(Color.secondary.opacity(0.1))
//                        .cornerRadius(10)
//                        .overlay(
//                            Button(action: {
//                                sourceFolders.removeAll { $0.id == folder.id }
//                                updateTotalSourceSize()
//                            }) {
//                                Image(systemName: "xmark.circle.fill")
//                                    .foregroundColor(.red)
//                            }
//                            .padding(5),
//                            alignment: .topTrailing
//                        )
//                    }
//                    
//                    if let destination = destinationURL {
//                        VStack {
//                            Image(systemName: "folder.fill")
//                                .resizable()
//                                .aspectRatio(contentMode: .fit)
//                                .frame(width: 50, height: 50)
//                                .foregroundColor(.black)
//                            Text(newFolderName)
//                                .lineLimit(1)
//                            Text(destination.path)
//                                .lineLimit(1)
//                                .font(.caption)
//                        }
//                        .padding()
//                        .background(Color.secondary.opacity(0.1))
//                        .cornerRadius(10)
//                    }
//                }
//            }
//            .frame(height: 200)
//            
//            HStack {
//                TextField("New Folder Name", text: $newFolderName)
//                    .textFieldStyle(RoundedBorderTextFieldStyle())
//                
//                Button("Select Destination") {
//                    destinationURL = selectDestinationFolder()
//                }
//                .disabled(isWorking)
//            }
//            
//            Toggle("Delete original folders after consolidation", isOn: $deleteOriginals)
//            
//            Button("Consolidate Folders") {
//                consolidateFolders()
//            }
//            .disabled(isWorking || sourceFolders.isEmpty || destinationURL == nil)
//            
//            ProgressView(value: progress)
//                .opacity(isWorking ? 1 : 0)
//            
//            if !statusMessage.isEmpty {
//                Text(statusMessage)
//            }
//            
//            if consolidatedSize > 0 {
//                Text("Consolidated folder size: \(formatFileSize(consolidatedSize))")
//            }
//        }
//        .padding()
//        .frame(minWidth: 400, minHeight: 500)
//    }
//    
//    func selectFolders() -> [URL] {
//        let panel = NSOpenPanel()
//        panel.allowsMultipleSelection = true
//        panel.canChooseDirectories = true
//        panel.canChooseFiles = false
//        
//        if panel.runModal() == .OK {
//            return panel.urls
//        }
//        
//        return []
//    }
//    
//    func selectDestinationFolder() -> URL? {
//        let panel = NSOpenPanel()
//        panel.allowsMultipleSelection = false
//        panel.canChooseDirectories = true
//        panel.canChooseFiles = false
//        panel.canCreateDirectories = true
//        panel.prompt = "Choose"
//        panel.message = "Select the destination for the consolidated folder"
//        
//        if panel.runModal() == .OK {
//            return panel.urls.first
//        }
//        
//        return nil
//    }
//    
//    func consolidateFolders() {
//        guard let destination = destinationURL else { return }
//        let consolidatedFolder = destination.appendingPathComponent(newFolderName)
//        
//        isWorking = true
//        statusMessage = "Working..."
//        progress = 0
//        
//        DispatchQueue.global(qos: .userInitiated).async {
//            do {
//                let fileManager = FileManager.default
//                
//                try fileManager.createDirectory(at: consolidatedFolder, withIntermediateDirectories: true, attributes: nil)
//                
//                var totalItems = sourceFolders.reduce(0) { $0 + $1.fileCount }
//                var processedItems = 0
//                
//                for folder in sourceFolders {
//                    let enumerator = fileManager.enumerator(at: folder.url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
//                    while let fileURL = enumerator?.nextObject() as? URL {
//                        let destinationURL = consolidatedFolder.appendingPathComponent(fileURL.lastPathComponent)
//                        
//                        if fileManager.fileExists(atPath: destinationURL.path) {
//                            let newName = generateUniqueFileName(for: fileURL.lastPathComponent, at: consolidatedFolder)
//                            let newDestinationURL = consolidatedFolder.appendingPathComponent(newName)
//                            try fileManager.copyItem(at: fileURL, to: newDestinationURL)
//                        } else {
//                            try fileManager.copyItem(at: fileURL, to: destinationURL)
//                        }
//                        
//                        processedItems += 1
//                        DispatchQueue.main.async {
//                            progress = Float(processedItems) / Float(totalItems)
//                            statusMessage = "Processed \(processedItems) of \(totalItems) items"
//                        }
//                    }
//                }
//                
//                if deleteOriginals {
//                    for folder in sourceFolders {
//                        try fileManager.removeItem(at: folder.url)
//                    }
//                }
//                
//                let consolidatedSize = calculateFolderSize(consolidatedFolder)
//                let operation = ConsolidationOperation(
//                    id: UUID(),
//                    date: Date(),
//                    sourceFolders: sourceFolders.map { $0.url.path },
//                    destinationFolder: consolidatedFolder.path,
//                    itemCount: processedItems,
//                    totalSize: consolidatedSize
//                )
//                saveOperation(operation)
//                
//                DispatchQueue.main.async {
//                    self.consolidatedSize = consolidatedSize
//                    isWorking = false
//                    statusMessage = "Completed! Consolidated \(processedItems) items."
//                    if deleteOriginals {
//                        statusMessage += " Original folders deleted."
//                    }
//                    sourceFolders.removeAll()
//                    updateTotalSourceSize()
//                }
//            } catch {
//                DispatchQueue.main.async {
//                    isWorking = false
//                    statusMessage = "Error: \(error.localizedDescription)"
//                }
//            }
//        }
//    }
//    
//    func generateUniqueFileName(for fileName: String, at folder: URL) -> String {
//        var newName = fileName
//        var counter = 1
//        let fileManager = FileManager.default
//        
//        while fileManager.fileExists(atPath: folder.appendingPathComponent(newName).path) {
//            let fileExtension = (fileName as NSString).pathExtension
//            let fileNameWithoutExtension = (fileName as NSString).deletingPathExtension
//            newName = "\(fileNameWithoutExtension)_\(counter).\(fileExtension)"
//            counter += 1
//        }
//        
//        return newName
//    }
//    
//    func saveOperation(_ operation: ConsolidationOperation) {
//        do {
//            var operations = try JSONDecoder().decode([ConsolidationOperation].self, from: consolidationHistory)
//            operations.append(operation)
//            consolidationHistory = try JSONEncoder().encode(operations)
//        } catch {
//            let operations = [operation]
//            consolidationHistory = (try? JSONEncoder().encode(operations)) ?? Data()
//        }
//    }
//    
//    func updateTotalSourceSize() {
//        totalSourceSize = sourceFolders.reduce(0) { $0 + $1.size }
//    }
//    
//    func calculateFolderSize(_ url: URL) -> Int64 {
//        let fileManager = FileManager.default
//        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else {
//            return 0
//        }
//        
//        var totalSize: Int64 = 0
//        for case let fileURL as URL in enumerator {
//            guard let attributes = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]) else {
//                continue
//            }
//            if attributes.isDirectory == false {
//                totalSize += Int64(attributes.fileSize ?? 0)
//            }
//        }
//        return totalSize
//    }
//    
//    func formatFileSize(_ size: Int64) -> String {
//        let formatter = ByteCountFormatter()
//        formatter.allowedUnits = [.useKB, .useMB, .useGB]
//        formatter.countStyle = .file
//        return formatter.string(fromByteCount: size)
//    }
//}
//
//struct FolderInfo: Identifiable {
//    let id = UUID()
//    let url: URL
//    let size: Int64
//    let fileCount: Int
//    
//    init(url: URL) {
//        self.url = url
//        let (size, count) = FolderInfo.getFolderInfo(url)
//        self.size = size
//        self.fileCount = count
//    }
//    
//    static func getFolderInfo(_ url: URL) -> (Int64, Int) {
//        let fileManager = FileManager.default
//        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else {
//            return (0, 0)
//        }
//        
//        var totalSize: Int64 = 0
//        var fileCount = 0
//        
//        for case let fileURL as URL in enumerator {
//            guard let attributes = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]) else {
//                continue
//            }
//            if attributes.isRegularFile == true {
//                totalSize += Int64(attributes.fileSize ?? 0)
//                fileCount += 1
//            }
//        }
//        
//        return (totalSize, fileCount)
//    }
//}
