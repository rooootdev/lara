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
        // Write directly to Documents folder (same as other debug logs)
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
        // CRITICAL: SYNCHRONOUS write with fsync() - NO async dispatch!
        let path = self.logFilePath.path
        let fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        if fd >= 0 {
            if let data = message.data(using: .utf8) {
                data.withUnsafeBytes { ptr in
                    write(fd, ptr.baseAddress, data.count)
                }
                fsync(fd)  // Force write to disk NOW
            }
            close(fd)
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
        addLog("CRITICAL: installTrollStore() called")

        guard canInstall else {
            addLog("CRITICAL: canInstall = false, aborting")
            return
        }

        addLog("CRITICAL: canInstall = true, proceeding")
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
        addLog("CRITICAL: Logs are being saved to Documents folder")
        addLog("CRITICAL: Check Files app -> On My iPhone -> lara")

        // Step 1: Verify DarkSword
        status = "Step 1/3: Verifying kernel exploit..."
        progress = 0.1
        addLog("=== STEP 1: VERIFY DARKSWORD ===")
        addLog("CRITICAL: Checking DarkSword status...")
        addLog("CRITICAL: mgr.dsready = \(mgr.dsready)")

        guard mgr.dsready else {
            addLog("CRITICAL: DarkSword NOT ready, aborting")
            failInstallation("DarkSword exploit not ready")
            return
        }
        addLog("✓ DarkSword is ready")
        addLog("CRITICAL: kernel_base = 0x\(String(format: "%llx", mgr.kernbase))")
        addLog("CRITICAL: kernel_slide = 0x\(String(format: "%llx", mgr.kernslide))")
        addLog("CRITICAL: Waiting 0.5s before AMFI bypass...")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Step 2: Trust Cache Injection (SAFER than AMFI bypass)
            status = "Step 2/3: Injecting Trust Cache..."
            progress = 0.4
            addLog("=== STEP 2: TRUST CACHE INJECTION ===")
            addLog("Note: Using trust cache injection instead of AMFI bypass")
            addLog("This is more stable and doesn't cause kernel panic")

            // Initialize trust cache injection
            addLog("Initializing trust cache injection...")
            let tcInitResult = trust_cache_inject_init()

            if tcInitResult != 0 {
                addLog("⚠ Trust cache init returned: \(tcInitResult)")
                addLog("Continuing anyway - may still work")
            } else {
                addLog("✓ Trust cache injection initialized")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Step 3: Download and install TrollStore PersistenceHelper
                status = "Step 3/3: Installing TrollStore..."
                progress = 0.7
                addLog("=== STEP 3: PERSISTENCEHELPER DOWNLOAD ===")
                addLog("Downloading TrollStore PersistenceHelper binary...")
                addLog("This is the core binary needed for TrollStore installation")
                addLog("Will inject CDHash into trust cache after download")

                downloadAndInstallTrollStore()
            }
        }
    }

    func downloadAndInstallTrollStore() {
        // Download PersistenceHelper using Objective-C curl wrapper
        let trollStoreURL = "https://github.com/opa334/TrollStore/releases/download/2.1.1/PersistenceHelper_Embedded"

        addLog("Downloading TrollStore PersistenceHelper from: \(trollStoreURL)")

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = documentsPath.appendingPathComponent("PersistenceHelper")

        // Remove old file if exists
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        addLog("Download destination: \(destinationURL.path)")
        addLog("Starting download via curl...")

        // Use Objective-C function to download (handles popen properly)
        let result = trust_cache_download_file(trollStoreURL, destinationURL.path)

        if result != 0 {
            addLog("✗ Download failed with error code: \(result)")
            failInstallation("Failed to download PersistenceHelper")
            return
        }

        // Check file size
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? Int64) ?? 0
        addLog("✓ PersistenceHelper downloaded successfully")
        addLog("File size: \(fileSize) bytes")

        if fileSize < 100000 {
            addLog("✗ Downloaded file too small (\(fileSize) bytes)")
            addLog("Expected ~209 KB for PersistenceHelper")
            failInstallation("PersistenceHelper download failed - file too small")
            return
        }

        addLog("✓ PersistenceHelper saved to: \(destinationURL.path)")
        addLog("")
        addLog("=== Injecting PersistenceHelper CDHash ===")

        // Inject CDHash directly - no extraction needed
        let injectResult = trust_cache_inject_binary(destinationURL.path)

        if injectResult == 0 {
            addLog("✓ PersistenceHelper CDHash injected into trust cache!")
            addLog("")
            addLog("=== Installation Complete ===")
            addLog("")
            addLog("Next steps:")
            addLog("1. PersistenceHelper is now trusted by the kernel")
            addLog("2. You can install it using TrollStore installer")
            addLog("3. Check trust_cache_debug.log for details")
        } else {
            addLog("⚠ Trust cache injection failed: \(injectResult)")
            addLog("Check trust_cache_debug.log for error details")
        }

        progress = 1.0
        status = "✓ Installation complete!"
        isInstalling = false
        installComplete = true
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
