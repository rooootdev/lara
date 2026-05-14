//
//  OTAView.swift
//  lara
//
//  Created by hxhlb on 5/14/26.
//

import SwiftUI
import Darwin
import Combine

struct OTAView: View {
    @ObservedObject private var mgr = laramgr.shared

    private enum OTAAction: String, Identifiable {
        case disable
        case enable
        case restoreBackup

        var id: String { rawValue }

        var title: String {
            switch self {
            case .disable: return "Disable OTA Updates"
            case .enable: return "Enable OTA Updates"
            case .restoreBackup: return "Restore OTA Backup"
            }
        }

        var message: String {
            switch self {
            case .disable:
                return "This will disable OTA update daemons by writing them to launchd's disabled.plist. A full device reboot is required."
            case .enable:
                return "This will remove OTA update daemons from launchd's disabled.plist. A full device reboot is required."
            case .restoreBackup:
                return "This will overwrite the system disabled.plist with Lara's local backup. A full device reboot is required."
            }
        }
    }

    private enum OTAState {
        case unknown
        case enabled
        case disabled
        case mixed

        var title: String {
            switch self {
            case .unknown: return "Unknown"
            case .enabled: return "Enabled"
            case .disabled: return "Disabled"
            case .mixed: return "Partially Disabled"
            }
        }
    }

    private let plistPath = "/var/db/com.apple.xpc.launchd/disabled.plist"
    private let darkSwordReferenceURL = URL(string: "https://github.com/kolbicz/DarkSword-Tweaks")!
    private let kfunReferenceURL = URL(string: "https://github.com/zeroxjf/kfun-zeroxjf")!
    private let backupURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("disabled.plist.backup")
    private let otaServices = [
        "com.apple.mobile.softwareupdated",
        "com.apple.OTATaskingAgent",
        "com.apple.softwareupdateservicesd",
        "com.apple.mobile.NRDUpdated",
    ]

    @State private var state: OTAState = .unknown
    @State private var serviceStates: [String: Bool] = [:]
    @State private var status: String?
    @State private var working = false
    @State private var pendingAction: OTAAction?
    @State private var hasBackup = false
    @State private var showOperationSheet = false
    @State private var operationTitle = "OTA Operation"
    @State private var operationLogs: [String] = []
    @State private var launchdRCDeadline: Date?
    @State private var launchdRCRemaining = 0
    @State private var launchdRCDidTimeout = false

