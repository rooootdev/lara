//
//  DarkBoardView.swift
//  lara
//
//  Icon theming using VFS and SBX+chown
//

import SwiftUI
import UniformTypeIdentifiers

struct DarkBoardView: View {
    @ObservedObject var mgr = laramgr.shared
    
    @State private var installedApps: [AppInfo] = []
    @State private var selectedApp: AppInfo?
    @State private var showThemePicker = false
    @State private var showThemeImporter = false
    @State private var plainPngThemes: [String] = []
    @State private var importedThemes: [ImportedTheme] = []
    @State private var statusMessage: String?
    @State private var isWorking = false
    @State private var iconCache: [String: UIImage] = [:]
    
    private let iconThemePath = "/var/mobile/darkboard"
    
    struct ImportedTheme: Identifiable, Hashable {
        let id: String
        let name: String
        let path: String
        let iconCount: Int
    }
    
    struct AppInfo: Identifiable, Hashable {
        let id: String
        let name: String
        let bundleId: String
        let bundlePath: String
    }
    
    var body: some View {
        List {
            Section {
                Button {
                    scanApps()
                } label: {
                    if isWorking {
                        HStack { ProgressView(); Text("Scanning...") }
                    } else {
                        Text("Refresh Apps")
                    }
                }
                .disabled(isWorking)
            } header: { Text("Actions") } footer: {
                Text("Place PNG files as bundleid.png in /var/mobile/darkboard")
            }
            
            Section {
                if installedApps.isEmpty {
                    Text("No apps found").foregroundColor(.secondary)
                } else {
                    ForEach(installedApps) { app in
                        Button {
                            selectedApp = app
                            showThemePicker = true
                        } label: {
                            HStack(spacing: 12) {
                                iconView(for: app)
                                VStack(alignment: .leading) {
                                    Text(app.name).font(.headline)
                                    Text(app.bundleId).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "paintbrush").foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } header: { Text("Installed Apps") }
            
            if !importedThemes.isEmpty {
                Section {
                    ForEach(importedThemes) { theme in
                        NavigationLink {
                            ThemeDetailView(theme: theme, installedApps: installedApps, onApply: applyThemeIcon)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(theme.name).font(.headline)
                                    Text("\(theme.iconCount) icons").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                } header: { Text("Imported Themes") }
            }
        }
        .navigationTitle("DarkBoard")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showThemeImporter = true } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .disabled(isWorking)
            }
        }
        .fileImporter(isPresented: $showThemeImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            handleThemeImport(result)
        }
        .alert("Status", isPresented: .constant(statusMessage != nil)) {
            Button("OK") { statusMessage = nil }
        } message: { Text(statusMessage ?? "") }
        .sheet(isPresented: $showThemePicker) {
            if let app = selectedApp {
                ThemePickerSheet(app: app, themePath: iconThemePath, onSelect: { applyIcon(to: app, themeFile: $0) })
            }
        }
        .onAppear { scanApps(); scanThemes() }
    }
    
    @ViewBuilder
    private func iconView(for app: AppInfo) -> some View {
        if let icon = iconCache[app.bundlePath] {
            Image(uiImage: icon).resizable().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 9))
        } else {
            Image("unknown").resizable().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }
    
    private func scanApps() {
        guard !isWorking else { return }
        isWorking = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            var apps: [AppInfo] = []
            var cache: [String: UIImage] = [:]
            let fm = FileManager.default
            let roots = ["/private/var/containers/Bundle/Application", "/var/containers/Bundle/Application"]
            var seen = Set<String>()
            
            for root in roots {
                guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
                for uuid in entries {
                    let dir = root + "/" + uuid
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { continue }
                    guard let appsInDir = try? fm.contentsOfDirectory(atPath: dir) else { continue }
                    
                    for app in appsInDir where app.hasSuffix(".app") {
                        let bundlePath = dir + "/" + app
                        let normalized = bundlePath.hasPrefix("/private/") ? String(bundlePath.dropFirst(8)) : bundlePath
                        guard !seen.contains(normalized) else { continue }
                        
                        let info = NSDictionary(contentsOfFile: bundlePath + "/Info.plist") as? [String: Any]
                        let name = info?["CFBundleDisplayName"] as? String ?? info?["CFBundleName"] as? String ?? app
                        let bundleId = info?["CFBundleIdentifier"] as? String ?? "unknown"
                        seen.insert(normalized)
                        
                        if let icon = loadAppIcon(bundlePath: bundlePath) { cache[bundlePath] = icon }
                        apps.append(AppInfo(id: bundlePath, name: name, bundleId: bundleId, bundlePath: bundlePath))
                    }
                }
            }
            
            apps.sort { $0.name.lowercased() < $1.name.lowercased() }
            DispatchQueue.main.async {
                self.installedApps = apps
                self.iconCache = cache
                self.isWorking = false
            }
        }
    }
    
    private func scanThemes() {
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(atPath: iconThemePath) {
            plainPngThemes = files.filter { $0.hasSuffix(".png") }
        }
        scanImportedThemes()
    }
    
    private func scanImportedThemes() {
        let fm = FileManager.default
        var themes: [ImportedTheme] = []
        guard let entries = try? fm.contentsOfDirectory(atPath: iconThemePath) else {
            importedThemes = []; return
        }
        
        for entry in entries where entry.hasSuffix(".theme") {
            let themePath = iconThemePath + "/" + entry
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: themePath, isDirectory: &isDir), isDir.boolValue else { continue }
            
            var themeName = entry.replacingOccurrences(of: ".theme", with: "")
            let infoPlistPath = themePath + "/Info.plist"
            if let info = NSDictionary(contentsOfFile: infoPlistPath) as? [String: Any],
               let name = info["PackageName"] as? String { themeName = name }
            
            var iconCount = 0
            let iconBundlesPath = themePath + "/IconBundles"
            if let icons = try? fm.contentsOfDirectory(atPath: iconBundlesPath) {
                iconCount = icons.filter { $0.hasSuffix(".png") }.count
            }
            
            themes.append(ImportedTheme(id: themePath, name: themeName, path: themePath, iconCount: iconCount))
        }
        importedThemes = themes
    }
    
