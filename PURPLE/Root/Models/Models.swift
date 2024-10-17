import SwiftUI

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

struct ConsolidationOperation: Codable, Identifiable {
    let id: UUID
    let date: Date
    let sourceFolders: [String]
    let destinationFolder: String
    let itemCount: Int
    let totalSize: Int64
}
