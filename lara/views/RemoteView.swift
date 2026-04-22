//
//  RemoteView.swift
//  lara
//
//  Created by ruter on 17.04.26.
//

import SwiftUI
import Darwin

struct RemoteView: View {
    @ObservedObject var mgr: laramgr
    @State private var running: Bool = false
    @State private var columns: Int = 5
    @State private var performanceHUD: Int = -1
    @AppStorage("rcdockunlimited") private var rcdockunlimited: Bool = false
    @State private var customProcessName: String = "SpringBoard"
    @State private var customFunctionName: String = "getpid"
    @State private var customArgsText: String = ""
    @State private var customTimeoutMs: Int = 100
    @State private var customMigBypass: Bool = false
    @State private var customLastResult: String = ""

    private var dockMaxColumns: Int { rcdockunlimited ? 50 : 10 }

    var body: some View {
        List {
            Section {
                Button {
                    run("Status Bar Time Format") {
                        status_bar_tweak(mgr.sbProc)
                        return "status_bar_tweak() done"
                    }
                } label: {
                    Text("Status Bar Time Format")
                }

                Button {
                    run("Hide Icon Labels") {
                        let hidden = hide_icon_labels(mgr.sbProc)
                        return "hide_icon_labels() -> \(hidden)"
                    }
                } label: {
                    Text("Hide Icon Labels")
                }
            } header: {
                Text("SpringBoard")
            }

            Section {
                Stepper(value: $columns, in: 1...dockMaxColumns) {
                    HStack {
                        Text("Dock columns")
                        Spacer()
                        Text("\(columns)")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
                .onChange(of: rcdockunlimited) { _ in
                    if !rcdockunlimited, columns > 10 {
                        columns = 10
                    }
                }

                Button {
                    run("Apply Dock Columns=\(columns)") {
                        let result = set_dock_icon_count(mgr.sbProc, Int32(columns))
                        return "set_dock_icon_count(\(columns)) -> \(result)"
                    }
                } label: {
                    Text("Apply Dock Columns")
                }
            }

            Section {
                Button {
                    run("Enable Upside Down") {
                        let result = enable_upside_down(mgr.sbProc)
                        return "enable_upside_down() -> \(result)"
                    }
                } label: {
                    Text("Enable Upside Down")
                }
            }

            Section {
                Button {
                    run("Enable Floating Dock") {
                        let result = enable_floating_dock(mgr.sbProc)
                        return "enable_floating_dock() -> \(result)"
                    }
                } label: {
                    Text("Enable Floating Dock (Broken)")
                }
                
                Button {
                    run("Enable Grid App Switcher") {
                        let result = enable_grid_app_switcher(mgr.sbProc)
                        return "enable_grid_app_switcher() -> \(result)"
                    }
                } label: {
                    Text("Enable Grid App Switcher (Broken animation)")
                }
            }
            
            Section {
                Picker("Performance HUD", selection: $performanceHUD) {
                    Text("Off").tag(-1)
                    Text("Basic").tag(0)
                    Text("Backdrops").tag(1)
                    Text("Particles").tag(2)
                    Text("Full").tag(3)
                    Text("Power").tag(5)
                    Text("EDR").tag(7)
                    Text("Glitches").tag(8)
                    Text("GPU Time").tag(9)
                    Text("Memory Bandwidth").tag(10)
                }
                .onChange(of: performanceHUD) { newValue in
                    set_performance_hud(mgr.sbProc, Int32(newValue))
                }
                .onAppear {
                    if mgr.rcrunning {
                        performanceHUD = Int(get_performance_hud(mgr.sbProc))
                    }
                }
            } footer: {
                Text("These call into SpringBoard via RemoteCall. Keep RemoteCall initialized while running them.")
                
                if !mgr.rcready {
                    Text("RemoteCall is not initialized. How are you here?")
                }
            }
            .disabled(!mgr.rcready || running)
            
            if #available(iOS 17.4, *) {
                Section {
                    Button {
                        mgr.rcinitDaemon(serviceName: "com.apple.xpc.amsaccountsd", process: "amsaccountsd", migbypass: false) { proc in
                            guard let proc else {
                                mgr.logmsg("rc init failed")
                                return
                            }
                            mgr.logmsg("rc init succeeded!")
                            mgr.eligibilitystate = euenabler_overwrite_eligibility(proc) == 0
                            mgr.logmsg("overwrite_eligibility() returned: \(mgr.eligibilitystate! ? "success" : "failure")")
                            proc.destroy()
                        }
                    } label: {
                        HStack {
                            Text("Overwrite eligibility (one time setup)")
                            if let state = mgr.eligibilitystate {
                                Spacer()
                                if state {
                                    Image(systemName: "checkmark.circle")
                                        .foregroundColor(.green)
                                } else {
                                    Image(systemName: "xmark.circle")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                    .disabled(mgr.eligibilitystate ?? false)
                    
                    Button {
                        mgr.eu1progress = 0.0
                        mgr.eu2progress = 0.0
                        mgr.eu1running = true
                        mgr.eu2running = true
                        mgr.rcinitDaemon(serviceName: "com.apple.managedappdistributiond.xpc", process: "managedappdistributiond", migbypass: false) { proc in
                            guard let proc else {
                                mgr.logmsg("rc init failed")
                                mgr.eu1running = false
                                return
                            }
                            mgr.logmsg("rc init succeeded!")
                            euenabler_override_country_code(proc) { progress in
                                DispatchQueue.main.async {
                                    self.mgr.eu1progress = progress
                                }
                            }
                            proc.destroy()
                            DispatchQueue.main.async {
                                mgr.eu1running = false
                            }
                        }
                        // fix unable to load app info
                        mgr.rcinitDaemon(serviceName: "com.apple.appstorecomponentsd.xpc", process: "appstorecomponentsd", migbypass: false) { proc in
                            guard let proc else {
                                mgr.logmsg("rc init failed")
                                mgr.eu2running = false
                                return
                            }
                            mgr.logmsg("rc init succeeded!")
                            euenabler_override_country_code(proc) { progress in
                                DispatchQueue.main.async {
                                    self.mgr.eu2progress = progress
                                }
                            }
                            proc.destroy()
                            DispatchQueue.main.async {
                                mgr.eu2running = false
                            }
                        }
                    } label: {
                        HStack {
                            if mgr.eu1running || mgr.eu2running {
                                ProgressView(value: (mgr.eu1progress + mgr.eu2progress)/2)
                                    .progressViewStyle(.circular)
                                    .frame(width: 18, height: 18)
                                Text("Running...")
                                Spacer()
                                Text("\(Int((mgr.eu1progress + mgr.eu2progress)/2 * 100))%")
                            } else {
                                Text("Enable Spoof EU Region")
                                Spacer()
                                if mgr.eu1progress + mgr.eu2progress == 2 {
                                    Image(systemName: "checkmark.circle")
                                        .foregroundColor(.green)
                                } else if mgr.dsattempted && mgr.dsfailed {
                                    Image(systemName: "xmark.circle")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                    .disabled(mgr.eu1running || mgr.eu2running || mgr.eu1progress+mgr.eu2progress == 2)
                } footer: {
                    Text("Enables installing of EU/Japan Marketplace apps.")
                }
                .disabled(isdebugged() || mgr.rcrunning || !mgr.rcready)
            }
            
            Section {
                TextField("Process name", text: $customProcessName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack {
                    TextField("Function (symbol or 0xaddr)", text: $customFunctionName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(1)
                    
                    TextEditor(text: $customArgsText)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Stepper(value: $customTimeoutMs, in: 10...5000, step: 10) {
                    HStack {
                        Text("Timeout")
                        Spacer()
                        Text("\(customTimeoutMs) ms")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }

                Toggle("MIG filter bypass", isOn: $customMigBypass)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Args (comma/space separated; dec, 0xhex, or -1)")
                        .foregroundColor(.secondary)
                        .font(.footnote)
                }

                Button {
                    run("Custom RemoteCall \(customProcessName):\(customFunctionName)") {
                        let process = customProcessName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let function = customFunctionName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !process.isEmpty else { return "custom: missing process name" }
                        guard !function.isEmpty else { return "custom: missing function name" }

                        let (args, parseError) = parseRemoteCallArgs(customArgsText)
                        if let parseError {
                            return "custom: args parse error: \(parseError)"
                        }

                        let ptr: UnsafeMutableRawPointer?
                        if let addr = parseAddress(function) {
                            ptr = UnsafeMutableRawPointer(bitPattern: UInt(addr))
                        } else {
                            let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
                            ptr = function.withCString { dlsym(RTLD_DEFAULT, $0) }
                        }

                        guard let ptr else {
                            return "custom: failed to resolve \(function)"
                        }

                        guard let proc = RemoteCall(process: process, useMigFilterBypass: customMigBypass) else {
                            return "custom: RemoteCall init failed for \(process)"
                        }
                        defer { proc.destroy() }

                        var argsCopy = args
                        let ret = function.withCString { (cName: UnsafePointer<CChar>) -> UInt64 in
                            UInt64(argsCopy.withUnsafeMutableBufferPointer { buffer in
                                proc.doStable(
                                    withTimeout: Int32(customTimeoutMs),
                                    functionName: UnsafeMutablePointer(mutating: cName),
                                    functionPointer: ptr,
                                    args: buffer.baseAddress,
                                    argCount: UInt(args.count)
                                )
                            })
                        }

                        let err = proc.lastError ?? ""
                        let suffix = err.isEmpty ? "" : " (err: \(err))"
                        return "custom: \(process) \(function)(\(args.count) args) -> 0x\(String(ret, radix: 16)) / \(ret)\(suffix)"
                    } onComplete: { msg in
                        self.customLastResult = msg
                    }
                } label: {
                    Text("Call")
                }

                if !customLastResult.isEmpty {
                    Text(customLastResult)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Custom RemoteCall")
            } footer: {
                Text("Calls a symbol (via dlsym) or an absolute address. Numeric args are passed as x0-x7 then stack.")
            }
            .disabled(!mgr.rcready || running)

            Section {
                HStack(alignment: .top) {
                    AsyncImage(url: URL(string: "https://github.com/khanhduytran0.png")) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    
                    VStack(alignment: .leading) {
                        Text("Duy Tran")
                            .font(.headline)
                        
                        Text("Responsible for most things related to remotecall.")
                            .font(.subheadline)
                            .foregroundColor(Color.secondary)
                    }
                    
                    Spacer()
                }
                .onTapGesture {
                    if let url = URL(string: "https://github.com/khanhduytran0"),
                       UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url)
                    }
                }
                
                HStack(alignment: .top) {
                    AsyncImage(url: URL(string: "https://github.com/zeroxjf.png")) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    
                    VStack(alignment: .leading) {
                        Text("0xjf")
                            .font(.headline)
                        
                        Text("Powercuff and SBCustomizer")
                            .font(.subheadline)
                            .foregroundColor(Color.secondary)
                    }
                    
                    Spacer()
                }
                .onTapGesture {
                    if let url = URL(string: "https://github.com/zeroxjf"),
                       UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url)
                    }
                }
                
                HStack(alignment: .top) {
                    AsyncImage(url: URL(string: "https://github.com/Scr-eam.png")) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    
                    VStack(alignment: .leading) {
                        Text("Scream")
                            .font(.headline)
                        
                        Text("Fixed Hide Icon Labels")
                            .font(.subheadline)
                            .foregroundColor(Color.secondary)
                    }
                    
                    Spacer()
                }
                .onTapGesture {
                    if let url = URL(string: "https://github.com/Scr-eam"),
                       UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url)
                    }
                }
            } header: {
                Text("Credits")
            }
        }
        .navigationTitle(Text("Tweaks"))
    }

    private func run(_ name: String, _ work: @escaping () -> String, onComplete: ((String) -> Void)? = nil) {
        guard mgr.rcready, !running else { return }
        running = true
        mgr.logmsg("(rc) \(name)...")

        DispatchQueue.global(qos: .userInitiated).async {
            let result = work()
            DispatchQueue.main.async {
                self.mgr.logmsg("(rc) \(result)")
                onComplete?(result)
                self.running = false
            }
        }
    }

    private func parseRemoteCallArgs(_ text: String) -> (args: [UInt64], error: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ([], nil) }

        let separators = CharacterSet(charactersIn: ", \t\r\n")
        let tokens = trimmed
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var out: [UInt64] = []
        out.reserveCapacity(tokens.count)

        for token in tokens {
            if let value = parseUInt64OrInt64BitPattern(token) {
                out.append(value)
            } else {
                return ([], "bad token '\(token)'")
            }
        }

        return (out, nil)
    }

    private func parseUInt64OrInt64BitPattern(_ token: String) -> UInt64? {
        if token.hasPrefix("-") {
            let rest = String(token.dropFirst())
            if rest.lowercased().hasPrefix("0x") {
                let hex = String(rest.dropFirst(2))
                guard let magnitude = UInt64(hex, radix: 16) else { return nil }
                let signed = -Int64(bitPattern: magnitude)
                return UInt64(bitPattern: signed)
            } else {
                guard let signed = Int64(rest) else { return nil }
                return UInt64(bitPattern: -signed)
            }
        }

        if token.lowercased().hasPrefix("0x") {
            return UInt64(token.dropFirst(2), radix: 16)
        }

        return UInt64(token)
    }

    private func parseAddress(_ functionField: String) -> UInt64? {
        let s = functionField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.lowercased().hasPrefix("0x") else { return nil }
        guard let value = UInt64(s.dropFirst(2), radix: 16) else { return nil }
        guard value <= UInt64(UInt.max) else { return nil }
        return value
    }
}
