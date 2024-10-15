//
//  ContentView.swift
//  PURPLE
//
//  Created by Brandon Hollins on 10/14/24.
//

import SwiftUI
import SwiftData
//
//  ContentView.swift
//  PURPLE
//
//  Created by Brandon Hollins on 10/14/24.
//
import SwiftUI
import ZIPFoundation

struct ContentView: View {
    @State private var selectedSidebarItem: SidebarItem? = .consolidate
    
    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedSidebarItem)
        } detail: {
            switch selectedSidebarItem {
            case .consolidate:
                ConsolidateView()
            case .compress:
                CompressView()
            case .settings:
                SettingsView()
            case .history:
                HistoryView()
            case .none:
                Text("Select an item from the sidebar")
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
    @State private var sourceFolders: [URL] = []
    @State private var destinationURL: URL?
    @State private var isWorking = false
    @State private var statusMessage = ""
    @State private var progress: Float = 0
    @State private var newFolderName = "Consolidated Midjourney"
    @State private var deleteOriginals = false
    @State private var totalSourceSize: Int64 = 0
    @State private var consolidatedSize: Int64 = 0
    @AppStorage("consolidationHistory") private var consolidationHistory: Data = Data()
    
    var body: some View {
        VStack(spacing: 20) {
            Button("Select Source Folders") {
                let newFolders = selectFolders()
                sourceFolders.append(contentsOf: newFolders)
                updateTotalSourceSize()
            }
            .disabled(isWorking)
            
            HStack {
                Circle()
                    .fill(sourceFolders.isEmpty ? .red : .green)
                    .frame(width: 10, height: 10)
                Text(sourceFolders.isEmpty ? "No folders selected" : "\(sourceFolders.count) folder(s) selected")
                    .foregroundColor(sourceFolders.isEmpty ? .red : .green)
            }
            
            if !sourceFolders.isEmpty {
                Text("Total size of selected folders: \(formatFileSize(totalSourceSize))")
            }
            
            List {
                ForEach(sourceFolders, id: \.self) { folder in
                    HStack {
                        Text(folder.lastPathComponent)
                        Spacer()
                        Button(action: {
                            sourceFolders.removeAll { $0 == folder }
                            updateTotalSourceSize()
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
            
            TextField("New Folder Name", text: $newFolderName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Toggle("Delete original folders after consolidation", isOn: $deleteOriginals)
            
            Button("Consolidate Folders") {
                consolidateFolders()
            }
            .disabled(isWorking || sourceFolders.isEmpty || destinationURL == nil)
            
            ProgressView(value: progress)
                .opacity(isWorking ? 1 : 0)
            
            if !statusMessage.isEmpty {
                Text(statusMessage)
            }
            
            if consolidatedSize > 0 {
                Text("Consolidated folder size: \(formatFileSize(consolidatedSize))")
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
    
    func consolidateFolders() {
        guard let destination = destinationURL else { return }
        let consolidatedFolder = destination.appendingPathComponent(newFolderName)
        
        isWorking = true
        statusMessage = "Working..."
        progress = 0
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fileManager = FileManager.default
                
                try fileManager.createDirectory(at: consolidatedFolder, withIntermediateDirectories: true, attributes: nil)
                
                var totalItems = 0
                var processedItems = 0
                
                for source in sourceFolders {
                    let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
                    while let url = enumerator?.nextObject() as? URL {
                        if url.lastPathComponent.hasPrefix("Midjourn") {
                            totalItems += try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).count
                        }
                    }
                }
                
                for source in sourceFolders {
                    let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
                    while let url = enumerator?.nextObject() as? URL {
                        if url.lastPathComponent.hasPrefix("Midjourn") {
                            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                            
                            for fileURL in contents {
                                let destinationURL = consolidatedFolder.appendingPathComponent(fileURL.lastPathComponent)
                                
                                if fileManager.fileExists(atPath: destinationURL.path) {
                                    let newName = generateUniqueFileName(for: fileURL.lastPathComponent, at: consolidatedFolder)
                                    let newDestinationURL = consolidatedFolder.appendingPathComponent(newName)
                                    try fileManager.copyItem(at: fileURL, to: newDestinationURL)
                                } else {
                                    try fileManager.copyItem(at: fileURL, to: destinationURL)
                                }
                                
                                processedItems += 1
                                DispatchQueue.main.async {
                                    progress = Float(processedItems) / Float(totalItems)
                                    statusMessage = "Processed \(processedItems) of \(totalItems) items"
                                }
                            }
                        }
                    }
                }
                
                if deleteOriginals {
                    for folder in sourceFolders {
                        try fileManager.removeItem(at: folder)
                    }
                }
                
                let consolidatedSize = calculateFolderSize(consolidatedFolder)
                let operation = ConsolidationOperation(
                    id: UUID(),
                    date: Date(),
                    sourceFolders: sourceFolders.map { $0.path },
                    destinationFolder: consolidatedFolder.path,
                    itemCount: processedItems,
                    totalSize: consolidatedSize
                )
                saveOperation(operation)
                
                DispatchQueue.main.async {
                    self.consolidatedSize = consolidatedSize
                    isWorking = false
                    statusMessage = "Completed! Consolidated \(processedItems) items."
                    if deleteOriginals {
                        statusMessage += " Original folders deleted."
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isWorking = false
                    statusMessage = "Error: \(error.localizedDescription)"
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
        DispatchQueue.global(qos: .userInitiated).async {
            let newSize = sourceFolders.reduce(0) { $0 + calculateFolderSize($1) }
            DispatchQueue.main.async {
                totalSourceSize = newSize
            }
        }
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


struct CompressView: View {
    @State private var sourceFolders: [URL] = []
    @State private var destinationURL: URL?
    @State private var isWorking = false
    @State private var statusMessage = ""
    @State private var progress: Float = 0
    @State private var zipFileName = "Compressed.zip"
    @State private var deleteOriginals = false
    @State private var totalSourceSize: Int64 = 0
    @State private var compressedSize: Int64 = 0
    
    var body: some View {
        VStack(spacing: 20) {
            Button("Select Folders to Compress") {
                let newFolders = selectFolders()
                sourceFolders.append(contentsOf: newFolders)
                updateTotalSourceSize()
            }
            .disabled(isWorking)
            
            HStack {
                Circle()
                    .fill(sourceFolders.isEmpty ? .red : .green)
                    .frame(width: 10, height: 10)
                Text(sourceFolders.isEmpty ? "No folders selected" : "\(sourceFolders.count) folder(s) selected")
                    .foregroundColor(sourceFolders.isEmpty ? .red : .green)
            }
            
            if !sourceFolders.isEmpty {
                Text("Total size of selected folders: \(formatFileSize(totalSourceSize))")
            }
            
            List {
                ForEach(sourceFolders, id: \.self) { folder in
                    HStack {
                        Text(folder.lastPathComponent)
                        Spacer()
                        Button(action: {
                            sourceFolders.removeAll { $0 == folder }
                            updateTotalSourceSize()
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
            
            Toggle("Delete original folders after compression", isOn: $deleteOriginals)
            
            Button("Compress Folders") {
                compressFolders()
            }
            .disabled(isWorking || sourceFolders.isEmpty || destinationURL == nil)
            
            ProgressView(value: progress)
                .opacity(isWorking ? 1 : 0)
            
            if !statusMessage.isEmpty {
                Text(statusMessage)
            }
            
            if compressedSize > 0 {
                Text("Compressed file size: \(formatFileSize(compressedSize))")
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
                
                if deleteOriginals {
                    for folder in sourceFolders {
                        try fileManager.removeItem(at: folder)
                    }
                }
                
                let compressedSize = try fileManager.attributesOfItem(atPath: zipFileURL.path)[.size] as? Int64 ?? 0
                
                DispatchQueue.main.async {
                    self.compressedSize = compressedSize
                    isWorking = false
                    statusMessage = "Completed! Compressed \(processedItems) items into \(zipFileURL.lastPathComponent)"
                    if deleteOriginals {
                        statusMessage += " Original folders deleted."
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isWorking = false
                    statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func updateTotalSourceSize() {
        DispatchQueue.global(qos: .userInitiated).async {
            let newSize = sourceFolders.reduce(0) { $0 + calculateFolderSize($1) }
            DispatchQueue.main.async {
                totalSourceSize = newSize
            }
        }
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

          

                struct SettingsView: View {
                    var body: some View {
                        Text("Settings View")
                    }
                }

                struct HistoryView: View {
                    @AppStorage("consolidationHistory") private var consolidationHistory: Data = Data()
                    
                    var operations: [ConsolidationOperation] {
                        (try? JSONDecoder().decode([ConsolidationOperation].self, from: consolidationHistory)) ?? []
                    }
                    
                    var body: some View {
                        List(operations.reversed()) { operation in
                            VStack(alignment: .leading) {
                                Text("Date: \(operation.date, formatter: itemFormatter)")
                                Text("Destination: \(operation.destinationFolder)")
                                Text("Items Consolidated: \(operation.itemCount)")
                                Text("Total Size: \(ByteCountFormatter().string(fromByteCount: operation.totalSize))")
                                Text("Source Folders:")
                                ForEach(operation.sourceFolders, id: \.self) { folder in
                                    Text("- \(folder)")
                                        .padding(.leading)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    }
                    
                    private let itemFormatter: DateFormatter = {
                        let formatter = DateFormatter()
                        formatter.dateStyle = .short
                        formatter.timeStyle = .short
                        return formatter
                    }()
                }

                #Preview {
                    ContentView()
                }
