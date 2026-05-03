//
//  FontPicker.swift
//  lara
//
//  Created by ruter on 27.03.26.
//

import SwiftUI
import Darwin

struct AppsView: View {
    @ObservedObject var mgr: laramgr
    @AppStorage("selectedmethod") private var selectedmethod: method = .vfs
    
    @State private var scannedapps: [scannedapp] = []
    @State private var iconcache: [String: UIImage] = [:]

    struct scannedapp: Identifiable, Hashable {
        let id: String
        let name: String
        let bundleid: String
        let bundlepath: String
        let hasmobileprov: Bool
        let notbypassed: Bool
    }
    
    private func isbypassed(bundlepath: String) -> Bool {
        let key = "com.apple.installd.validatedByFreeProfile"

        errno = 0
        let size = getxattr(bundlepath, key, nil, 0, 0, 0)

        if size < 0 {
            let code = errno

            if code == ENOATTR {
                mgr.logmsg("(sbx) xattr not present (bypassed): \(bundlepath)")
                return true
            } else {
                let err = String(cString: strerror(code))
                mgr.logmsg("(sbx) getxattr error on \(bundlepath) | errno=\(code) | \(err)")
                return false
            }
        }

        mgr.logmsg("(sbx) xattr still present (NOT bypassed): \(bundlepath)")
        return false
    }
    
    private func sbx3apbypass() {
        guard mgr.sbxready else {
            mgr.logmsg("(sbx) sandbox escape not ready")
            return
        }

        let fm = FileManager.default
        let roots = [
            "/private/var/containers/Bundle/Application",
            "/var/containers/Bundle/Application"
        ]

        var seen: Set<String> = []
        var processed = 0

        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }

            for uuid in entries {
                let dir = root + "/" + uuid

                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { continue }
                guard let apps = try? fm.contentsOfDirectory(atPath: dir) else { continue }

                for app in apps where app.hasSuffix(".app") {
                    let bundlepath = dir + "/" + app

                    let normalized = bundlepath.hasPrefix("/private/")
                        ? String(bundlepath.dropFirst(8))
                        : bundlepath

                    if seen.contains(normalized) { continue }
                    seen.insert(normalized)

                    let mp = bundlepath + "/embedded.mobileprovision"
                    guard access(mp, F_OK) == 0 else { continue }

                    let testkey = "com.apple.installd.validatedByFreeProfile"
                    
                    let success = mgr.apfsown(path: bundlepath, uid: 501, gid: 501)
                    if !success {
                        mgr.logmsg("(sbx) failed to set ownership on: \(bundlepath)")
                    } else {
                        mgr.logmsg("(sbx) set ownership on: \(bundlepath)")
                    }

                    errno = 0
                    let rc = removexattr(bundlepath, testkey, 0)
                    if rc == 0 {
                        mgr.logmsg("(sbx) removed xattr on: \(bundlepath)")
                        processed += 1
                    } else {
                        let code = errno

                        if code == ENOATTR {
                            mgr.logmsg("(sbx) xattr already missing: \(bundlepath)")
                            processed += 1
                        } else {
                            let err = String(cString: strerror(code))
                            mgr.logmsg("(sbx) removexattr failed \(bundlepath) | errno=\(code) | \(err)")
                        }
                    }

                    errno = 0
                    let size = getxattr(bundlepath, testkey, nil, 0, 0, 0)
                    if size < 0 && errno == ENOATTR {
                        mgr.logmsg("(sbx) verified removal: \(bundlepath)")
                    } else {
                        mgr.logmsg("(sbx) xattr still exists on: \(bundlepath)")
                    }
                }
            }
        }
        
        mgr.logmsg("(sbx) processed \(processed) app(s)")

        if processed == 0 {
            mgr.logmsg("(sbx) no eligible app found for xattr test")
        }
    }
    
    private func scanappssbx() {
        guard mgr.sbxready else {
            scannedapps = []
            iconcache = [:]
            return
        }

        let fm = FileManager.default
        let roots = [
            "/private/var/containers/Bundle/Application",
            "/var/containers/Bundle/Application"
        ]

        var results: [scannedapp] = []
        var cache: [String: UIImage] = [:]
        var seen: Set<String> = []

        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }

            for uuid in entries {
                let dir = root + "/" + uuid
                
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { continue }
                guard let apps = try? fm.contentsOfDirectory(atPath: dir) else { continue }

                for app in apps where app.hasSuffix(".app") {
                    let bundlepath = dir + "/" + app
                    
                    let normalizedPath = bundlepath.hasPrefix("/private/")
                        ? String(bundlepath.dropFirst(8))
                        : bundlepath
                    
                    if seen.contains(normalizedPath) { continue }

                    let infoPath = bundlepath + "/Info.plist"
                    let info = NSDictionary(contentsOfFile: infoPath) as? [String: Any]

                    let name =
                        (info?["CFBundleDisplayName"] as? String) ??
                        (info?["CFBundleName"] as? String) ??
                        app
                    
                    let bundleid = (info?["CFBundleIdentifier"] as? String) ?? "unknown"

                    let mp = bundlepath + "/embedded.mobileprovision"
                    let hasMP = access(mp, F_OK) == 0
                    guard hasMP else { continue }

                    let validated = isbypassed(bundlepath: bundlepath)

                    seen.insert(normalizedPath)

                    if let icon = loadappicon(bundlepath: bundlepath) {
                        cache[bundlepath] = icon
                    }

                    results.append(
                        scannedapp(
                            id: bundlepath,
                            name: name,
                            bundleid: bundleid,
                            bundlepath: bundlepath,
                            hasmobileprov: hasMP,
                            notbypassed: !validated
                        )
                    )
                }
            }
        }

        results.sort { $0.name.lowercased() < $1.name.lowercased() }

        scannedapps = results
        iconcache = cache
    }
    
    private func loadappicon(bundlepath: String) -> UIImage? {
        guard let bundle = Bundle(path: bundlepath) else { return nil }

        if let icons = bundle.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            
            for name in files.reversed() {
                if let image = UIImage(named: name, in: bundle, compatibleWith: nil) {
                    return image
                }
            }
        }

        if let name = bundle.infoDictionary?["CFBundleIconFile"] as? String,
           let image = UIImage(named: name, in: bundle, compatibleWith: nil) {
            return image
        }

        return nil
    }
    
    var body: some View {
        List {
            Section {
                if scannedapps.isEmpty {
                    Text("No apps found.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(scannedapps) { app in
                        HStack(spacing: 12) {
                            if let icon = iconcache[app.bundlepath] {
                                Image(uiImage: icon)
                                    .resizable()
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                            } else {
                                Image("unknown")
                                    .resizable()
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                            }

                            VStack(alignment: .leading) {
                                Text(app.name)
                                    .font(.headline)

                                Text(app.bundleid)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if !app.notbypassed {
                                Image(systemName: "checkmark.circle")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
            } header: {
                Text("Sideloaded Apps")
            }

            Section {
                Button {
                    sbx3apbypass()
                } label: {
                    Text("Bypass 3 App Limit")
                }
            } footer: {
                Text("Needs to be reapplied everytime you sideload a new app.")
            }
        }
        .navigationTitle("3 App Bypass")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    scanappssbx()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            scanappssbx()
        }
    }
}