    private func handleThemeImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            isWorking = true
            
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                var themeName = url.lastPathComponent
                if !themeName.hasSuffix(".theme") { themeName = themeName + ".theme" }
                let destPath = self.iconThemePath + "/" + themeName
                
                do {
                    try? fm.removeItem(atPath: destPath)
                    try fm.copyItem(at: url, to: URL(fileURLWithPath: destPath))
                    DispatchQueue.main.async {
                        self.scanImportedThemes()
                        self.statusMessage = "Theme imported: \(themeName)"
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.statusMessage = "Import failed: \(error.localizedDescription)"
                    }
                }
                DispatchQueue.main.async { self.isWorking = false }
            }
        case .failure(let error):
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }
    
    private func loadAppIcon(bundlePath: String) -> UIImage? {
        guard let bundle = Bundle(path: bundlePath) else { return nil }
        if let icons = bundle.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            for name in files.reversed() {
                if let image = UIImage(named: name, in: bundle, compatibleWith: nil) { return image }
            }
        }
        if let name = bundle.infoDictionary?["CFBundleIconFile"] as? String,
           let image = UIImage(named: name, in: bundle, compatibleWith: nil) { return image }
        return nil
    }
    
    private func findIconPath(in bundlePath: String) -> String? {
        let fm = FileManager.default
        let candidates = ["AppIcon60x60@2x.png", "AppIcon60x60@3x.png", "AppIcon76x76@2x.png"]
        for name in candidates {
            let path = bundlePath + "/" + name
            if fm.fileExists(atPath: path) { return path }
        }
        guard let bundle = Bundle(path: bundlePath),
              let icons = bundle.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String] else { return nil }
        for name in files.reversed() where name.contains("@2x") {
            let path = bundlePath + "/" + name + ".png"
            if fm.fileExists(atPath: path) { return path }
        }
        if let firstFile = files.first {
            let path = bundlePath + "/" + firstFile + ".png"
            if fm.fileExists(atPath: path) { return path }
        }
        return nil
    }
    
    private func applyIcon(to app: AppInfo, themeFile: String) {
        isWorking = true
        showThemePicker = false
        
        let sourcePath = iconThemePath + "/" + themeFile
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            statusMessage = "Theme file not found"; isWorking = false; return
        }
        guard let targetPath = findIconPath(in: app.bundlePath) else {
            statusMessage = "Could not find icon path"; isWorking = false; return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.mgr.lara_overwritefile(target: targetPath, source: sourcePath)
            DispatchQueue.main.async {
                self.isWorking = false
                if result.ok {
                    self.statusMessage = "Icon applied! Respring to see changes."
                    self.mgr.logmsg("(darkboard) applied \(themeFile) to \(app.bundleId)")
                } else {
                    self.statusMessage = "Failed: \(result.message)"
                }
            }
        }
    }
    
    private func applyThemeIcon(to app: AppInfo, iconPath: String) {
        isWorking = true
        guard let targetPath = findIconPath(in: app.bundlePath) else {
            statusMessage = "Could not find icon path"; isWorking = false; return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.mgr.lara_overwritefile(target: targetPath, source: iconPath)
            DispatchQueue.main.async {
                self.isWorking = false
                if result.ok {
                    self.statusMessage = "Icon applied! Respring to see changes."
                    self.mgr.logmsg("(darkboard) applied icon to \(app.bundleId)")
                } else {
                    self.statusMessage = "Failed: \(result.message)"
                }
            }
        }
    }
}

