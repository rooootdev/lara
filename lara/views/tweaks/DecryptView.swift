//
//  DecryptView.swift
//  lara
//
//  Created by neonmodder123 on 23.05.26.
//

import SwiftUI

extension Notification.Name {
    static let laraDecryptProgress = Notification.Name("lara.decrypt.progress")
}

// C function-pointer callbacks cannot capture `self`, so the page progress
// travels through a global. The C callback runs on a background queue while
// SwiftUI reads it on main, hence the lock.
private var latestPageProgress: Double = 0.0
private let pageProgressLock = NSLock()

// Overall progress is split into phases. The C callback only knows about the
// page loop, so copy and pack get their own slices of the bar.
private let kDecryptPhaseStart = 0.35
private let kDecryptPhaseSpan  = 0.50
private let kPackPhaseStart    = 0.85
private let kPackPhaseSpan     = 0.14

struct DecryptApp: Identifiable {
    let id = UUID()
    let name: String
    let bundleID: String
    let bundlePath: String
    let executable: String
    let icon: UIImage?
    var isEncrypted: DecryptStatus = .unknown
}

enum DecryptStatus {
    case encrypted, unencrypted, unknown
}

struct DecryptView: View {
    @ObservedObject private var mgr = laramgr.shared
    @State private var query = ""
    @State private var apps: [DecryptApp] = []
    @State private var decryptingbid: String? = nil
    @State private var errormsg: String? = nil
    @State private var pendingdecrypt: DecryptApp? = nil
    @State private var decryptProgress: Double = 0.0
    @State private var appSizeBytes: Int64 = 0
    @State private var stageText: String = ""

    // Always hop to main before touching @State. NotificationCenter.Publisher
    // delivers on the posting thread, so a background post would mutate
    // @State off-main: SwiftUI would not repaint until the very last main
    // thread refresh, which looked like "jumps straight to 100%".
    private func setStage(_ text: String, _ value: Double? = nil) {
        DispatchQueue.main.async {
            self.stageText = text
            if let v = value {
                self.decryptProgress = max(self.decryptProgress, min(v, 1.0))
            }
        }
    }

    private let documentspath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""

