import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RecordView: View {
    @ObservedObject var mgr: laramgr

    @State private var disabled = false
    @State private var isOverwriting = false

    private let target1 = "/var/mobile/Library/CallServices/Greetings/default/StartDisclosureWithTone.m4a"
    private let target2 = "/var/mobile/Library/CallServices/Greetings/default/StopDisclosure.caf"

    // MARK: - Remote Download URLs
    private let remote1 = URL(string:
        "https://github.com/YangJiiii/Disable-Call-Recording-BookRestore-/raw/refs/heads/main/Sounds/StartDisclosureWithTone.m4a"
    )!

    private let remote2 = URL(string:
        "https://github.com/YangJiiii/Disable-Call-Recording-BookRestore-/raw/refs/heads/main/Sounds/StopDisclosure.caf"
    )!

    var body: some View {
        List {

            Section(header: HeaderLabel(text: "Status", icon: "info.circle")) {
                HStack {
                    Text("Status")
                    Spacer()

                    Text(disabled ? "Disabled" : "Enabled")
                        .foregroundColor(disabled ? .red : .green)
                        .monospaced()
                }
            }

            Section(header: HeaderLabel(text: "Actions", icon: "hammer")) {

                Button("Disable") {
                    disableRecordNotify()
                }
                .disabled(disabled || isOverwriting)

                Button("Enable") {
                    enableRecordNotify()
                }
                .disabled(isOverwriting)
            }

            // MARK: - NEW DOWNLOAD SECTION
            Section(header: HeaderLabel(text: "Download", icon: "arrow.down.circle")) {

                Button("Download Sounds") {
                    downloadSounds()
                }
                .disabled(isOverwriting)
            }
        }
        .navigationTitle("Call Record Notification")
        .onAppear {
            downloadIfNeeded()
            check()
        }
    }

    // MARK: - Documents Paths

    private var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var local1: URL {
        documents.appendingPathComponent("StartDisclosurewithTone.m4a")
    }

    private var local2: URL {
        documents.appendingPathComponent("StopDisclosure.caf")
    }

    // MARK: - Status Check

    private func check() {
        guard
            let attrs1 = try? FileManager.default.attributesOfItem(atPath: target1),
            let attrs2 = try? FileManager.default.attributesOfItem(atPath: target2),
            let size1 = attrs1[.size] as? NSNumber,
            let size2 = attrs2[.size] as? NSNumber
        else {
            disabled = false
            return
        }

        disabled = size1.intValue < 2048 || size2.intValue < 2048
    }

    // MARK: - DOWNLOAD SYSTEM

    private func downloadIfNeeded() {
        let fm = FileManager.default

        if !fm.fileExists(atPath: local1.path) {
            download(remote1, to: local1)
        }

        if !fm.fileExists(atPath: local2.path) {
            download(remote2, to: local2)
        }
    }

    private func downloadSounds() {
        isOverwriting = true

        let group = DispatchGroup()

        group.enter()
        download(remote1, to: local1) { group.leave() }

        group.enter()
        download(remote2, to: local2) { group.leave() }

        group.notify(queue: .main) {
            self.isOverwriting = false
            self.mgr.logmsg("Sounds downloaded")
            self.check()
        }
    }

    private func download(_ url: URL, to dest: URL, completion: (() -> Void)? = nil) {
        URLSession.shared.downloadTask(with: url) { tempURL, _, error in

            defer { completion?() }

            guard let tempURL = tempURL, error == nil else {
                DispatchQueue.main.async {
                    self.mgr.logmsg("Download failed: \(url.lastPathComponent)")
                }
                return
            }

            do {
                let fm = FileManager.default

                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }

                try fm.moveItem(at: tempURL, to: dest)

                DispatchQueue.main.async {
                    self.mgr.logmsg("Downloaded: \(dest.lastPathComponent)")
                }

            } catch {
                DispatchQueue.main.async {
                    self.mgr.logmsg("File error: \(error.localizedDescription)")
                }
            }
        }.resume()
    }

    // MARK: - Backup Creation

    private func createBackupsIfNeeded() {
        let fm = FileManager.default

        let backupFolder = documents.appendingPathComponent("Backup")

        let backup1 = backupFolder.appendingPathComponent("StartDisclosurewithTone.m4a")
        let backup2 = backupFolder.appendingPathComponent("StopDisclosure.caf")

        if !fm.fileExists(atPath: backupFolder.path) {
            try? fm.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        }

        if !fm.fileExists(atPath: backup1.path) {
            try? fm.copyItem(at: URL(fileURLWithPath: target1), to: backup1)
        }

        if !fm.fileExists(atPath: backup2.path) {
            try? fm.copyItem(at: URL(fileURLWithPath: target2), to: backup2)
        }
    }

    // MARK: - Overwrite

    @discardableResult
    private func overwrite(target: String, source: String) -> Bool {
        let ok = mgr.vfsoverwritefromlocalpath(target: target, source: source)

        mgr.logmsg(ok ? "overwrite ok: \(target)" : "overwrite failed: \(target)")
        return ok
    }

    // MARK: - Disable

    private func disableRecordNotify() {
        isOverwriting = true

        DispatchQueue.global(qos: .userInitiated).async {

            self.createBackupsIfNeeded()

            let ok1 = self.overwrite(target: self.target1, source: self.local1.path)
            let ok2 = self.overwrite(target: self.target2, source: self.local2.path)

            DispatchQueue.main.async {
                self.isOverwriting = false
                self.check()

                if !(ok1 && ok2) {
                    self.mgr.logmsg("Failed disabling notification")
                }
            }
        }
    }

    // MARK: - Enable

    private func enableRecordNotify() {
        let fm = FileManager.default

        let backupFolder = documents.appendingPathComponent("Backup")
        let backup1 = backupFolder.appendingPathComponent("StartDisclosurewithTone.m4a")
        let backup2 = backupFolder.appendingPathComponent("StopDisclosure.caf")

        guard
            fm.fileExists(atPath: backup1.path),
            fm.fileExists(atPath: backup2.path)
        else {
            mgr.logmsg("Backups not found")
            return
        }

        isOverwriting = true

        DispatchQueue.global(qos: .userInitiated).async {

            let ok1 = self.overwrite(target: self.target1, source: backup1.path)
            let ok2 = self.overwrite(target: self.target2, source: backup2.path)

            DispatchQueue.main.async {
                self.isOverwriting = false
                self.check()

                if !(ok1 && ok2) {
                    self.mgr.logmsg("Failed restoring notification")
                }
            }
        }
    }
}
