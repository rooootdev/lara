//
//  KeychainView.swift
//  lara
//
//  Created by yyfll on 08.07.26.
//  Modified from DecryptView.swift
//

import SwiftUI
import UIKit

private struct KeychainApp: Identifiable {
    let name: String
    let bundleID: String
    let bundlePath: String
    let executable: String
    let icon: UIImage?

    var id: String { bundleID }
}

private enum KeychainClassKind: String, CaseIterable, Identifiable {
    case genericPassword
    case internetPassword
    case certificate
    case key
    case identity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .genericPassword: return "Generic Password"
        case .internetPassword: return "Internet Password"
        case .certificate: return "Certificate"
        case .key: return "Key"
        case .identity: return "Identity"
        }
    }

    var icon: String {
        switch self {
        case .genericPassword: return "key.horizontal"
        case .internetPassword: return "globe"
        case .certificate: return "checkmark.seal"
        case .key: return "key"
        case .identity: return "person.text.rectangle"
        }
    }

    var exportKey: String {
        switch self {
        case .genericPassword: return "genericPassword"
        case .internetPassword: return "internetPassword"
        case .certificate: return "certificate"
        case .key: return "key"
        case .identity: return "identity"
        }
    }

    var secClass: sec_class {
        switch self {
        case .genericPassword: return .scGenericPassword
        case .internetPassword: return .scInternetPassword
        case .certificate: return .scCertificate
        case .key: return .scKey
        case .identity: return .scIdentity
        }
    }
}

private enum KeychainClassLoadState {
    case success([KeychainItemResult])
    case empty
    case failure(String)
}

private struct KeychainClassResult: Identifiable {
    let kind: KeychainClassKind
    let state: KeychainClassLoadState

    var id: String { kind.id }

    var itemCount: Int {
        switch state {
        case .success(let items): return items.count
        case .empty, .failure: return 0
        }
    }

    var items: [KeychainItemResult] {
        switch state {
        case .success(let items): return items
        case .empty, .failure: return []
        }
    }

    var statusText: String {
        switch state {
        case .success(let items): return "\(items.count) items"
        case .empty: return "0 items"
        case .failure: return "Failed"
        }
    }

    var statusColor: Color {
        switch state {
        case .success(let items):
            return items.isEmpty ? .secondary : .green
        case .empty:
            return .secondary
        case .failure:
            return .red
        }
    }

    var failureMessage: String? {
        if case .failure(let message) = state {
            return message
        }
        return nil
    }

    var jsonObject: [String: Any] {
        var object: [String: Any] = [
            "id": kind.exportKey,
            "title": kind.title,
            "status": jsonStatus,
            "itemCount": itemCount,
            "items": items.map(\.jsonObject),
        ]
        if let failureMessage {
            object["error"] = failureMessage
        }
        return object
    }

    private var jsonStatus: String {
        switch state {
        case .success: return "success"
        case .empty: return "empty"
        case .failure: return "failure"
        }
    }
}

private struct KeychainFieldResult: Identifiable {
    let key: String
    let displayValue: String
    let detailText: String
    let searchText: String
    let isMonospaced: Bool
    let exportValue: Any

    var id: String { key }

    var jsonObject: [String: Any] {
        [
            "key": key,
            "value": exportValue,
        ]
    }
}

private struct KeychainItemResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let fields: [KeychainFieldResult]

    var summaryFields: [KeychainFieldResult] {
        let priorityKeys = [
            "labl", "acct", "svce", "srvr", "path", "agrp", "alis",
            "subj", "issuer", "cdat", "mdat"
        ]

        var matches: [KeychainFieldResult] = []
        for key in priorityKeys {
            if let field = fields.first(where: { $0.key == key }) {
                matches.append(field)
            }
        }

        if matches.isEmpty {
            return Array(fields.prefix(3))
        }
        return matches
    }

    var searchableText: String {
        var pieces = [title]
        if let subtitle {
            pieces.append(subtitle)
        }
        pieces.append(contentsOf: fields.map { "\($0.key) \($0.searchText)" })
        return pieces.joined(separator: "\n")
    }

    var secondarySummary: String? {
        let values = summaryFields
            .map(\.displayValue)
            .filter { !$0.isEmpty }
            .filter { value in
                value != title && value != (subtitle ?? "")
            }

        return values.first
    }

    var jsonObject: [String: Any] {
        var object: [String: Any] = [
            "id": id,
            "title": title,
            "fields": fields.map(\.jsonObject),
        ]
        if let subtitle {
            object["subtitle"] = subtitle
        }
        return object
    }

    var prettyJSON: String {
        prettyPrintedJSONString(jsonObject) ?? "{}"
    }
}