struct ThemePickerSheet: View {
    let app: DarkBoardView.AppInfo
    let themePath: String
    let onSelect: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var themeFiles: [String] = []
    @State private var selectedTheme: String?
    @State private var previewImage: UIImage?
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(app.name).font(.headline)
                            Text(app.bundleId).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        if let img = previewImage {
                            Image(uiImage: img).resizable().frame(width: 60, height: 60).clipShape(RoundedRectangle(cornerRadius: 13))
                        }
                    }
                }
                
                Section {
                    ForEach(themeFiles, id: \.self) { file in
                        Button {
                            selectedTheme = file
                            loadPreview(for: file)
                        } label: {
                            HStack {
                                Text(file.replacingOccurrences(of: ".png", with: ""))
                                Spacer()
                                if selectedTheme == file {
                                    Image(systemName: "checkmark").foregroundColor(.blue)
                                }
                            }
                        }
                    }
                } header: { Text("Available Themes") }
            }
            .navigationTitle("Select Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        if let theme = selectedTheme { onSelect(theme); dismiss() }
                    }
                    .disabled(selectedTheme == nil)
                }
            }
        }
        .onAppear { scanThemes() }
    }
    
    private func scanThemes() {
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(atPath: themePath) {
            themeFiles = files.filter { $0.hasSuffix(".png") }
        }
    }
    
    private func loadPreview(for file: String) {
        previewImage = UIImage(contentsOfFile: themePath + "/" + file)
    }
}

struct ThemeDetailView: View {
    let theme: DarkBoardView.ImportedTheme
    let installedApps: [DarkBoardView.AppInfo]
    let onApply: (DarkBoardView.AppInfo, String) -> Void
    
    @State private var matchingApps: [(String, DarkBoardView.AppInfo)] = []
    
    var body: some View {
        List {
            Section {
                Text("\(matchingApps.count) matching apps").foregroundColor(.secondary)
            }
            
            ForEach(matchingApps, id: \.1.id) { match in
                Button {
                    onApply(match.1, theme.path + "/IconBundles/" + match.0)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(match.1.name).font(.headline)
                            Text(match.0).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "paintbrush").foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle(theme.name)
        .onAppear { loadThemeIcons() }
    }
    
    private func loadThemeIcons() {
        let fm = FileManager.default
        let iconBundlesPath = theme.path + "/IconBundles"
        guard let icons = try? fm.contentsOfDirectory(atPath: iconBundlesPath) else { return }
        
        var matches: [(String, DarkBoardView.AppInfo)] = []
        for iconFile in icons where iconFile.hasSuffix(".png") {
            var iconName = iconFile
                .replacingOccurrences(of: "-large.png", with: "")
                .replacingOccurrences(of: "-large@2x.png", with: "")
                .replacingOccurrences(of: ".png", with: "")
            
            for app in installedApps {
                if app.bundleId == iconName || app.bundleId.lowercased() == iconName.lowercased() {
                    matches.append((iconFile, app))
                }
            }
        }
        matchingApps = matches.sorted { $0.1.name.lowercased() < $1.1.name.lowercased() }
    }
}
