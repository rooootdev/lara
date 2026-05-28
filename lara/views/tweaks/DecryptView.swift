//
//  DecryptView.swift
//  lara
//
//  Created by neonmodder123 on 23.05.26.
//

import SwiftUI

struct decryptapp: Identifiable {
    let id = UUID()
    let name: String
    let bundleid: String
    let bundlepath: String
    let executable: String
    let icon: UIImage?
    var isencrypted: decryptstatus = .unknown
}

enum decryptstatus {
    case encrypted, unencrypted, unknown
}

struct DecryptView: View {
    @ObservedObject private var mgr = laramgr.shared
    @State private var query = ""
    @State private var apps: [decryptapp] = []
    @State private var decryptingbid: String? = nil
    @State private var errormsg: String? = nil
    @State private var pendingdecrypt: decryptapp? = nil

    private let documentspath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""

    private var filteredapps: [decryptapp] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return apps }
        let q = trimmed.lowercased()
        return apps.filter { $0.name.lowercased().contains(q) || $0.bundleid.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !mgr.sbxready {
                    Section {
                        Text("Sandbox escape not ready. Run the sandbox escape first.")
                            .foregroundColor(.secondary)
                    } header: { Text("Status") }
                }

                HStack {
                    TextField("Search", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(action: loadapps) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(!mgr.sbxready || decryptingbid != nil)
                }

                if let error = errormsg {
                    Section {
                        PlainAlert(title: "Error", icon: "exclamationmark.triangle", text: error, color: .red)
                    }
                }

                Section {
                    if filteredapps.isEmpty {
                        Text(query.isEmpty ? "Loading..." : "No matches.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(filteredapps) { app in
                            AppRow(app: app, isdecrypting: decryptingbid == app.bundleid) {
                                startdecrypt(app)
                            }
                        }
                    }
                } header: {
                    HeaderLabel(text: "Installed Apps", icon: "app.badge")
                }
            }
            .navigationTitle("App Decrypt")
        }
        .onAppear {
            set_log_callback { msg in
                guard let msg = msg else { return }
                let s = String(cString: msg)
                DispatchQueue.main.async {
                    laramgr.shared.logmsg("(decrypt) \(s)")
                }
            }
            if mgr.sbxready { loadapps() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            if let app = pendingdecrypt {
                pendingdecrypt = nil
                let pid = find_process_pid(app.executable)
                if pid > 0 {
                    dodecrypt(app, pid: pid)
                } else {
                    errormsg = "App is not running, try again."
                    decryptingbid = nil
                }
            }
        }
        .onChange(of: mgr.sbxready) { ready in
            if ready { loadapps() } else { apps.removeAll() }
        }
    }

    func loadapps() {
        guard mgr.sbxready else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [decryptapp] = []
            let bundleFolder = "/private/var/containers/Bundle/Application"

            guard let bundles = try? FileManager.default.contentsOfDirectory(atPath: bundleFolder) else {
                DispatchQueue.main.async { apps.removeAll() }
                return
            }

            for bundle in bundles {
                let appPath = bundleFolder + "/" + bundle
                guard let contents = try? FileManager.default.contentsOfDirectory(atPath: appPath) else { continue }
                for item in contents {
                    guard item.hasSuffix(".app") else { continue }
                    let fullAppPath = appPath + "/" + item
                    let infoPath = fullAppPath + "/Info.plist"
                    guard let info = NSDictionary(contentsOfFile: infoPath) else { continue }

                    let executable = info["CFBundleExecutable"] as? String ?? ""
                    if executable.isEmpty { continue }
                    let bundleid = info["CFBundleIdentifier"] as? String ?? ""
                    let name = (info["CFBundleDisplayName"] as? String) ??
                               (info["CFBundleName"] as? String) ??
                               (item as NSString).deletingPathExtension

                    var icon: UIImage? = nil
                    if let icons = info["CFBundleIcons"] as? [String: Any],
                       let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
                       let iconfiles = primary["CFBundleIconFiles"] as? [String],
                       let iconname = iconfiles.last {
                        let iconpath = fullAppPath + "/" + iconname
                        if let img = UIImage(contentsOfFile: iconpath) { icon = img }
                        else if let img = UIImage(contentsOfFile: iconpath + "@2x.png") { icon = img }
                        else if let img = UIImage(contentsOfFile: iconpath + ".png") { icon = img }
                    }

                    let encResult = is_encrypted(fullAppPath, executable)
                    let status: decryptstatus
                    if encResult > 0 { status = .encrypted }
                    else if encResult == 0 { status = .unencrypted }
                    else { status = .unknown }

                    results.append(decryptapp(
                        name: name, bundleid: bundleid, bundlepath: fullAppPath,
                        executable: executable,
                        icon: icon ?? UIImage(named: "unknown"),
                        isencrypted: status
                    ))
                    break
                }
            }

            results.sort { $0.name.lowercased() < $1.name.lowercased() }
            DispatchQueue.main.async { apps = results }
        }
    }

    func startdecrypt(_ app: decryptapp) {
        guard decryptingbid == nil && pendingdecrypt == nil else { return }
        guard mgr.dsready else { errormsg = "Darksword not ready, run the exploit first."; return }
        guard mgr.sbxready else { errormsg = "Sandbox not escaped."; return }

        let appurl = URL(fileURLWithPath: app.bundlepath)
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: appurl, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let furi as URL in enumerator {
                if let fs = (try? furi.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                    total += Int64(fs)
                }
            }
        }
        if total > 200 * 1024 * 1024 {
            Alertinator.shared.alert(
                title: "Large App",
                body: "This app is over 200 MB, decryption may take a while.",
                actionLabel: "Continue",
                action: { self.rundecrypt(app) }
            )
            return
        }
        rundecrypt(app)
    }

    func rundecrypt(_ app: decryptapp) {
        errormsg = nil
        decryptingbid = app.bundleid

        let pid = find_process_pid(app.executable)
        if pid > 0 {
            dodecrypt(app, pid: pid)
        } else {
            pendingdecrypt = app

            var bgTask: UIBackgroundTaskIdentifier = .invalid
            bgTask = UIApplication.shared.beginBackgroundTask(withName: "AutoResumeDecrypt") {
                UIApplication.shared.endBackgroundTask(bgTask)
            }

            let ret = launch_app(app.bundleid)
            guard ret == 0 else {
                UIApplication.shared.endBackgroundTask(bgTask)
                pendingdecrypt = nil
                decryptingbid = nil
                errormsg = "Could not launch app. Open it manually."
                return
            }

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2.5) {
                launch_app(Bundle.main.bundleIdentifier!)
                usleep(500000)

                if self.pendingdecrypt != nil {
                    self.pendingdecrypt = nil
                    let foundPid = find_process_pid(app.executable)
                    if foundPid > 0 {
                        DispatchQueue.main.async {
                            self.dodecrypt(app, pid: foundPid)
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.decryptingbid = nil
                            self.errormsg = "Process not found after launch. Try manually."
                        }
                    }
                }

                DispatchQueue.main.async {
                    UIApplication.shared.endBackgroundTask(bgTask)
                }
            }
        }
    }

    func dodecrypt(_ app: decryptapp, pid: pid_t) {
        let appName = (app.bundlepath as NSString).lastPathComponent
        let ipaName = app.name
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .appending(".ipa")
        let workDir = documentspath + "/Decrypted/.tmp_" + app.bundleid
        let destAppPath = workDir + "/" + appName
        let payloadDir = workDir + "/Payload"
        let payloadAppPath = payloadDir + "/" + appName
        let ipaPath = documentspath + "/Decrypted/" + ipaName

        laramgr.shared.logmsg("(decrypt) decrypting \(app.bundleid)...")

        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default

            try? fm.removeItem(atPath: workDir)
            try? fm.createDirectory(atPath: payloadDir, withIntermediateDirectories: true)

            cpdir(app.bundlepath, destAppPath)
            var dstSt = stat()
            guard stat(destAppPath, &dstSt) == 0 else {
                DispatchQueue.main.async {
                    decryptingbid = nil
                    errormsg = "Failed to copy bundle, some files may be inaccessible."
                    laramgr.shared.logmsg("(decrypt) copy failed: could not copy \(app.bundlepath)")
                }
                return
            }

            let mainBinary = destAppPath + "/" + app.executable
            let mainRet = decrypt_binary_pid((app.bundlepath + "/" + app.executable), pid, mainBinary)
            guard mainRet == 0 else {
                DispatchQueue.main.async {
                    decryptingbid = nil
                    errormsg = "Failed to decrypt main binary"
                    laramgr.shared.logmsg("(decrypt) main binary decrypt failed")
                }
                return
            }

            let srcFrameworks = app.bundlepath + "/Frameworks"
            var srcFwSt = stat()
            if stat(srcFrameworks, &srcFwSt) == 0 {
                let frameworksPath = destAppPath + "/Frameworks"
                let frameworks = (try? fm.contentsOfDirectory(atPath: frameworksPath)) ?? []
                for fw in frameworks where fw.hasSuffix(".framework") {
                    let fwName = (fw as NSString).deletingPathExtension
                    let fwBinary = frameworksPath + "/" + fw + "/" + fwName
                    if !fm.fileExists(atPath: fwBinary) { continue }
                    if is_encrypted_path(fwBinary) > 0 {
                        let fwRet = decrypt_binary_pid(fwBinary, pid, fwBinary)
                        if fwRet != 0 {
                            laramgr.shared.logmsg("(decrypt) framework \(fwName) decrypt failed")
                        }
                    }
                }
            }

            do {
                try fm.moveItem(atPath: destAppPath, toPath: payloadAppPath)
            } catch {
                DispatchQueue.main.async {
                    decryptingbid = nil
                    errormsg = "Failed to move app bundle: \(error.localizedDescription)"
                    laramgr.shared.logmsg("(decrypt) move failed: \(error.localizedDescription)")
                }
                return
            }

            do {
                try createZipArchive(
                    fromDirectory: URL(fileURLWithPath: workDir, isDirectory: true),
                    to: URL(fileURLWithPath: ipaPath)
                )
            } catch {
                DispatchQueue.main.async {
                    decryptingbid = nil
                    errormsg = "Failed to create ipa: \(error.localizedDescription)"
                    laramgr.shared.logmsg("(decrypt) zip failed: \(error.localizedDescription)")
                }
                return
            }

            try? fm.removeItem(atPath: workDir)

            DispatchQueue.main.async {
                decryptingbid = nil
                laramgr.shared.logmsg("(decrypt) ipa saved to \(ipaPath)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    presentShareSheet(with: URL(fileURLWithPath: ipaPath))
                }
            }
        }
    }
}

