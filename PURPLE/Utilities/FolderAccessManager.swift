////
////  FolderAccessManager.swift
////  PURPLE
////
////  Created by Brandon Hollins on 10/15/24.
////
//
//import SwiftUI
//class FolderAccessManager: ObservableObject {
//    @Published var accessibleFolders: [URL: Data] = [:]
//    
//    func requestAccess(to url: URL) -> Bool {
//        do {
//            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
//            accessibleFolders[url] = bookmarkData
//            return true
//        } catch {
//            print("Failed to create security-scoped bookmark: \(error)")
//            return false
//        }
//    }
//    
//    func accessFolder(_ url: URL, perform action: () throws -> Void) throws {
//        guard let bookmarkData = accessibleFolders[url] else {
//            throw NSError(domain: "FolderAccessManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No access to folder"])
//        }
//        
//        var isStale = false
//        guard let accessedURL = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
//            throw NSError(domain: "FolderAccessManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to resolve bookmark"])
//        }
//        
//        if isStale {
//            _ = requestAccess(to: url)
//        }
//        
//        guard accessedURL.startAccessingSecurityScopedResource() else {
//            throw NSError(domain: "FolderAccessManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to access security-scoped resource"])
//        }
//        
//        defer { accessedURL.stopAccessingSecurityScopedResource() }
//        
//        try action()
//    }
//}
