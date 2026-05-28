//
//  FileSystemHelpers.swift
//  lara
//
//  Created by lunginspector on 5/22/26.
//

import Foundation
import UniformTypeIdentifiers
import Combine

struct santanderclipitem {
    let path: String
    let isdir: Bool
    let name: String
}

final class santanderclip: ObservableObject {
    static let shared = santanderclip()
    @Published var item: santanderclipitem?
    init() {}
}

struct santandermsg: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}

enum santandersort: String, CaseIterable {
    case az
    case za
}

struct santanderlisting {
    let items: [santanderitem]
    let empty: String?
}

enum SantanderChown {
    static func chown(path: String, uid: UInt32, gid: UInt32) -> Bool {
        path.withCString {
            apfs_own($0, uid, gid) == 0
        }
    }
}

enum santanderfs {
    static func clearImmutableIfPossible(atPath path: String) {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 16 else {
            return
        }
        do {
            try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: path)
        } catch {
            // Some files do not expose the immutable flag to this process; keep the original operation error.
        }
    }

    static func removeItemClearingImmutable(atPath path: String) throws {
        clearImmutableIfPossible(atPath: path)
        try FileManager.default.removeItem(atPath: path)
    }

    static func listdir(item: santanderitem, readsbx: Bool) -> santanderlisting {
        guard item.isdir else { return santanderlisting(items: [], empty: "Not a directory.") }

        if readsbx {
            return listsbx(item: item)
        }

        let mgr = laramgr.shared
        guard mgr.vfsready else {
            return santanderlisting(items: [], empty: "VFS not ready.")
        }
        guard let entries = mgr.vfslistdir(path: item.path) else {
            return santanderlisting(items: [], empty: "Unable to list directory.")
        }

        let items = entries.map { entry in
            let full = item.path == "/" ? "/" + entry.name : item.path + "/" + entry.name
            return santanderitem(path: full, isdir: entry.isDir)
        }

        return santanderlisting(items: items, empty: items.isEmpty ? "Directory is empty." : nil)
    }

    static func listsbx(item: santanderitem) -> santanderlisting {
        let fm = FileManager.default
        var isdir = ObjCBool(false)
        let exists = fm.fileExists(atPath: item.path, isDirectory: &isdir)
        guard exists, isdir.boolValue else {
            return santanderlisting(items: [], empty: "Directory no longer exists.")
        }
        guard fm.isReadableFile(atPath: item.path) else {
            return santanderlisting(items: [], empty: "Cannot list directory (missing permissions).")
        }

        do {
            let names = try fm.contentsOfDirectory(atPath: item.path)
            let mode = fmAppsDisplayMode(rawValue: UserDefaults.standard.string(forKey: "selectedFMAppsDisplayMode") ?? "") ?? .appName
            let bundledirs = [
                "/private/var/containers/Bundle/Application",
                "/var/containers/Bundle/Application"
            ]
            var appnames: [String: String] = [:]

            if mode == .appName {
                appnames = appnamecache()
            }

            let items = names.map { name in
                let full = item.path == "/" ? "/" + name : item.path + "/" + name
                var isdir = ObjCBool(false)
                fm.fileExists(atPath: full, isDirectory: &isdir)
                var display = name
                var isApp = false
                var appUDID = ""

                if mode != .UUID, isdir.boolValue {
                    if bundledirs.contains(item.path), mode == .appName {
                        display = bundleappname(at: full) ?? name
                        isApp = true
                        appUDID = name
                    } else if let bundleid = bundleidforcontainer(at: full) {
                        switch mode {
                        case .appName:
                            display = appnames[bundleid] ?? bundleid
                            isApp = true
                            appUDID = name
                        case .bundleID:
                            display = bundleid
                        case .UUID:
                            break
                        }
                    }
                }

                return santanderitem(path: full, isdir: isdir.boolValue, display: display, isApp: isApp, appUDID: appUDID)
            }

            return santanderlisting(items: items, empty: items.isEmpty ? "Directory is empty." : nil)
        } catch {
            let err = error as NSError
            if err.domain == NSCocoaErrorDomain && err.code == NSFileReadNoPermissionError {
                return santanderlisting(items: [], empty: "Cannot list directory (missing permissions).")
            }
            return santanderlisting(items: [], empty: "Unable to list directory: \(err.localizedDescription)")
        }
    }

    static func filteritems(all: [santanderitem], base: String, query: String, showhidden: Bool, recsearch: Bool, sort: santandersort, readsbx: Bool) -> [santanderitem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [santanderitem]

        if !q.isEmpty && recsearch && readsbx {
            items = recsearchsbx(root: base, query: q)
        } else if !q.isEmpty {
            items = all.filter { $0.display.localizedCaseInsensitiveContains(q) || $0.path.localizedCaseInsensitiveContains(q) }
        } else {
            items = all
        }

        if q.isEmpty && !showhidden {
            items = items.filter { !$0.name.hasPrefix(".") }
        }

        switch sort {
        case .az:
            items.sort { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending }
        case .za:
            items.sort { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedDescending }
        }

        return items
    }

    static func emptymessage(shown: [santanderitem], all: [santanderitem], query: String, showhidden: Bool, fallback: String?) -> String? {
        guard shown.isEmpty else { return nil }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { return "No matching items." }
        if !showhidden && !all.isEmpty { return "No visible items. Enable hidden files to show dotfiles." }
        return fallback ?? "Directory is empty."
    }

    static func recsearchsbx(root: String, query: String) -> [santanderitem] {
        let fm = FileManager.default
        var out: [santanderitem] = []
        guard let en = fm.enumerator(atPath: root) else { return [] }

        for case let name as String in en {
            let full = (root as NSString).appendingPathComponent(name)
            var isdir = ObjCBool(false)
            fm.fileExists(atPath: full, isDirectory: &isdir)

            if name.localizedCaseInsensitiveContains(query) || full.localizedCaseInsensitiveContains(query) {
                out.append(santanderitem(path: full, isdir: isdir.boolValue))
            }
        }

        return out
    }

    static func uniquepath(base: String) -> String {
        let fm = FileManager.default
        if !fm.fileExists(atPath: base) { return base }

        let dir = (base as NSString).deletingLastPathComponent
        let file = (base as NSString).lastPathComponent
        let ext = (file as NSString).pathExtension
        let stem = ext.isEmpty ? file : (file as NSString).deletingPathExtension

        var i = 1
        while true {
            let suffix = i == 1 ? " copy" : " copy \(i)"
            let name = ext.isEmpty ? "\(stem)\(suffix)" : "\(stem)\(suffix).\(ext)"
            let candidate = (dir as NSString).appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate) {
                return candidate
            }
            i += 1
        }
    }

    static func fileDetails(path: String) -> FileInfoProperties {
        let fm = FileManager.default
        var info: FileInfoProperties = FileInfoProperties(fileExists: false, kind: "", uttype: "", size: 0, created: "", modified: "", isSymlink: false, posixPerms: "", owner: "", group: "", readable: false, writable: false, executable: false)
        
        // check if file exists & get type
        var isdir = ObjCBool(false)
        let exists = fm.fileExists(atPath: path, isDirectory: &isdir)
        
        if exists {
            info.fileExists = exists
            info.kind = isdir.boolValue ? "directory" : "file"
        }
        
        // get particular file info
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [.contentTypeKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey, .isSymbolicLinkKey]
        
        if let values = try? url.resourceValues(forKeys: keys) {
            if let type = values.contentType {
                info.uttype = type.identifier
            }
            if let size = values.fileSize {
                info.size = size
            }
            if let created = values.creationDate {
                info.created = created.description
            }
            if let modified = values.contentModificationDate {
                info.modified = modified.description
            }
            if let sym = values.isSymbolicLink {
                info.isSymlink = sym
            }
        }
        
        // now get permissions
        if let attrs = try? fm.attributesOfItem(atPath: path) {
            if let perms = attrs[.posixPermissions] as? NSNumber {
                info.posixPerms = String(format: "%04o", perms.intValue)
            }
            if let owner = attrs[.ownerAccountName] as? String {
                info.owner = owner
            }
            if let group = attrs[.groupOwnerAccountName] as? String {
                info.group = group
            }
        }
        
        info.readable = fm.isReadableFile(atPath: path)
        info.writable = fm.isWritableFile(atPath: path)
        info.executable = fm.isExecutableFile(atPath: path)
        
        return info
    }

    static func loadfile(item: santanderitem, readsbx: Bool) -> santanderloadedfile {
        if isimage(item) {
            if let data = readdata(path: item.path, readsbx: readsbx, max: 8 * 1024 * 1024),
               let img = UIImage(data: data) {
                return santanderloadedfile(preview: .image(img), text: "", editable: false)
            }
        }

        if ismedia(item), let url = preparetemp(item: item, readsbx: readsbx, maxbytes: 128 * 1024 * 1024) {
            return santanderloadedfile(preview: .media(url), text: "", editable: false)
        }

        guard let data = readdata(path: item.path, readsbx: readsbx, max: 2 * 1024 * 1024) else {
            let err = readsbx ? "Failed to read file.\n\n" + unreadabledetails(path: item.path) : "Failed to read file."
            return santanderloadedfile(preview: .error(err), text: err, editable: false)
        }

        let rendered = render(data: data)
        return santanderloadedfile(preview: .text(rendered.text, rendered.editable), text: rendered.text, editable: rendered.editable)
    }

    static func writefile(path: String, data: Data, readsbx: Bool, writevfs: Bool) -> Bool {
        if writevfs {
            return laramgr.shared.vfsoverwritewithdata(target: path, data: data)
        }
        guard readsbx else { return false }
        do {
            clearImmutableIfPossible(atPath: path)
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func readdata(path: String, readsbx: Bool, max: Int) -> Data? {
        if readsbx {
            let url = URL(fileURLWithPath: path)
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            if #available(iOS 13.4, *) {
                return try? handle.read(upToCount: max) ?? Data()
            }
            return handle.readData(ofLength: max)
        }
        return laramgr.shared.vfsread(path: path, maxSize: max)
    }

    static func preparetemp(item: santanderitem, readsbx: Bool, maxbytes: Int64) -> URL? {
        if readsbx {
            guard let size = sbxfilesize(path: item.path), size > 0, size <= maxbytes else { return nil }
            return URL(fileURLWithPath: item.path)
        }

        let size = vfs_filesize(item.path)
        guard size > 0, size <= maxbytes else { return nil }

        let ext = (item.path as NSString).pathExtension
        let name = "santander_" + UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: nil)

        guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
        defer { try? handle.close() }

        let chunk = 1024 * 1024
        var off: Int64 = 0
        while off < size {
            let want = Int(min(Int64(chunk), size - off))
            var buf = [UInt8](repeating: 0, count: want)
            let got = vfs_read(item.path, &buf, want, off_t(off))
            if got <= 0 { return nil }
            handle.write(Data(buf.prefix(Int(got))))
            off += Int64(got)
        }

        return url
    }

    static func isimage(_ item: santanderitem) -> Bool {
        if let type = item.type, type.isSubtype(of: .image) { return true }
        let ext = (item.path as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "heic", "heif", "bmp", "tif", "tiff", "webp"].contains(ext)
    }

    static func ismedia(_ item: santanderitem) -> Bool {
        if let type = item.type, type.isSubtype(of: .audio) || type.isSubtype(of: .movie) || type.isSubtype(of: .video) {
            return true
        }
        let ext = (item.path as NSString).pathExtension.lowercased()
        if ["mp4", "mov", "m4v", "avi", "mkv"].contains(ext) { return true }
        if ["mp3", "m4a", "m4b", "aac", "aiff", "wav", "caf", "flac", "opus", "ogg", "wma", "amr", "3gp"].contains(ext) { return true }
        return false
    }

    static func render(data: Data) -> (text: String, editable: Bool) {
        if data.isEmpty {
            return ("(empty file)", true)
        }
        if let plist = plisttext(data: data) {
            return (plist, false)
        }
        if let text = textdecode(data: data) {
            return (text, true)
        }
        return (hexdump(data: data), false)
    }

    static func plisttext(data: Data) -> String? {
        guard data.starts(with: Data("bplist".utf8)) || data.starts(with: Data("<?xml".utf8)) else {
            return nil
        }
        guard let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return nil
        }
        if JSONSerialization.isValidJSONObject(obj),
           let jsondata = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let json = String(data: jsondata, encoding: .utf8) {
            return json
        }
        if let xmldata = try? PropertyListSerialization.data(fromPropertyList: obj, format: .xml, options: 0),
           let xml = String(data: xmldata, encoding: .utf8) {
            return xml
        }
        return String(describing: obj)
    }

    static func textdecode(data: Data) -> String? {
        let encs: [String.Encoding] = [
            .utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .utf32, .utf32LittleEndian,
            .utf32BigEndian, .ascii, .isoLatin1, .windowsCP1252, .macOSRoman, .nonLossyASCII
        ]
        for enc in encs {
            guard let value = String(data: data, encoding: enc) else { continue }
            if lookstext(value) {
                return value
            }
        }
        return nil
    }

    static func lookstext(_ value: String) -> Bool {
        if value.isEmpty { return true }
        let scalars = value.unicodeScalars
        let bad = scalars.filter { scalar in
            let v = scalar.value
            if v == 9 || v == 10 || v == 13 { return false }
            if v < 32 { return true }
            if v >= 0x7F && v <= 0x9F { return true }
            return false
        }
        return Double(bad.count) / Double(scalars.count) < 0.01
    }

    static func hexdump(data: Data) -> String {
        let limit = min(data.count, 4096)
        let chunk = data.prefix(limit)
        var lines: [String] = []
        lines.append("Binary data (\(data.count) bytes). Showing first \(limit) bytes:")
        lines.append("")

        var off = 0
        while off < chunk.count {
            let row = chunk[off..<min(off + 16, chunk.count)]
            let hex = row.map { String(format: "%02X", $0) }.joined(separator: " ")
            let ascii = row.map { byte -> String in
                if byte >= 32 && byte <= 126 {
                    return String(UnicodeScalar(byte))
                }
                return "."
            }.joined()
            lines.append(String(format: "%08X  %-47@  %@", off, hex as NSString, ascii))
            off += 16
        }

        return lines.joined(separator: "\n")
    }

    static func unreadabledetails(path: String) -> String {
        let fm = FileManager.default
        var lines: [String] = []

        var isdir = ObjCBool(false)
        let exists = fm.fileExists(atPath: path, isDirectory: &isdir)
        lines.append("Exists: \(exists ? "yes" : "no")")
        if exists {
            lines.append("Kind: \(isdir.boolValue ? "directory" : "regular item")")
        }

        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [.contentTypeKey, .isSymbolicLinkKey, .isAliasFileKey, .fileSizeKey]
        if let values = try? url.resourceValues(forKeys: keys) {
            if let type = values.contentType {
                lines.append("UTType: \(type.identifier)")
            }
            if let size = values.fileSize {
                lines.append("Size: \(size) bytes")
            }
            if let sym = values.isSymbolicLink {
                lines.append("Symlink: \(sym ? "yes" : "no")")
            }
            if values.isSymbolicLink == true,
               let target = try? fm.destinationOfSymbolicLink(atPath: path) {
                lines.append("Symlink target: \(target)")
            }
            if let alias = values.isAliasFile {
                lines.append("Alias file: \(alias ? "yes" : "no")")
            }
        }

        if let attrs = try? fm.attributesOfItem(atPath: path) {
            if let filetype = attrs[.type] as? FileAttributeType {
                lines.append("File attribute type: \(filetype.rawValue)")
            }
            if let owner = attrs[.ownerAccountName] as? String {
                lines.append("Owner: \(owner)")
            }
            if let group = attrs[.groupOwnerAccountName] as? String {
                lines.append("Group: \(group)")
            }
            if let perms = attrs[.posixPermissions] as? NSNumber {
                lines.append(String(format: "POSIX perms: %04o", perms.intValue))
            }
        }

        lines.append("Readable: \(fm.isReadableFile(atPath: path) ? "yes" : "no")")
        lines.append("Writable: \(fm.isWritableFile(atPath: path) ? "yes" : "no")")
        lines.append("Executable: \(fm.isExecutableFile(atPath: path) ? "yes" : "no")")
        return lines.joined(separator: "\n")
    }

    static func sbxfilesize(path: String) -> Int64? {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? NSNumber {
            return size.int64Value
        }
        return nil
    }

    static func appnamecache() -> [String: String] {
        let fm = FileManager.default
        let bundlepath = "/private/var/containers/Bundle/Application"
        guard let apps = try? fm.contentsOfDirectory(atPath: bundlepath) else { return [:] }
        var out: [String: String] = [:]

        for app in apps {
            let apppath = bundlepath + "/" + app
            guard let contents = try? fm.contentsOfDirectory(atPath: apppath) else { continue }
            for item in contents where item.hasSuffix(".app") {
                let infopath = apppath + "/" + item + "/Info.plist"
                guard let plist = NSDictionary(contentsOf: URL(fileURLWithPath: infopath)),
                      let bundleid = plist["CFBundleIdentifier"] as? String else { continue }
                let appname = (plist["CFBundleDisplayName"] as? String) ??
                    (plist["CFBundleName"] as? String) ??
                    (plist["CFBundleExecutable"] as? String) ??
                    bundleid
                out[bundleid] = appname
                break
            }
        }

        return out
    }

    static func bundleappname(at path: String) -> String? {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path) else { return nil }
        for item in contents where item.hasSuffix(".app") {
            let infopath = path + "/" + item + "/Info.plist"
            guard let plist = NSDictionary(contentsOf: URL(fileURLWithPath: infopath)) else { continue }
            return (plist["CFBundleDisplayName"] as? String) ??
                (plist["CFBundleName"] as? String) ??
                (plist["CFBundleExecutable"] as? String)
        }
        return nil
    }

    static func bundleidforcontainer(at path: String) -> String? {
        let meta = path + "/.com.apple.mobile_container_manager.metadata.plist"
        guard let plist = NSDictionary(contentsOf: URL(fileURLWithPath: meta)) else { return nil }
        return plist["MCMMetadataIdentifier"] as? String
    }
}