struct AppRow: View {
    let app: decryptapp
    let isdecrypting: Bool
    let ondecrypt: () -> Void

    var body: some View {
        HStack {
            if let icon = app.icon {
                Image(uiImage: icon)
                    .resizable().frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            } else {
                Image("unknown")
                    .resizable().frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.headline)
                Text(app.bundleid).font(.caption).foregroundColor(.gray)
                HStack(spacing: 4) {
                    switch app.isencrypted {
                    case .encrypted:
                        Text("Encrypted").font(.caption2).foregroundStyle(.orange)
                    case .unencrypted:
                        Text("Unencrypted").font(.caption2).foregroundStyle(.green)
                    case .unknown:
                        Text("Not eligible").font(.caption2).foregroundStyle(.gray)
                    }
                }
            }

            Spacer()

            switch app.isencrypted {
            case .encrypted:
                Button(action: ondecrypt) {
                    if isdecrypting { ProgressView() }
                    else { Text("Decrypt") }
                }
                .disabled(isdecrypting)
            case .unknown:
                Button(action: ondecrypt) {
                    if isdecrypting { ProgressView() }
                    else { Text("Decrypt") }
                }
                .disabled(true)
            case .unencrypted:
                Image(systemName: "checkmark.circle").foregroundColor(.green)
            }
        }
        .opacity(isdecrypting ? 0.6 : 1.0)
    }
}

func cpdir(_ src: String, _ dst: String) {
    var isDir = ObjCBool(false)
    let exists = FileManager.default.fileExists(atPath: src, isDirectory: &isDir)

    if exists, !isDir.boolValue {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: src)) else { return }
        defer { try? handle.close() }
        let data: Data
        if #available(iOS 13.4, *) {
            guard let d = try? handle.readToEnd() else { return }
            data = d
        } else {
            data = handle.readDataToEndOfFile()
        }
        try? data.write(to: URL(fileURLWithPath: dst), options: .atomic)
        return
    }

    guard exists, isDir.boolValue else { return }
    try? FileManager.default.createDirectory(atPath: dst, withIntermediateDirectories: true)

    guard let items = try? FileManager.default.contentsOfDirectory(atPath: src) else { return }
    for item in items {
        cpdir(src + "/" + item, dst + "/" + item)
    }
}
