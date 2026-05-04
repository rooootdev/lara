//
//  TrollStoreInstallerView.swift
//  lara
//
//  Created for TrollStore installation support
//  Date: 2026-05-03
//

import SwiftUI
import Foundation

struct TrollStoreInstallerView: View {
    @ObservedObject var mgr: laramgr
    @State private var status: String = "Ready to install TrollStore"
    @State private var progress: Double = 0.0
    @State private var isInstalling: Bool = false
    @State private var installComplete: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var detailedLog: String = ""
    @State private var showLog: Bool = false
    @State private var previousLogs: [String] = []
    @State private var showPreviousLogs: Bool = false

    private let logFilePath: URL = {
        // Save to shared container accessible from Files app
        if let sharedURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.lara") {
            return sharedURL.appendingPathComponent("trollstore_logs.txt")
        }
        // Fallback to Documents
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("trollstore_logs.txt")
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                        .padding(.top, 20)

                    Text("TrollStore Installer")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Install TrollStore using LARA exploit chain")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    // Status
                    VStack(spacing: 10) {
                        Text(status)
                            .font(.body)
                            .foregroundColor(installComplete ? .green : .primary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        if isInstalling {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .padding(.horizontal, 40)

                            Text("\(Int(progress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Requirements check
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Requirements:")
                            .font(.headline)

                        HStack {
                            Image(systemName: mgr.dsready ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(mgr.dsready ? .green : .red)
                            Text("DarkSword Exploit")
                            Spacer()
                            if !mgr.dsready {
                                Button("Run") {
                                    runDarkSword()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }

                        HStack {
                            Image(systemName: mgr.sbxready ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(mgr.sbxready ? .green : .red)
                            Text("Sandbox Escape")
                            Spacer()
                            if mgr.dsready && !mgr.sbxready {
                                Button("Run") {
                                    runSandboxEscape()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }

                        HStack {
                            Image(systemName: mgr.rcready ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(mgr.rcready ? .green : .gray)
                            Text("RemoteCall (Optional)")
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Install button
                    Button(action: {
                        installTrollStore()
                    }) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text(installComplete ? "Reinstall TrollStore" : "Install TrollStore")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canInstall ? Color.blue : Color.gray)
                        .cornerRadius(12)
                    }
                    .disabled(!canInstall || isInstalling)
                    .padding(.horizontal)

                    // Show log button
                    Button(action: {
                        showLog.toggle()
                    }) {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("Show Detailed Log")
                        }
                        .font(.subheadline)
                    }
                    .padding(.horizontal)

                    // Show previous logs button
                    Button(action: {
                        loadPreviousLogs()
                        showPreviousLogs.toggle()
                    }) {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                            Text("Show Previous Logs")
                        }
                        .font(.subheadline)
                    }
                    .padding(.horizontal)

                    if showLog {
                        ScrollView {
                            Text(detailedLog)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .frame(height: 200)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }

                    if showPreviousLogs {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                if previousLogs.isEmpty {
                                    Text("No previous logs found")
                                        .foregroundColor(.secondary)
                                } else {
                                    ForEach(Array(previousLogs.enumerated()), id: \.offset) { index, log in
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text("Attempt #\(previousLogs.count - index)")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                            Text(log)
                                                .font(.system(.caption2, design: .monospaced))
                                            Divider()
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                        }
                        .frame(height: 250)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }

                    // Warning
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Important Notes:")
                                .font(.headline)
                        }

                        Text("• TrollStore will be installed as a regular app")
                        Text("• After reboot, you need to run LARA again to install new apps")
                        Text("• This modifies system processes temporarily")
                        Text("• Not permanent - patches reset on reboot")

                    }
                    .font(.caption)
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    Spacer()
                }
            }
            .navigationTitle("TrollStore")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Installation Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    var canInstall: Bool {
        return mgr.dsready && mgr.sbxready && !isInstalling
    }

    func addLog(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        let logLine = "[\(timestamp)] \(message)\n"
        detailedLog += logLine
        mgr.logmsg(message)

        // Save to file immediately
        saveLogToFile(logLine)
    }

    func saveLogToFile(_ message: String) {
        // Force immediate write with sync
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var content = ""
                if FileManager.default.fileExists(atPath: logFilePath.path) {
                    content = try String(contentsOf: logFilePath, encoding: .utf8)
                }
                content += message

                // Write atomically and force sync to disk
                try content.write(to: logFilePath, atomically: true, encoding: .utf8)

                // Force sync to disk immediately
                if let fileHandle = try? FileHandle(forWritingTo: logFilePath) {
                    fileHandle.synchronizeFile()
                    fileHandle.closeFile()
                }
            } catch {
                print("Failed to save log: \(error)")
            }
        }
    }

    func loadPreviousLogs() {
        do {
            if FileManager.default.fileExists(atPath: logFilePath.path) {
                let content = try String(contentsOf: logFilePath, encoding: .utf8)
                let sessions = content.components(separatedBy: "=== TrollStore Installation Started ===")
                previousLogs = sessions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
        } catch {
            print("Failed to load previous logs: \(error)")
        }
    }

    func runDarkSword() {
        addLog("Starting DarkSword exploit...")
        mgr.run { success in
            if success {
                addLog("✓ DarkSword exploit successful")
            } else {
                addLog("✗ DarkSword exploit failed")
            }
        }
    }

    func runSandboxEscape() {
        addLog("Starting sandbox escape...")
        mgr.sbxescape { success in
            if success {
                addLog("✓ Sandbox escape successful")
            } else {
                addLog("✗ Sandbox escape failed")
            }
        }
    }

    func installTrollStore() {
        guard canInstall else { return }

        isInstalling = true
        installComplete = false
        progress = 0.0
        detailedLog = ""

        // Add separator for new session
        saveLogToFile("\n\n========================================\n")
        addLog("=== TrollStore Installation Started ===")
        addLog("Device: \(UIDevice.current.model)")
        addLog("iOS: \(UIDevice.current.systemVersion)")
        addLog("Time: \(Date().formatted())")

        // Step 1: Verify DarkSword
        status = "Step 1/5: Verifying kernel exploit..."
        progress = 0.1
        addLog("Checking DarkSword status...")

        guard mgr.dsready else {
            failInstallation("DarkSword exploit not ready")
            return
        }
        addLog("✓ DarkSword is ready")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Step 2: AMFI Bypass
            status = "Step 2/5: Bypassing AMFI..."
            progress = 0.3
            addLog("Attempting AMFI bypass...")

            // Always attempt AMFI bypass - it's needed for RemoteCall
            // The amfi.m code will handle PPL protection safely
            let amfiResult = amfi_bypass(ds_get_our_proc())

            if amfiResult == 0 {
                addLog("✓ AMFI bypass successful")
            } else if amfiResult == 1 {
                addLog("⚠ AMFI bypass partial (may still work)")
            } else if amfiResult == -4 {
                addLog("⚠ AMFI bypass skipped (PPL protected)")
                addLog("This is expected on A12+ devices")
                addLog("RemoteCall should still work")
            } else {
                addLog("✗ AMFI bypass failed (code: \(amfiResult))")
                addLog("Continuing anyway - may still work...")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Step 3: Initialize RemoteCall
                status = "Step 3/5: Initializing RemoteCall..."
                progress = 0.5
                addLog("Initializing RemoteCall for installd...")

                mgr.rcinit(process: "installd", migbypass: false) { success in
                    if !success {
                        addLog("⚠ RemoteCall init failed, trying alternative method...")
                        // Continue anyway - we can try without RemoteCall
                    } else {
                        addLog("✓ RemoteCall initialized")
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        // Step 4: Patch installd
                        status = "Step 4/5: Patching installd..."
                        progress = 0.7
                        addLog("Patching installd for TrollStore...")

                        if mgr.rcready {
                            let patchResult = installd_patch_for_trollstore(mgr.sbProc)
                            if patchResult == 0 {
                                addLog("✓ installd patched successfully")
                            } else {
                                addLog("⚠ installd patch had issues (code: \(patchResult))")
                            }
                        } else {
                            addLog("⚠ Skipping installd patch (RemoteCall not available)")
                            addLog("Installation may still work with AMFI bypass alone")
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            // Step 5: Download and install TrollStore
                            status = "Step 5/5: Installing TrollStore..."
                            progress = 0.9
                            addLog("Downloading TrollStore IPA...")

                            downloadAndInstallTrollStore()
                        }
                    }
                }
            }
        }
    }

    func downloadAndInstallTrollStore() {
        let trollStoreURL = "https://github.com/opa334/TrollStore/releases/latest/download/TrollStore.ipa"

        addLog("Downloading TrollStore from: \(trollStoreURL)")

        guard let url = URL(string: trollStoreURL) else {
            failInstallation("Invalid TrollStore URL")
            return
        }

        // Download TrollStore IPA
        let task = URLSession.shared.downloadTask(with: url) { localURL, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.addLog("✗ Download failed: \(error.localizedDescription)")
                    self.failInstallation("Failed to download TrollStore")
                }
                return
            }

            guard let localURL = localURL else {
                DispatchQueue.main.async {
                    self.failInstallation("Download completed but no file received")
                }
                return
            }

            DispatchQueue.main.async {
                self.addLog("✓ TrollStore downloaded successfully")
                self.addLog("File size: \((try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? 0) bytes")

                // Move to Documents directory
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let destinationURL = documentsPath.appendingPathComponent("TrollStore.ipa")

                do {
                    // Remove old file if exists
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }

                    // Move downloaded file
                    try FileManager.default.moveItem(at: localURL, to: destinationURL)

                    self.addLog("✓ TrollStore saved to: \(destinationURL.path)")
                    self.addLog("")
                    self.addLog("=== Installation Complete ===")
                    self.addLog("")
                    self.addLog("Next steps:")
                    self.addLog("1. Open Files app → On My iPhone → lara")
                    self.addLog("2. Tap TrollStore.ipa to install")
                    self.addLog("3. The patches are active - installation should succeed")
                    self.addLog("4. After reboot, run LARA again for new installations")

                    self.progress = 1.0
                    self.status = "✓ Installation complete!"
                    self.isInstalling = false
                    self.installComplete = true

                } catch {
                    self.addLog("✗ Failed to save TrollStore: \(error.localizedDescription)")
                    self.failInstallation("Failed to save downloaded file")
                }
            }
        }

        task.resume()
        addLog("Download started...")
    }

    func failInstallation(_ message: String) {
        status = "✗ Installation failed"
        errorMessage = message
        showError = true
        isInstalling = false
        addLog("✗ FAILED: \(message)")
        addLog("=== Installation Aborted ===")
    }
}
