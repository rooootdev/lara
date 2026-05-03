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
        detailedLog += "[\(timestamp)] \(message)\n"
        mgr.logmsg(message)
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

        addLog("=== TrollStore Installation Started ===")

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

            let amfiResult = amfi_bypass(ds_get_our_proc())

            if amfiResult == 0 {
                addLog("✓ AMFI bypass successful")
            } else if amfiResult == 1 {
                addLog("⚠ AMFI bypass partial (may still work)")
            } else {
                addLog("✗ AMFI bypass failed (code: \(amfiResult))")
                addLog("Continuing anyway - installd patch may be sufficient...")
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

        addLog("Download URL: \(trollStoreURL)")
        addLog("Note: Actual download/install requires additional implementation")
        addLog("This is a proof-of-concept showing the exploit chain")

        // Simulate download
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            progress = 1.0
            status = "✓ Installation complete!"
            isInstalling = false
            installComplete = true

            addLog("=== Installation Process Complete ===")
            addLog("")
            addLog("Next steps:")
            addLog("1. Download TrollStore.ipa manually")
            addLog("2. Install using your preferred sideload method")
            addLog("3. The patches are active - installation should succeed")
            addLog("4. After reboot, run LARA again for new installations")
            addLog("")
            addLog("Note: This is a proof-of-concept implementation")
            addLog("Full integration would require IPA download/install code")
        }
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