    private let launchdRCTimeoutSeconds = 120

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Current State")
                        Spacer()
                        Text(state.title)
                            .foregroundStyle(state == .disabled ? .orange : .secondary)
                    }

                    Button("Refresh Status") {
                        refresh()
                    }
                    .disabled(!mgr.sbxready || working)
                } footer: {
                    Text("Reads \(plistPath). Missing entries mean OTA updates are not disabled by this toggle.")
                }

                Section {
                    Button("Backup disabled.plist") {
                        backup()
                    }
                    .disabled(!mgr.sbxready || working)

                    Button("Restore Backup") {
                        pendingAction = .restoreBackup
                    }
                    .disabled(!mgr.dsready || working || !hasBackup)

                    HStack {
                        Text("Backup")
                        Spacer()
                        Text(hasBackup ? "Available" : "Missing")
                            .foregroundStyle(hasBackup ? Color.secondary : Color.orange)
                    }
                } header: {
                    HeaderLabel(text: "Backup", icon: "externaldrive")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if !mgr.sbxready {
                            Text("Sandbox is not ready. Backup is unavailable until sandbox escape is initialized.")
                        }
                        Text("Backup path: \(backupURL.path)")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        pendingAction = .disable
                    } label: {
                        Text("Disable OTA Updates")
                    }
                    .disabled(!mgr.dsready || working)

                    Button {
                        pendingAction = .enable
                    } label: {
                        Text("Enable OTA Updates")
                    }
                    .disabled(!mgr.dsready || working)
                } header: {
                    HeaderLabel(text: "Actions", icon: "antenna.radiowaves.left.and.right")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("A full device reboot is required after changing this setting. A respring is not enough.")
                        Link("Reference: kolbicz/DarkSword-Tweaks", destination: darkSwordReferenceURL)
                        Link("Reference: zeroxjf/kfun-zeroxjf", destination: kfunReferenceURL)
                    }
                }

                Section {
                    ForEach(otaServices, id: \.self) { service in
                        HStack {
                            Text(service)
                                .font(.system(size: 13, design: .monospaced))
                            Spacer()
                            Text(serviceStates[service] == true ? "Disabled" : "Not Disabled")
                                .foregroundStyle(serviceStates[service] == true ? .orange : .secondary)
                        }
                    }
                } header: {
                    Text("Launchd Services")
                }

                if working {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Working...")
                        }
                    }
                }
            }
            .navigationTitle("OTA Disabler")
            .onAppear {
                refresh()
                refreshBackupState()
            }
            .alert("Status", isPresented: .constant(status != nil)) {
                Button("OK") { status = nil }
            } message: {
                Text(status ?? "")
            }
            .alert(item: $pendingAction) { action in
                Alert(
                    title: Text(action.title),
                    message: Text(confirmMessage(for: action)),
                    primaryButton: .destructive(Text(action.title)) {
                        apply(action)
                    },
                    secondaryButton: .cancel()
                )
            }
            .sheet(isPresented: $showOperationSheet) {
                NavigationStack {
                    List {
                        Section {
                            HStack {
                                if working {
                                    ProgressView()
                                } else {
                                    Image(systemName: "checkmark.circle")
                                        .foregroundStyle(.green)
                                }
                                Text(working ? "Working..." : "Finished")
                            }

                            if launchdRCDeadline != nil && working {
                                HStack {
                                    Text("launchd RC")
                                    Spacer()
                                    Text(launchdRCDidTimeout ? "Still waiting" : "\(launchdRCRemaining)s remaining")
                                        .foregroundStyle(launchdRCDidTimeout ? Color.orange : Color.secondary)
                                }
                                Text(launchdRCDidTimeout ? "RemoteCall creation exceeded the expected 120s window and may be stuck." : "RemoteCall creation can take up to 120 seconds.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Section {
                            ScrollView {
                                Text(operationLogs.joined(separator: "\n"))
                                    .font(.system(size: 13, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(minHeight: 260)
                        } header: {
                            Text("Logs")
                        }
                    }
                    .navigationTitle(operationTitle)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showOperationSheet = false
                            }
                            .disabled(working)
                        }
                    }
                }
                .presentationDetents([.medium, .large])
                .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
                    updateLaunchdRCCountdown(now: now)
                }
            }
        }
    }

    private func confirmMessage(for action: OTAAction) -> String {
        var message = action.message
        if mgr.sbProc != nil || mgr.rcready {
            message += "\n\nA SpringBoard RemoteCall session is currently active. Continuing will temporarily destroy the SpringBoard RemoteCall and switch to launchd. You can re-initialize SpringBoard RemoteCall after this operation."
        }
        return message
    }

    private func refresh() {
        guard mgr.sbxready else {
            state = .unknown
            serviceStates = [:]
            refreshBackupState()
            return
        }

        let plist = readDisabledPlist()
        serviceStates = Dictionary(uniqueKeysWithValues: otaServices.map { service in
            (service, plist[service] as? Bool == true)
        })

        let disabledCount = serviceStates.values.filter { $0 }.count
        if disabledCount == otaServices.count {
            state = .disabled
        } else if disabledCount == 0 {
            state = .enabled
        } else {
            state = .mixed
        }
        refreshBackupState()
    }

    private func apply(_ action: OTAAction) {
        guard mgr.dsready else {
            status = "Darksword is not ready."
            return
        }

        operationTitle = action.title
        operationLogs = []
        showOperationSheet = true
        otaLog("Started \(action.title)")
        clearLaunchdRCCountdown()
        working = true

        DispatchQueue.global(qos: .userInitiated).async {
            let result: Int32
            #if DISABLE_REMOTECALL
            otaLog("RemoteCall is disabled in this build")
            result = ENOTSUP
            #else
            DispatchQueue.main.async {
                otaLog("Switching RemoteCall target to launchd")
            }

            if let sbProc = mgr.sbProc {
                DispatchQueue.main.async {
                    otaLog("Destroying existing SpringBoard RemoteCall")
                }
                sbProc.destroy()
                DispatchQueue.main.async {
                    mgr.sbProc = nil
                    mgr.rcready = false
                }
            }

            DispatchQueue.main.async {
                otaLog("Creating RemoteCall(process: launchd)")
                startLaunchdRCCountdown()
            }

            guard let proc = RemoteCall(process: "launchd", useMigFilterBypass: false) else {
                let error = RemoteCall.lastInitError() ?? "unknown error"
                DispatchQueue.main.async {
                    clearLaunchdRCCountdown()
                    working = false
                    status = "launchd RemoteCall failed: \(error)"
                    otaLog("launchd RemoteCall failed: \(error)")
                }
                return
            }

            DispatchQueue.main.async {
                clearLaunchdRCCountdown()
                otaLog("launchd RemoteCall initialized")
            }

            if action == .restoreBackup {
                do {
                    let data = try Data(contentsOf: backupURL)
                    DispatchQueue.main.async {
                        otaLog("Loaded backup: \(data.count) bytes")
                        otaLog("Restoring disabled.plist from backup")
                    }
                    result = ota_write_disabled_plist(proc, data)
                } catch {
                    DispatchQueue.main.async {
                        working = false
                        status = "Restore failed: \(error.localizedDescription)"
                        otaLog("Restore failed: \(error.localizedDescription)")
                    }
                    return
                }
            } else {
                DispatchQueue.main.async {
                    otaLog("Writing launchd disabled.plist")
                }
                result = ota_set_updates_disabled(proc, action == .disable)
            }

            DispatchQueue.main.async {
                otaLog("Destroying launchd RemoteCall")
            }
            proc.destroy()
            #endif

            DispatchQueue.main.async {
                working = false
                if result == 0 {
                    refresh()
                    status = "\(action.title) completed through launchd. Fully reboot the device to apply."
                    otaLog("\(action.title) completed")
                    otaLog("Fully reboot the device to apply. A respring is not enough.")
                } else {
                    status = "\(action.title) failed: \(String(cString: strerror(result)))"
                    otaLog("\(action.title) failed: \(String(cString: strerror(result)))")
                }
            }
        }
    }

    private func backup() {
        guard mgr.sbxready else {
            status = "sandbox escape not ready"
            return
        }

        working = true
        defer { working = false }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: plistPath), options: .mappedIfSafe)
            try data.write(to: backupURL, options: .atomic)
            refreshBackupState()
            status = "Backup saved to \(backupURL.lastPathComponent)."
        } catch {
            status = "Backup failed: \(error.localizedDescription)"
        }
    }

    private func readDisabledPlist() -> [String: Any] {
        if !fileExists(plistPath) {
            return [:]
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: plistPath), options: .mappedIfSafe)
            return (try PropertyListSerialization.propertyList(
                from: data,
                options: [.mutableContainersAndLeaves],
                format: nil
            ) as? [String: Any]) ?? [:]
        } catch {
            mgr.logmsg("[ota] failed to read disabled.plist: \(error.localizedDescription)")
            return [:]
        }
    }

    private func fileExists(_ path: String) -> Bool {
        var statbuf = stat()
        return stat(path, &statbuf) == 0
    }

    private func refreshBackupState() {
        hasBackup = FileManager.default.fileExists(atPath: backupURL.path)
    }

    private func otaLog(_ message: String) {
        operationLogs.append(message)
        mgr.logmsg("[ota] \(message)")
    }

    private func startLaunchdRCCountdown() {
        launchdRCDidTimeout = false
        launchdRCRemaining = launchdRCTimeoutSeconds
        launchdRCDeadline = Date().addingTimeInterval(TimeInterval(launchdRCTimeoutSeconds))
        otaLog("launchd RemoteCall may take up to \(launchdRCTimeoutSeconds)s")
    }

    private func clearLaunchdRCCountdown() {
        launchdRCDeadline = nil
        launchdRCRemaining = 0
        launchdRCDidTimeout = false
    }

    private func updateLaunchdRCCountdown(now: Date) {
        guard let deadline = launchdRCDeadline else { return }
        let remaining = Int(ceil(deadline.timeIntervalSince(now)))
        if remaining > 0 {
            launchdRCRemaining = remaining
        } else {
            launchdRCRemaining = 0
            if !launchdRCDidTimeout {
                launchdRCDidTimeout = true
                otaLog("launchd RemoteCall exceeded \(launchdRCTimeoutSeconds)s and may be stuck")
            }
        }
    }
}
