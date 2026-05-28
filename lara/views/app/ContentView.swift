//
//  ContentView.swift
//  lara
//
//  Created by ruter on 23.03.26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var mgr: laramgr
    @ObservedObject private var logger = globallogger
    @AppStorage("selectedMethod") private var selectedmethod: method = .hybrid
    @AppStorage("logsdisplaymode") private var selectedlogsdisplaymode: logsdisplaymode = .toolbar
    @AppStorage("loggerNoBS") private var loggernobs: Bool = true
    
    @State private var showSettings: Bool = false
    @State private var dlingkcache: Bool = false
    
    init() {
        globallogger.capture()
    }
    
    var body: some View {
        NavigationStack {
            List {
                AlertsSection
                KRWSection
                RCSection
                ActionsSection
                DebugSection
                InlineLogsSection
            }
            .navigationTitle("lara")
            .toolbar {
                if selectedlogsdisplaymode == .toolbar {
                    Button(action: {
                        mgr.showLogs.toggle()
                    }) {
                        Image(systemName: "terminal")
                    }
                }
                Button(action: {
                    showSettings.toggle()
                }) {
                    Image(systemName: "gear")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
    
    private var AlertsSection: some View {
        Section {
            if !mgr.hasOffsets {
                PlainAlert(title: "No offsets found!", icon: "exclamationmark.triangle.fill", text: "Kernelcache offsets are missing. Click \"Run Exploit\" and then fetch the offsets.")
            }
        }
    }
    
    private var KRWSection: some View {
        Section {
            LabeledContent(content: {
                if mgr.dsready {
                    Image(systemName: "checkmark.circle")
                } else if mgr.dsrunning {
                    HStack {
                        Text("\(Int(mgr.dsprogress * 100))%")
                        ProgressView()
                    }
                } else if mgr.dsattempted && mgr.dsfailed {
                    Image(systemName: "xmark.circle")
                }
            }) {
                Button("Run Exploit", action: {
                    offsets_init()
                    mgr.run()
                })
                .disabled(mgr.dsready || mgr.dsrunning || isdebugged())
            }
            
            if !mgr.hasOffsets {
                Button {
                    guard !dlingkcache else { return }
                    dlingkcache = true

                    DispatchQueue.global(qos: .userInitiated).async {
                        let fetched = fetchkcache()

                        if fetched {
                            let dlkc = dlkcache()
                            DispatchQueue.main.async {
                                mgr.hasOffsets = dlkc
                                dlingkcache = false
                            }
                            return
                        }

                        DispatchQueue.main.async {
                            mgr.hasOffsets = false
                            dlingkcache = false
                        }
                    }
                } label: {
                    if dlingkcache {
                        HStack {
                            Text("Fetching Kernelcache...")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Text("Fetch Kernelcache")
                    }
                }
                .disabled(dlingkcache || !mgr.dsready)
            } else {
                if selectedmethod == .hybrid {
                    LabeledContent(content: {
                        if mgr.vfsready && mgr.sbxready {
                            Image(systemName: "checkmark.circle")
                        } else if mgr.vfsrunning || mgr.sbxrunning {
                            HStack {
                                Text("Running...")
                                ProgressView()
                            }
                        } else if (mgr.vfsattempted && mgr.vfsfailed) || (mgr.sbxattempted && mgr.sbxfailed) {
                            Image(systemName: "xmark.circle")
                        }
                    }) {
                        Button("Initialize System", action: {
                            mgr.vfsinit()
                            mgr.sbxescape()
                        })
                        .disabled(!mgr.hasOffsets || !mgr.dsready || mgr.vfsrunning || mgr.sbxrunning || (mgr.vfsready && mgr.sbxready))
                    }
                }
                
                // initalize vfs
                if selectedmethod == .vfs {
                    LabeledContent(content: {
                        if mgr.vfsready {
                            Image(systemName: "checkmark.circle")
                        } else if mgr.vfsrunning {
                            HStack {
                                Text("\(Int(mgr.dsprogress * 100))%")
                                ProgressView()
                            }
                        } else if mgr.vfsattempted && mgr.vfsfailed {
                            Image(systemName: "xmark.circle")
                        }
                    }) {
                        Button("Initialize VFS", action: {
                            mgr.vfsinit()
                        })
                        .disabled(!mgr.dsready || mgr.vfsready || mgr.vfsrunning || isdebugged())
                    }
                }
                
                // escape sandbox
                if selectedmethod == .sbx {
                    LabeledContent(content: {
                        if mgr.sbxready {
                            Image(systemName: "checkmark.circle")
                        } else if mgr.sbxrunning {
                            HStack {
                                Text("Running...")
                                ProgressView()
                            }
                        } else if mgr.sbxattempted && mgr.sbxfailed {
                            Image(systemName: "xmark.circle")
                        }
                    }) {
                        Button("Escape Sandbox", action: {
                            mgr.sbxescape()
                        })
                        .disabled(!mgr.dsready || mgr.sbxready || mgr.sbxrunning || isdebugged())
                    }
                }
            }
        } header: {
            HeaderLabel(text: "Kernel Read Write", icon: "externaldrive")
        } footer: {
            if isdebugged() {
                Text("Not available while a debugger is attached.")
            }
        }
    }
    
    private var RCSection: some View {
        Group {
            #if !DISABLE_REMOTECALL
            Section {
                // init remotecall
                LabeledContent(content: {
                    if mgr.rcready {
                        Image(systemName: "checkmark.circle")
                    } else if mgr.rcrunning {
                        HStack {
                            Text("Running...")
                            ProgressView()
                        }
                    } else if mgr.rcfailed {
                        Image(systemName: "xmark.circle")
                    }
                }) {
                    Button("Initalize RemoteCall", action: {
                        mgr.rcinit(process: "SpringBoard", migbypass: false) { success in
                            if success {
                                mgr.logmsg("rc init succeeded!")
                                let pid = mgr.rccall(name: "getpid")
                                mgr.logmsg("remote getpid() returned: \(pid)")
                            } else {
                                mgr.logmsg("rc init failed")
                                mgr.rcfailed = true
                            }
                        }
                    })
                    .disabled(!mgr.dsready || isdebugged() || mgr.rcrunning || mgr.rcready)
                }
                
                // destroy remotecall
                if mgr.rcready {
                    Button("Destroy Remotecall", action: {
                        mgr.rcdestroy()
                    })
                }
            } header: {
                HeaderLabel(text: "RemoteCall", icon: "syringe")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let error = mgr.rcLastError ?? mgr.sbProc?.lastError {
                        Text("Error: \(error)")
                            .foregroundColor(.red)
                    }
                    if RemoteCall.isLiveContainerRuntime() && !RemoteCall.isLiveProcessRuntime() {
                        Text("RemoteCall needs a PAC-enabled LiveContainer launch context. The main exploit may still work when RemoteCall is unavailable.")
                    }
                    if isdebugged() {
                        Text("Not available when a debugger is attached.")
                    }
                    Text("RemoteCall is relatively unstable and may not work properly.")
                    if isIOS16() {
                        Text("iOS 16 tip: Open Control Center after tapping Initialize RemoteCall. This significantly improves the success rate and speed.")
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                        Text("If initialization fails after about 2 minutes, respring, relaunch Lara, and try again.")
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                }
                .font(.footnote)
            }
            #endif
        }
    }
    
    private var ActionsSection: some View {
        Section(header: HeaderLabel(text: "Actions", icon: "wrench.and.screwdriver")) {
            Button("Respring", action: {
                mgr.respring()
            })
            
            Button("Panic!", action: {
                mgr.panic()
            })
            
            if isdebugged() {
                Button("Detach Debugger", action: {
                    exit(0)
                })
            }
        }
    }
    
    private var DebugSection: some View {
        Group {
            if weonadebugbuild_pjbweouttahereexclamationmark {
                if mgr.dsready {
                    Section(header: HeaderLabel(text: "Debug Only", icon: "ant")) {
                        LabeledContent("kernel_base") {
                            Text(String(format: "0x%llx", mgr.kernbase))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        LabeledContent("kernel_slide") {
                            Text(String(format: "0x%llx", mgr.kernslide))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var InlineLogsSection: some View {
        if selectedlogsdisplaymode == .content {
            Section {
                ScrollView {
                    if loggernobs {
                        let combined = logger.logs.joined(separator: "\n")
                        Text(combined)
                            .font(.system(size: 13, design: .monospaced))
                            .lineSpacing(1)
                            .textSelection(.enabled)
                            .onTapGesture {
                                UIPasteboard.general.string = combined
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                    } else {
                        ForEach(Array(logger.logs.enumerated()), id: \.offset) { _, log in
                            Text(log)
                                .font(.system(size: 13, design: .monospaced))
                                .lineSpacing(1)
                                .textSelection(.enabled)
                                .onTapGesture {
                                    UIPasteboard.general.string = log
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                        }
                    }
                }
                .frame(height: 250)
                
                Button("Copy All") {
                    UIPasteboard.general.string = logger.logs.joined(separator: "\n\n")
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                
                Button("Clear") {
                    logger.clear()
                }
                .foregroundColor(.red)
            } header: {
                HeaderLabel(text: "Logs", icon: "terminal")
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(laramgr())
}