private struct KeychainReadResult {
    let app: KeychainApp
    let date: Date
    let classResults: [KeychainClassResult]

    var totalItems: Int {
        classResults.reduce(0) { $0 + $1.itemCount }
    }

    var exportObject: [String: Any] {
        [
            "app": [
                "name": app.name,
                "bundleID": app.bundleID,
                "bundlePath": app.bundlePath,
                "executable": app.executable,
            ],
            "readAt": iso8601Formatter.string(from: date),
            "totalItems": totalItems,
            "classes": classResults.map(\.jsonObject),
        ]
    }
}

struct KeychainView: View {
    @ObservedObject private var mgr = laramgr.shared
    @State private var query = ""
    @State private var apps: [KeychainApp] = []
    @State private var datareadingbid: String? = nil
    @State private var errormsg: String? = nil
    @State private var pendingread: KeychainApp? = nil
    @State private var currentResult: KeychainReadResult? = nil
    @State private var isLoadingApps = false
    @State private var launchBackgroundTask: UIBackgroundTaskIdentifier = .invalid

    private var filteredapps: [KeychainApp] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return apps }
        let q = trimmed.lowercased()
        return apps.filter { $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q) }
    }

    private var appEmptyMessage: String {
        if !mgr.sbxready {
            return "Run the sandbox escape to list installed apps."
        }
        if isLoadingApps {
            return "Loading..."
        }
        if query.isEmpty {
            return "No apps found."
        }
        return "No matches."
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = errormsg {
                    Section {
                        PlainAlert(title: "Error", icon: "exclamationmark.triangle", text: error, color: .red)
                    }
                }

                currentResultSection
                resultsSection
                installedAppsSection
            }
            .navigationTitle("Keychain Reader")
        }
        .onAppear {
            set_log_callback_kc { msg in
                guard let msg = msg else { return }
                let s = String(cString: msg)
                DispatchQueue.main.async {
                    laramgr.shared.logmsg("(keychain) \(s)")
                }
            }
            if mgr.sbxready && apps.isEmpty {
                loadApps()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            attemptPendingRead(reportFailure: false)
        }
        .onChange(of: mgr.sbxready) { ready in
            if ready {
                loadApps()
            } else {
                apps.removeAll()
                isLoadingApps = false
            }
        }
    }

    private var currentResultSection: some View {
        Section(
            header: HeaderLabel(text: "Current Result", icon: "tray.full"),
            footer: Text("Keychain reading relies on RemoteCall and exploit state. It may be unstable and can fail, return incomplete results or make app crash.")
        ) {
            if let currentResult {
                LabeledContent("App") {
                    Text(currentResult.app.name)
                }
                LabeledContent("Bundle ID") {
                    Text(currentResult.app.bundleID)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Read At") {
                    Text(currentResult.date.formatted(date: .abbreviated, time: .standard))
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Total Items") {
                    Text("\(currentResult.totalItems)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Button("Export JSON") {
                    exportCurrentResult()
                }
                .disabled(datareadingbid != nil)
            } else {
                Text("Read an app to browse its keychain results.")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var resultsSection: some View {
        Section(
            header: HeaderLabel(text: "Results", icon: "key.horizontal"),
            footer: Text("Keychain Reader will switch to target app and then switch back 2 times. Generally, you do not need to take any action during this process.\n\nIf keep in progress, try manually switch to target app and then switch back to lara.")
        ) {
            if let currentResult {
                ForEach(currentResult.classResults) { classResult in
                    switch classResult.state {
                    case .success(let items) where !items.isEmpty:
                        NavigationLink {
                            KeychainClassDetailView(
                                app: currentResult.app,
                                classResult: classResult
                            )
                        } label: {
                            KeychainClassRow(classResult: classResult)
                        }
                    default:
                        KeychainClassRow(classResult: classResult)
                    }
                }
            } else {
                Text("No result yet.")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var installedAppsSection: some View {
        Section(header: HeaderLabel(text: "Installed Apps", icon: "app.badge")) {
            HStack {
                TextField("Search", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button(action: loadApps) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(!mgr.sbxready || datareadingbid != nil || isLoadingApps)
            }

            if filteredapps.isEmpty {
                Text(appEmptyMessage)
                    .foregroundColor(.secondary)
            } else {
                ForEach(filteredapps) { app in
                    KCAppRow(
                        app: app,
                        isreading: datareadingbid == app.bundleID,
                        isdisabled: datareadingbid != nil && datareadingbid != app.bundleID
                    ) {
                        startRead(app)
                    }
                }
            }
        }
    }

    private func loadApps() {
        guard mgr.sbxready else {
            DispatchQueue.main.async {
                self.apps.removeAll()
                self.isLoadingApps = false
            }
            return
        }

        DispatchQueue.main.async {
            self.isLoadingApps = true
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var results: [KeychainApp] = []
            let bundleFolder = "/private/var/containers/Bundle/Application"

            guard let bundles = try? FileManager.default.contentsOfDirectory(atPath: bundleFolder) else {
                DispatchQueue.main.async {
                    self.apps.removeAll()
                    self.isLoadingApps = false
                }
                return
            }

            for bundle in bundles {
                let appPath = bundleFolder + "/" + bundle
                guard let contents = try? FileManager.default.contentsOfDirectory(atPath: appPath) else { continue }
                for item in contents {
                    guard item.hasSuffix(".app") else { continue }
                    guard isEligibleKeychainApp(at: appPath, bname: item) else { continue }
                    let fullAppPath = appPath + "/" + item
                    let infoPath = fullAppPath + "/Info.plist"
                    guard let info = NSDictionary(contentsOfFile: infoPath) else { continue }
0
                    let executable = info["CFBundleExecutable"] as? String ?? ""
                    if executable.isEmpty { continue }
                    let bundleid = info["CFBundleIdentifier"] as? String ?? ""
                    if bundleid != nil && bundleid == Bundle.main.bundleIdentifier { continue }
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

                    results.append(KeychainApp(
                        name: name,
                        bundleID: bundleid,
                        bundlePath: fullAppPath,
                        executable: executable,
                        icon: icon ?? UIImage(named: "unknown")
                    ))
                    break
                }
            }

            results.sort { $0.name.lowercased() < $1.name.lowercased() }
            DispatchQueue.main.async {
                self.apps = results
                self.isLoadingApps = false
            }
        }
    }

    private func isEligibleKeychainApp(at containerPath: String, bname bundleName: String) -> Bool {
        FileManager.default.fileExists(atPath: containerPath + "/" + bundleName + "/embedded.mobileprovision") || FileManager.default.fileExists(atPath: containerPath + "/iTunesMetadata.plist")
    }

    private func startRead(_ app: KeychainApp) {
        guard datareadingbid == nil && pendingread == nil else { return }
        guard mgr.dsready else {
            errormsg = "Darksword not ready. Run the exploit first."
            return
        }
        guard mgr.hasOffsets else {
            errormsg = "Offsets not ready. Fetch the kernelcache offsets first."
            return
        }
        guard mgr.sbxready else {
            errormsg = "Sandbox escape not ready."
            return
        }
        guard !app.executable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errormsg = "App executable is missing."
            return
        }

        runRead(app)
    }

    private func runRead(_ app: KeychainApp) {
        errormsg = nil
        datareadingbid = app.bundleID
        pendingread = app
        beginLaunchBackgroundTask()

        let ret = launch_app(app.bundleID)
        guard ret == 0 else {
            pendingread = nil
            datareadingbid = nil
            errormsg = "Could not launch app. Open it manually."
            endLaunchBackgroundTask()
            return
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 5.0) {
            returnToLaraApp()
            usleep(1_000_000)
            DispatchQueue.main.async {
                self.attemptPendingRead(reportFailure: true)
            }
        }
    }

    private func attemptPendingRead(reportFailure _: Bool) {
        guard let app = pendingread else { return }

        guard mgr.dsready, mgr.hasOffsets, mgr.sbxready else {
            pendingread = nil
            datareadingbid = nil
            errormsg = "Exploit state changed. Reinitialize and try again."
            endLaunchBackgroundTask()
            return
        }

        guard !app.executable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            pendingread = nil
            datareadingbid = nil
            errormsg = "App executable is missing."
            endLaunchBackgroundTask()
            return
        }

        pendingread = nil
        endLaunchBackgroundTask()
        doRead(app)
    }

    private func doRead(_ app: KeychainApp) {
        guard mgr.dsready, mgr.hasOffsets, mgr.sbxready else {
            datareadingbid = nil
            errormsg = "Exploit state changed. Reinitialize and try again."
            return
        }

        laramgr.shared.logmsg("(keychain) reading \(app.bundleID)...")

        DispatchQueue.global(qos: .userInitiated).async {
            guard let proc = RemoteCall(process: app.executable, useMigFilterBypass: false) else {
                DispatchQueue.main.async {
                    self.datareadingbid = nil
                    self.errormsg = "Cannot init RemoteCall."
                }
                return
            }

            defer {
                proc.destroy()
                returnToLaraApp()
            }

            let relaunchSucceeded = DispatchQueue.main.sync {
                launch_app(app.bundleID) == 0
            }
            guard relaunchSucceeded else {
                DispatchQueue.main.async {
                    self.datareadingbid = nil
                    self.errormsg = "Could not relaunch app for keychain scan."
                }
                return
            }

            usleep(500_000)

            let result = self.performRead(app: app, proc: proc)
            DispatchQueue.main.async {
                self.currentResult = result
                self.datareadingbid = nil
                self.errormsg = nil
            }
        }
    }

    private func performRead(app: KeychainApp, proc: RemoteCall) -> KeychainReadResult {
        var secSymbols = remote_sec_symbols()
        guard find_secitem_symbols(proc, &secSymbols) else {
            let message = "Failed to resolve Security symbols."
            laramgr.shared.logmsg("(keychain) \(message)")
            return KeychainReadResult(
                app: app,
                date: Date(),
                classResults: KeychainClassKind.allCases.map {
                    KeychainClassResult(kind: $0, state: .failure(message))
                }
            )
        }

        var classResults: [KeychainClassResult] = []

        for kind in KeychainClassKind.allCases {
            guard let rawItems = get_secitems(proc, &secSymbols, kind.secClass, true) as? [NSDictionary] else {
                laramgr.shared.logmsg("(keychain) \(kind.title.lowercased()) read failed")
                classResults.append(
                    KeychainClassResult(
                        kind: kind,
                        state: .failure("Failed to read \(kind.title.lowercased()) items.")
                    )
                )
                continue
            }

            let items = normalizeItems(rawItems, kind: kind)
            if items.isEmpty {
                laramgr.shared.logmsg("(keychain) \(kind.title.lowercased()): 0 items")
                classResults.append(KeychainClassResult(kind: kind, state: .empty))
            } else {
                laramgr.shared.logmsg("(keychain) \(kind.title.lowercased()): \(items.count) items")
                classResults.append(KeychainClassResult(kind: kind, state: .success(items)))
            }
        }

        let result = KeychainReadResult(
            app: app,
            date: Date(),
            classResults: classResults
        )
        laramgr.shared.logmsg("(keychain) finished \(app.bundleID) with \(result.totalItems) total item(s)")
        return result
    }

    private func normalizeItems(_ rawItems: [NSDictionary], kind: KeychainClassKind) -> [KeychainItemResult] {
        rawItems.enumerated().map { index, rawItem in
            let rawPairs = rawItem.allKeys.compactMap { key -> (String, Any)? in
                guard let value = rawItem.object(forKey: key) else { return nil }
                return (String(describing: key), value)
            }
            let pairs = rawPairs.sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
            let fields = pairs.map { normalizeField(key: $0.0, value: $0.1) }

            let title = itemLabel(
                fallback: "\(kind.title) Item \(index + 1)",
                fields: fields,
                preferredKeys: ["labl", "svce", "srvr", "acct", "alis", "subj", "type"]
            )
            let subtitle = itemSubtitle(fields: fields, excluding: title)

            return KeychainItemResult(
                id: "\(kind.exportKey)-\(index)",
                title: title,
                subtitle: subtitle,
                fields: fields
            )
        }
    }

    private func normalizeField(key: String, value: Any) -> KeychainFieldResult {
        if let data = value as? Data {
            if data.isEmpty {
                let exportValue: [String: Any] = [
                    "type": "data",
                    "byteCount": 0,
                    "base64": "",
                    "preview": "",
                ]
                return KeychainFieldResult(
                    key: key,
                    displayValue: "",
                    detailText: "",
                    searchText: "",
                    isMonospaced: true,
                    exportValue: exportValue
                )
            }

            if key.caseInsensitiveCompare("sha1") == .orderedSame {
                let hex = hexString(data)
                let exportValue: [String: Any] = [
                    "type": "data",
                    "byteCount": data.count,
                    "hex": hex,
                    "base64": data.base64EncodedString(),
                ]
                return KeychainFieldResult(
                    key: key,
                    displayValue: hex,
                    detailText: hex,
                    searchText: hex,
                    isMonospaced: true,
                    exportValue: exportValue
                )
            }

            let preview = santanderfs.render(data: data).text
            let exportValue: [String: Any] = [
                "type": "data",
                "byteCount": data.count,
                "base64": data.base64EncodedString(),
                "preview": preview,
            ]
            return KeychainFieldResult(
                key: key,
                displayValue: compactText(preview),
                detailText: preview,
                searchText: preview,
                isMonospaced: true,
                exportValue: exportValue
            )
        }

        if let string = value as? String {
            return KeychainFieldResult(
                key: key,
                displayValue: compactText(string),
                detailText: string,
                searchText: string,
                isMonospaced: false,
                exportValue: string
            )
        }

        if let date = value as? Date {
            let display = date.formatted(date: .abbreviated, time: .standard)
            return KeychainFieldResult(
                key: key,
                displayValue: display,
                detailText: display,
                searchText: display,
                isMonospaced: false,
                exportValue: iso8601Formatter.string(from: date)
            )
        }

        if let bool = value as? Bool {
            let display = bool ? "True" : "False"
            return KeychainFieldResult(
                key: key,
                displayValue: display,
                detailText: display,
                searchText: display,
                isMonospaced: false,
                exportValue: bool
            )
        }

        if let int = value as? Int {
            let display = String(int)
            return KeychainFieldResult(
                key: key,
                displayValue: display,
                detailText: display,
                searchText: display,
                isMonospaced: false,
                exportValue: int
            )
        }

        if let double = value as? Double {
            let display = String(format: "%.3f", double)
            return KeychainFieldResult(
                key: key,
                displayValue: display,
                detailText: display,
                searchText: display,
                isMonospaced: false,
                exportValue: double
            )
        }

        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                let bool = number.boolValue
                let display = bool ? "True" : "False"
                return KeychainFieldResult(
                    key: key,
                    displayValue: display,
                    detailText: display,
                    searchText: display,
                    isMonospaced: false,
                    exportValue: bool
                )
            }

            let display = number.stringValue
            let exportValue: Any = Int(display).map { $0 } ?? Double(display).map { $0 } ?? display
            return KeychainFieldResult(
                key: key,
                displayValue: display,
                detailText: display,
                searchText: display,
                isMonospaced: false,
                exportValue: exportValue
            )
        }

        if let dict = value as? NSDictionary {
            let exportValue = normalizedDictionary(dict)
            let detail = prettyPrintedJSONString(exportValue) ?? String(describing: exportValue)
            return KeychainFieldResult(
                key: key,
                displayValue: compactText(detail),
                detailText: detail,
                searchText: detail,
                isMonospaced: true,
                exportValue: exportValue
            )
        }

        if let dict = value as? [AnyHashable: Any] {
            let exportValue = normalizedDictionary(dict)
            let detail = prettyPrintedJSONString(exportValue) ?? String(describing: exportValue)
            return KeychainFieldResult(
                key: key,
                displayValue: compactText(detail),
                detailText: detail,
                searchText: detail,
                isMonospaced: true,
                exportValue: exportValue
            )
        }

        if let array = value as? [Any] {
            let exportValue = array.map(normalizedJSONValue)
            let detail = prettyPrintedJSONString(exportValue) ?? String(describing: exportValue)
            return KeychainFieldResult(
                key: key,
                displayValue: compactText(detail),
                detailText: detail,
                searchText: detail,
                isMonospaced: true,
                exportValue: exportValue
            )
        }

        let fallback = String(describing: value)
        return KeychainFieldResult(
            key: key,
            displayValue: compactText(fallback),
            detailText: fallback,
            searchText: fallback,
            isMonospaced: true,
            exportValue: fallback
        )
    }

    private func itemLabel(fallback: String, fields: [KeychainFieldResult], preferredKeys: [String]) -> String {
        for key in preferredKeys {
            if let value = fieldDisplayValue(for: key, in: fields), !value.isEmpty {
                return value
            }
        }
        return fallback
    }

    private func itemSubtitle(fields: [KeychainFieldResult], excluding title: String) -> String? {
        let preferredKeys = ["acct", "svce", "srvr", "path", "agrp", "alis", "issuer", "subj"]
        for key in preferredKeys {
            guard let value = fieldDisplayValue(for: key, in: fields), !value.isEmpty, value != title else { continue }
            return value
        }
        return nil
    }

    private func fieldDisplayValue(for key: String, in fields: [KeychainFieldResult]) -> String? {
        fields.first(where: { $0.key == key })?.displayValue
    }

    private func exportCurrentResult() {
        guard let currentResult else { return }

        do {
            let data = try JSONSerialization.data(
                withJSONObject: currentResult.exportObject,
                options: [.prettyPrinted, .sortedKeys]
            )
            let timestamp = iso8601Formatter.string(from: currentResult.date)
                .replacingOccurrences(of: ":", with: "-")
            let filename = "keychain-\(currentResult.app.bundleID)-\(timestamp).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            presentShareSheet(with: url)
        } catch {
            errormsg = "Failed to export result: \(error.localizedDescription)"
        }
    }

    private func beginLaunchBackgroundTask() {
        guard launchBackgroundTask == .invalid else { return }
        launchBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "KeychainLaunch") {
            DispatchQueue.main.async {
                self.endLaunchBackgroundTask()
            }
        }
    }

    private func endLaunchBackgroundTask() {
        guard launchBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(launchBackgroundTask)
        launchBackgroundTask = .invalid
    }
}

private struct KeychainClassDetailView: View {
    let app: KeychainApp
    let classResult: KeychainClassResult

    @State private var searchQuery = ""

    private var filteredItems: [KeychainItemResult] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return classResult.items }
        let query = trimmed.lowercased()
        return classResult.items.filter { item in
            item.searchableText.lowercased().contains(query)
        }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("App") {
                    Text(app.name)
                }
                LabeledContent("Bundle ID") {
                    Text(app.bundleID)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Items") {
                    Text("\(classResult.itemCount)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } header: {
                HeaderLabel(text: classResult.kind.title, icon: classResult.kind.icon)
            }

            Section {
                if filteredItems.isEmpty {
                    Text(searchQuery.isEmpty ? "No items." : "No matches.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(filteredItems) { item in
                        NavigationLink {
                            KeychainItemDetailView(item: item)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                if let subtitle = item.subtitle {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }

                                if let summary = item.secondarySummary {
                                    Text(summary)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
            } header: {
                HeaderLabel(text: "Items", icon: "list.bullet.rectangle")
            }
        }
        .navigationTitle(classResult.kind.title)
        .searchable(text: $searchQuery, prompt: "Search items")
    }
}

private struct KeychainItemDetailView: View {
    let item: KeychainItemResult

    var body: some View {
        List {
            if !item.summaryFields.isEmpty {
                Section(header: HeaderLabel(text: "Summary", icon: "text.alignleft")) {
                    ForEach(item.summaryFields) { field in
                        KeychainFieldRow(field: field)
                    }
                }
            }

            Section(header: HeaderLabel(text: "All Fields", icon: "doc.text")) {
                ForEach(item.fields) { field in
                    KeychainFieldRow(field: field)
                }
            }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = item.prettyJSON
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
            }
        }
    }
}

private struct KeychainClassRow: View {
    let classResult: KeychainClassResult

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: classResult.kind.icon)
                .frame(width: 20, alignment: .center)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(classResult.kind.title)
                    .foregroundColor(.primary)

                if let failureMessage = classResult.failureMessage {
                    Text(failureMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Text(classResult.statusText)
                .font(.caption)
                .foregroundColor(classResult.statusColor)
                .monospaced()
        }
    }
}

private struct KeychainFieldRow: View {
    let field: KeychainFieldResult

    private var usesExpandedLayout: Bool {
        field.isMonospaced || field.detailText.contains("\n") || field.detailText.count > 90
    }

    private var renderedText: String {
        field.detailText.isEmpty ? "(empty)" : field.detailText
    }

    var body: some View {
        if usesExpandedLayout {
            VStack(alignment: .leading, spacing: 6) {
                Text(field.key)
                    .fontWeight(.medium)

                Text(renderedText)
                    .font(field.isMonospaced ? .system(size: 13, design: .monospaced) : .body)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LabeledContent(field.key) {
                Text(renderedText)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct KCAppRow: View {
    let app: KeychainApp
    let isreading: Bool
    let isdisabled: Bool
    let onread: () -> Void

    var body: some View {
        HStack {
            if let icon = app.icon {
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

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.headline)
                Text(app.bundleID)
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            Button(action: onread) {
                if isreading {
                    ProgressView()
                } else {
                    Text("Read")
                }
            }
            .disabled(isdisabled || isreading)
        }
        .opacity(isreading || isdisabled ? 0.6 : 1.0)
    }
}

private let iso8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private func returnToLaraApp() {
    guard let bundleID = Bundle.main.bundleIdentifier else { return }
    _ = launch_app(bundleID)
}

private func compactText(_ text: String, maxLength: Int = 96) -> String {
    let collapsed = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard collapsed.count > maxLength else { return collapsed }
    return String(collapsed.prefix(maxLength - 3)) + "..."
}

private func normalizedDictionary(_ dictionary: NSDictionary) -> [String: Any] {
    let pairs = dictionary.allKeys.compactMap { key -> (String, Any)? in
        guard let value = dictionary.object(forKey: key) else { return nil }
        return (String(describing: key), value)
    }
    return normalizedDictionary(pairs)
}

private func normalizedDictionary(_ dictionary: [AnyHashable: Any]) -> [String: Any] {
    let pairs = dictionary.map { (String(describing: $0.key), $0.value) }
    return normalizedDictionary(pairs)
}

private func normalizedDictionary(_ pairs: [(String, Any)]) -> [String: Any] {
    var result: [String: Any] = [:]
    for (key, value) in pairs.sorted(by: { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }) {
        result[key] = normalizedJSONValue(value)
    }
    return result
}

private func normalizedJSONValue(_ value: Any) -> Any {
    if let data = value as? Data {
        let preview = santanderfs.render(data: data).text
        return [
            "type": "data",
            "byteCount": data.count,
            "base64": data.base64EncodedString(),
            "preview": preview,
        ]
    }
    if let string = value as? String {
        return string
    }
    if let date = value as? Date {
        return iso8601Formatter.string(from: date)
    }
    if let bool = value as? Bool {
        return bool
    }
    if let int = value as? Int {
        return int
    }
    if let double = value as? Double {
        return double
    }
    if let number = value as? NSNumber {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue
        }
        if let intValue = Int(number.stringValue) {
            return intValue
        }
        if let doubleValue = Double(number.stringValue) {
            return doubleValue
        }
        return number.stringValue
    }
    if let dict = value as? NSDictionary {
        return normalizedDictionary(dict)
    }
    if let dict = value as? [AnyHashable: Any] {
        return normalizedDictionary(dict)
    }
    if let array = value as? [Any] {
        return array.map(normalizedJSONValue)
    }
    return String(describing: value)
}

private func hexString(_ data: Data) -> String {
    data.map { String(format: "%02X", $0) }.joined()
}

private func prettyPrintedJSONString(_ value: Any) -> String? {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
          let string = String(data: data, encoding: .utf8)
    else {
        return nil
    }
    return string
}
