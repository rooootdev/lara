//
//
// CacheView.swift
//
// lara
//

import SwiftUI
import UIKit
import WebKit
import Combine

// MARK: - Models

struct CacheApp: Identifiable {
    let id: String
    let name: String
    let bundleID: String?

    let appBundlePath: String?
    let dataContainerPath: String

    let icon: UIImage?

    let cacheSize: Int64
    let tmpSize: Int64
    let documentsSize: Int64

    let cachePath: String
    let tmpPath: String
    let documentsPath: String
}

struct StorageSnapshot: Identifiable {
    let id = UUID()
    let date = Date()
    let totalBytes: Int64
}

struct AppRecord {
    let dataUUID: String
    let bundleID: String
    let bundlePath: String
    let name: String
    let icon: UIImage?
}

// MARK: - Manager

final class CleanerManager: ObservableObject {

    @Published var apps: [CacheApp] = []
    @Published var snapshots: [StorageSnapshot] = []

    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var statusText = ""

    @Published var totalCacheBytes: Int64 = 0

    private let fm = FileManager.default
    private let dataRoot = "/var/mobile/Containers/Data/Application"

    // Resolver (optional enrichment layer)
    private let resolver = BundleResolver()
    private var appDB: [String: AppRecord] = [:]

    // MARK: Build DB (SAFE)
    private func buildDatabase() {
        let resolved = resolver.resolveAll()

        var db: [String: AppRecord] = [:]
        for app in resolved {
            db[app.dataUUID] = AppRecord(
                dataUUID: app.dataUUID,
                bundleID: app.bundleID,
                bundlePath: app.bundlePath,
                name: app.name,
                icon: app.icon
            )
        }

        self.appDB = db
    }

    // MARK: Scan

    func startScan(minSizeMB: Int64 = 1) {

        guard !isScanning else { return }

        isScanning = true
        apps.removeAll()
        scanProgress = 0
        totalCacheBytes = 0
        statusText = "Scanning apps..."

        DispatchQueue.global(qos: .userInitiated).async {

            self.buildDatabase()

            let containers = (try? self.fm.contentsOfDirectory(atPath: self.dataRoot)) ?? []

            let total = max(containers.count, 1)
            var processed = 0

            var results: [CacheApp] = []

            for uuid in containers {

                let dataPath = self.dataRoot + "/" + uuid

                let cachePath = dataPath + "/Library/Caches"
                let tmpPath = dataPath + "/tmp"
                let docsPath = dataPath + "/Documents"

                let cacheSize = self.folderSize(cachePath)
                let tmpSize = self.folderSize(tmpPath)
                let docsSize = self.folderSize(docsPath)

                let totalSize = cacheSize + tmpSize + docsSize

                // Only skip extremely small containers
                if totalSize < minSizeMB * 1024 * 1024 {
                    processed += 1
                    continue
                }

                let appInfo = self.appDB[uuid]

                let name = appInfo?.name ?? "App \(uuid.suffix(6))"
                let bundleID = appInfo?.bundleID
                let bundlePath = appInfo?.bundlePath
                let icon = appInfo?.icon

                results.append(CacheApp(
                    id: uuid,
                    name: name,
                    bundleID: bundleID,
                    appBundlePath: bundlePath,
                    dataContainerPath: dataPath,
                    icon: icon,
                    cacheSize: cacheSize,
                    tmpSize: tmpSize,
                    documentsSize: docsSize,
                    cachePath: cachePath,
                    tmpPath: tmpPath,
                    documentsPath: docsPath
                ))

                processed += 1

                DispatchQueue.main.async {
                    self.scanProgress = Double(processed) / Double(total)
                    self.statusText = "Scanning \(processed)/\(total)"
                }
            }

            let totalBytes = results.reduce(0) {
                $0 + $1.cacheSize + $1.tmpSize + $1.documentsSize
            }

            DispatchQueue.main.async {
                self.apps = results.sorted { $0.cacheSize > $1.cacheSize }
                self.totalCacheBytes = totalBytes

                self.snapshots.append(StorageSnapshot(totalBytes: totalBytes))

                self.isScanning = false
                self.scanProgress = 1.0
                self.statusText = "Completed (\(results.count) apps)"
            }
        }
    }