    private var filteredapps: [DecryptApp] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return apps }
        let q = trimmed.lowercased()
        return apps.filter { $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q) }
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
                    Button(action: loadApps) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(!mgr.sbxready || decryptingbid != nil)
                }

                if decryptingbid != nil {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(stageText.isEmpty ? "Preparing..." : stageText)
                                Spacer()
                                Text("\(Int(decryptProgress * 100))%")
                                    .monospacedDigit()
                            }
                            .font(.caption).foregroundColor(.secondary)
                            ProgressView(value: decryptProgress)
                            if appSizeBytes > 200 * 1024 * 1024 {
                                Text(String(format: "%.2f GB app — keep lara in the foreground, screen unlocked, device charging.", Double(appSizeBytes) / 1024 / 1024 / 1024))
                                    .font(.caption2).foregroundColor(.orange)
                            }
                        }
                    } header: { Text("Progress") }
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
                            AppRow(app: app, isdecrypting: decryptingbid == app.bundleID) {
                                startDecrypt(app)
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
            set_progress_callback { p in
                pageProgressLock.lock()
                latestPageProgress = p
                pageProgressLock.unlock()
                // Post on main: Combine's NotificationCenter.Publisher emits
                // synchronously on whatever thread called post().
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .laraDecryptProgress, object: nil)
                }
            }
            if mgr.sbxready { loadApps() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .laraDecryptProgress)) { _ in
            // Ignore page callbacks that arrive late, after packing started.
            guard decryptProgress < kPackPhaseStart else { return }
            pageProgressLock.lock()
            let p = latestPageProgress
            pageProgressLock.unlock()
            stageText = "Decrypting binary..."
            // Framework binaries restart the C progress at 0, so keep the
            // bar monotonic instead of letting it jump backwards.
            decryptProgress = max(decryptProgress,
                                  kDecryptPhaseStart + p * kDecryptPhaseSpan)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            if let app = pendingdecrypt {
                pendingdecrypt = nil
                let pid = find_process_pid(app.executable)
                if pid > 0 {
                    doDecrypt(app, pid: pid)
                } else {
                    errormsg = "App is not running, try again."
                    decryptingbid = nil
                }
            }
        }
        .onChange(of: mgr.sbxready) { ready in
            if ready { loadApps() } else { apps.removeAll() }
        }
    }

    func loadApps() {
        guard mgr.sbxready else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [DecryptApp] = []
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
                    let status: DecryptStatus
                    if encResult > 0 { status = .encrypted }
                    else if encResult == 0 { status = .unencrypted }
                    else { status = .unknown }

                    results.append(DecryptApp(
                        name: name, bundleID: bundleid, bundlePath: fullAppPath,
                        executable: executable,
                        icon: icon ?? UIImage(named: "unknown"),
                        isEncrypted: status
                    ))
                    break
                }
            }

            results.sort { $0.name.lowercased() < $1.name.lowercased() }
            DispatchQueue.main.async { apps = results }
        }
    }

    func startDecrypt(_ app: DecryptApp) {
        guard decryptingbid == nil && pendingdecrypt == nil else { return }
        guard mgr.dsready else { errormsg = "Darksword not ready, run the exploit first."; return }
        guard mgr.sbxready else { errormsg = "Sandbox not escaped."; return }

        // Enumerating a multi-GB bundle can take many seconds on the main
        // thread and gets the app killed by the 0x8badf00d watchdog. Do it in
        // the background, then hop back for the alert.
        decryptingbid = app.bundleID
        errormsg = nil
        decryptProgress = 0.0
        stageText = "Scanning app size..."
        pageProgressLock.lock()
        latestPageProgress = 0.0
        pageProgressLock.unlock()
        let appurl = URL(fileURLWithPath: app.bundlePath)
        DispatchQueue.global(qos: .userInitiated).async {
            var total: Int64 = 0
            if let enumerator = FileManager.default.enumerator(at: appurl, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let furi as URL in enumerator {
                    if let fs = (try? furi.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                        total += Int64(fs)
                    }
                }
            }
            DispatchQueue.main.async {
                self.appSizeBytes = total
                self.runDecrypt(app)
            }
        }
    }

    func runDecrypt(_ app: DecryptApp) {
        errormsg = nil
        decryptingbid = app.bundleID

        let pid = find_process_pid(app.executable)
        if pid > 0 {
            doDecrypt(app, pid: pid)
        } else {
            pendingdecrypt = app

            var bgTask: UIBackgroundTaskIdentifier = .invalid
            bgTask = UIApplication.shared.beginBackgroundTask(withName: "AutoResumeDecrypt") {
                UIApplication.shared.endBackgroundTask(bgTask)
            }

            let ret = launch_app(app.bundleID)
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
                            self.doDecrypt(app, pid: foundPid)
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

    func doDecrypt(_ app: DecryptApp, pid: pid_t) {
        let appName = (app.bundlePath as NSString).lastPathComponent
        let ipaName = app.name
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .appending(".ipa")
        let workDir = documentspath + "/Decrypted/.tmp_" + app.bundleID
        let destAppPath = workDir + "/" + appName
        let payloadDir = workDir + "/Payload"
        let payloadAppPath = payloadDir + "/" + appName
        let ipaPath = documentspath + "/Decrypted/" + ipaName

        laramgr.shared.logmsg("(decrypt) decrypting \(app.bundleID)...")
        laramgr.shared.logmsg("(decrypt) work dir: \(workDir)")
        stageText = "Copying bundle..."

        // The old code's only background task was the 3-second "relaunch me"
        // one, so the long job ran with no assertion and got suspended as soon
        // as the screen locked / the user switched away.
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "AppDecrypt") {
            UIApplication.shared.endBackgroundTask(bgTask)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            defer {
                DispatchQueue.main.async {
                    UIApplication.shared.endBackgroundTask(bgTask)
                }
            }
            let fm = FileManager.default

            if let values = try? URL(fileURLWithPath: documentspath)
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
               let free = values.volumeAvailableCapacityForImportantUsage {
                let needed = Int64(appSizeBytes) * 3   // copy + IPA + headroom
                laramgr.shared.logmsg(String(format: "(decrypt) free space %.2f GiB, want ~%.2f GiB",
                                             Double(free) / 1024 / 1024 / 1024,
                                             Double(needed) / 1024 / 1024 / 1024))
                if free < needed {
                    laramgr.shared.logmsg("(decrypt) WARNING: low disk space, output may be truncated")
                }
            }

            laramgr.shared.logmsg("(decrypt) existing work dir (if any) will be removed: \(workDir)")
            try? fm.removeItem(atPath: workDir)
            try? fm.createDirectory(atPath: payloadDir, withIntermediateDirectories: true)

            guard let enumerator = fm.enumerator(atPath: app.bundlePath) else {
                DispatchQueue.main.async {
                    decryptingbid = nil
                    errormsg = "Failed to enumerate bundle for copy"
                    laramgr.shared.logmsg("(decrypt) cannot enumerate \(app.bundlePath)")
                }
                return
            }

            var copyFailures = 0
            var copiedBytes: Int64 = 0
            var lastCopyReport: Int64 = 0
            let copyTotal = max(Double(appSizeBytes), 1.0)
            for case let subpath as String in enumerator {
                let src = (app.bundlePath as NSString).appendingPathComponent(subpath)
                let dst = (destAppPath as NSString).appendingPathComponent(subpath)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: src, isDirectory: &isDir) else { continue }
                do {
                    if isDir.boolValue {
                        try fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
                    } else {
                        try fm.copyItem(atPath: src, toPath: dst)
                        if let sz = (try? fm.attributesOfItem(atPath: dst)[.size]) as? NSNumber {
                            copiedBytes += sz.int64Value
                        }
                    }
                } catch {
                    copyFailures += 1
                    if copyFailures <= 5 {
                        laramgr.shared.logmsg("(decrypt) copy failed for \(subpath): \(error.localizedDescription)")
                    }
                }
                if copiedBytes - lastCopyReport >= 32 * 1024 * 1024 {
                    lastCopyReport = copiedBytes
                    let frac = min(Double(copiedBytes) / copyTotal, 1.0)
                    self.setStage("Copying bundle...", kDecryptPhaseStart * frac)
                }
            }
            if copyFailures > 0 {
                laramgr.shared.logmsg("(decrypt) WARNING: \(copyFailures) files failed to copy; IPA will be incomplete")
            }

            self.setStage("Decrypting binary...", kDecryptPhaseStart)
            let mainBinary = destAppPath + "/" + app.executable
            let mainRet = decrypt_binary_pid((app.bundlePath + "/" + app.executable), pid, mainBinary)
            guard mainRet == 0 else {
                DispatchQueue.main.async {
                    decryptingbid = nil
                    errormsg = "Failed to decrypt main binary"
                    laramgr.shared.logmsg("(decrypt) main binary decrypt failed")
                }
                return
            }

            let srcFrameworks = app.bundlePath + "/Frameworks"
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

            self.setStage("Packing IPA...", kPackPhaseStart)
            do {
                try createZipArchiveStreaming(
                    fromDirectory: URL(fileURLWithPath: workDir, isDirectory: true),
                    to: URL(fileURLWithPath: ipaPath),
                    progress: { frac in
                        self.setStage("Packing IPA...",
                                      kPackPhaseStart + frac * kPackPhaseSpan)
                    }
                )
            } catch {
                // Deliberately keep workDir: Payload/ already contains the
                // decrypted binary, so it can be zipped off-device instead.
                DispatchQueue.main.async {
                    decryptingbid = nil
                    errormsg = "Failed to create ipa: \(error.localizedDescription)"
                    laramgr.shared.logmsg("(decrypt) zip failed: \(error.localizedDescription)")
                    laramgr.shared.logmsg("(decrypt) decrypted bundle preserved at \(payloadDir)")
                }
                return
            }

            try? fm.removeItem(atPath: workDir)
            self.setStage("Done", 1.0)

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
    let app: DecryptApp
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
                Text(app.bundleID).font(.caption).foregroundColor(.gray)
                HStack(spacing: 4) {
                    switch app.isEncrypted {
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

            switch app.isEncrypted {
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