    // MARK: Delete

    func deleteCache(_ app: CacheApp) {
        try? fm.removeItem(atPath: app.cachePath)
        try? fm.removeItem(atPath: app.tmpPath)
    }

    func deleteAll() {
        for app in apps {
            deleteCache(app)
        }
    }

    // MARK: Web cleanup

    func cleanWKWebView() {

        let types: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeWebSQLDatabases
        ]

        WKWebsiteDataStore.default().removeData(
            ofTypes: types,
            modifiedSince: Date(timeIntervalSince1970: 0)
        ) {
            DispatchQueue.main.async {
                self.statusText = "WKWebView cleared"
            }
        }
    }

    func cleanURLCache() {
        URLCache.shared.removeAllCachedResponses()
    }

    // MARK: Size

    private func folderSize(_ path: String) -> Int64 {
        guard let e = fm.enumerator(atPath: path) else { return 0 }

        var size: Int64 = 0

        for case let file as String in e {

            let full = (path as NSString).appendingPathComponent(file)

            if let attrs = try? fm.attributesOfItem(atPath: full),
               let fileSize = attrs[.size] as? NSNumber {
                size += fileSize.int64Value
            }
        }

        return size
    }
}

// MARK: - UI

struct CacheView: View {

    @StateObject var mgr = CleanerManager()

    var body: some View {

        NavigationStack {

            VStack {

                Text("Clean Cache")
                    .font(.title2).bold()

                Text("\(mgr.totalCacheBytes / 1024 / 1024) MB Total")
                    .font(.title)

                ProgressView(value: mgr.scanProgress)

                Text(mgr.statusText)
                    .font(.caption)

                List {

                    Section("Apps") {

                        ForEach(mgr.apps) { app in

                            HStack {

                                if let icon = app.icon {
                                    Image(uiImage: icon)
                                        .resizable()
                                        .frame(width: 40, height: 40)
                                        .cornerRadius(8)
                                } else {
                                    Image(systemName: "app")
                                }

                                VStack(alignment: .leading) {
                                    Text(app.name).bold()
                                    Text("Cache \(app.cacheSize / 1024 / 1024) MB")
                                    Text("Tmp \(app.tmpSize / 1024 / 1024) MB")
                                    Text("Docs \(app.documentsSize / 1024 / 1024) MB")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    mgr.deleteCache(app)
                                } label: {
                                    Text("Delete")
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    mgr.deleteCache(app)
                                } label: {
                                    Text("Cache")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button(role: .destructive) {
                                try? FileManager.default.removeItem(atPath: app.documentsPath)
                                if let index = mgr.apps.firstIndex(where: { $0.id == app.id }) {
                                    mgr.apps[index] = CacheApp(
                                        id: app.id,
                                        name: app.name,
                                        bundleID: app.bundleID,
                                        appBundlePath: app.appBundlePath,
                                        dataContainerPath: app.dataContainerPath,
                                        icon: app.icon,
                                        cacheSize: app.cacheSize,
                                        tmpSize: app.tmpSize,
                                        documentsSize: 0,  
                                        cachePath: app.cachePath,
                                        tmpPath: app.tmpPath,
                                        documentsPath: app.documentsPath

                                    )
                                }
                                    
                            } label: {
                                Text("Docs")
                            }
                            .tint(.orange)
                            }
                        }
                    }

                    Section("Tools") {

                        Button("Delete ALL Cache") {
                            mgr.deleteAll()
                        }
                        .foregroundStyle(.red)

                        Button("Clear WKWebView") {
                            mgr.cleanWKWebView()
                        }

                        Button("Clear URLCache") {
                            mgr.cleanURLCache()
                        }

                        Button("Rescan") {
                            mgr.startScan()
                        }
                    }
                }
            }
            .onAppear {
                mgr.startScan()
            }
        }
    }
}
