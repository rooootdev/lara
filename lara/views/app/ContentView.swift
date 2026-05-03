//
//  ContentView.swift
//  lara
//
//  Created by ruter on 23.03.26.
//

import SwiftUI
import UniformTypeIdentifiers
import PartyUI

struct ContentView: View {
    @ObservedObject private var mgr = laramgr.shared
    
    @State private var hasOffsets: Bool = false
    
    @State private var theaderText: String = "Offsets are missing!"
    @State private var theaderIcon: String = "exclamationmark.triangle.fill"
    
    @State private var showSettings: Bool = false
    
    @AppStorage("showfmintabs") private var showfmintabs: Bool = true
    @AppStorage("selectedMethod") private var selectedMethod: method = .hybrid
    
    init() {
        globallogger.capture()
    }
    
    var body: some View {
        NavigationStack {
            List {
                //DebugSection
                KRWSection
                RCSection
                ActionsSection
            }
            .navigationTitle("lara")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        mgr.showLogs.toggle()
                    }) {
                        Image(systemName: "terminal")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        showSettings.toggle()
                    }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(mgr: mgr, hasoffsets: $hasOffsets)
            }
        }
    }
    
    private var DebugSection: some View {
        Section(header: HeaderLabel(text: "Debugging", icon: "ant")) {
            if mgr.dsready {
                LabeledContent("kernel_base") {
                    Text(String(format: "0x%llx", mgr.kernslide))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                LabeledContent("kernel_slide") {
                    Text(String(format: "0x%llx", mgr.kernslide))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            if isdebugged() {
                Button("Detach", role: .destructive, action: {
                    exit(0)
                })
            }
        }
    }
    
    private var KRWSection: some View {
        Section(header: HeaderLabel(text: "Kernel Read Write", icon: "wrench.and.screwdriver"), footer: Text(isdebugged() ? "Not available while a debugger is attached." : "Depending on your device configuration, this may not function properly.")) {
            if hasOffsets {
                PlainAlert(title: "Kernelcache offsets missing!", icon: "exclamationmark.triangle.fill", text: "lara needs to download kernelcache offsets in order for the exploit to function properly. Download them in settings.")
            } else {
                VStack {
                    Button(action: {
                        offsets_init()
                        mgr.run()
                    }) {
                        if mgr.dsready {
                            ButtonLabel(text: "Exploit Successful", icon: "checkmark")
                        } else if mgr.dsrunning {
                            ButtonLabel(text: "Running Exploit... (\(Int(mgr.dsprogress * 100))%)", icon: "showMeProgressPlease")
                        } else if mgr.dsattempted && mgr.dsfailed {
                            ButtonLabel(text: "Exploit Failed!", icon: "xmark")
                        } else {
                            ButtonLabel(text: "Run Exploit", icon: "cpu")
                        }
                    }
                    .buttonStyle(TranslucentButtonStyle(color: mgr.dsattempted && mgr.dsfailed ? .red : .accentColor))
                    .disabled(mgr.dsready || mgr.dsrunning)
                    
                    if selectedMethod == .hybrid {
                        Button(action: {
                            mgr.vfsinit()
                            mgr.sbxescape()
                        }) {
                            if mgr.vfsready && mgr.sbxready {
                                ButtonLabel(text: "Initialized System", icon: "checkmark")
                            } else if mgr.vfsrunning || mgr.sbxrunning {
                                ButtonLabel(text: "Running...", icon: "showMeProgressPlease")
                            } else if mgr.vfsattempted && mgr.vfsfailed || mgr.sbxattempted && mgr.sbxfailed {
                                ButtonLabel(text: "Failed!", icon: "xmark")
                            } else {
                                ButtonLabel(text: "Initalize System", icon: "folder")
                            }
                        }
                        .buttonStyle(TranslucentButtonStyle(color: mgr.vfsattempted && mgr.vfsfailed || mgr.sbxattempted && mgr.sbxfailed ? .red : .purple))
                        .disabled(!mgr.dsready || mgr.vfsrunning || mgr.sbxrunning || mgr.vfsready && mgr.sbxready)
                    }
                    
                    if selectedMethod == .vfs {
                        Button(action: {
                            mgr.vfsinit()
                        }) {
                            if mgr.vfsready {
                                ButtonLabel(text: "VFS Initialized", icon: "checkmark")
                            } else if mgr.vfsrunning {
                                ButtonLabel(text: "Initializing VFS... (\(Int(mgr.vfsprogress * 100))%)", icon: "showMeProgressPlease")
                            } else if mgr.vfsattempted && mgr.vfsfailed {
                                ButtonLabel(text: "VFS Failed!", icon: "xmark")
                            } else {
                                ButtonLabel(text: "Initialize VFS", icon: "folder")
                            }
                        }
                        .buttonStyle(TranslucentButtonStyle(color: mgr.vfsattempted && mgr.vfsfailed ? .red : .yellow))
                        .disabled(!mgr.dsready || mgr.vfsrunning || mgr.vfsready)
                    }
                    
                    if selectedMethod == .sbx {
                        Button(action: {
                            mgr.sbxescape()
                        }) {
                            if mgr.sbxready {
                                ButtonLabel(text: "Escaped Sandbox", icon: "checkmark")
                            } else if mgr.sbxrunning {
                                ButtonLabel(text: "Escaping Sandbox...", icon: "showMeProgressPlease")
                            } else if mgr.sbxattempted && mgr.sbxfailed {
                                ButtonLabel(text: "Escape Failed!", icon: "xmark")
                            } else {
                                ButtonLabel(text: "Escape Sandbox", icon: "shippingbox")
                            }
                        }
                        .buttonStyle(TranslucentButtonStyle(color: mgr.sbxattempted && mgr.sbxfailed ? .red : .yellow))
                        .disabled(!mgr.dsready || mgr.sbxrunning || mgr.sbxready)
                    }
                }
            }
        }
    }
    
    private var RCSection: some View {
        Group {
            #if !DISABLE_REMOTECALL
            Section(header: HeaderLabel(text: "RemoteCall (SB Injection)", icon: "house"), footer: Group {
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
                Text("RemoteCall is still in development and may not work properly 100% of the time.")
            }) {
                VStack {
                    Button(action: {
                        mgr.logmsg("T")
                        mgr.rcinit(process: "SpringBoard", migbypass: false) { success in
                            if success {
                                mgr.logmsg("rc init succeeded!")
                                let pid = mgr.rccall(name: "getpid")
                                mgr.logmsg("remote getpid() returned: \(pid)")
                            } else {
                                mgr.logmsg("rc init failed")
                            }
                        }
                    }) {
                        if mgr.rcready {
                            ButtonLabel(text: "Initialized RemoteCall", icon: "checkmark")
                        } else if mgr.rcrunning {
                            ButtonLabel(text: "Initializing RemoteCall...", icon: "showMeProgressPlease")
                        } else {
                            ButtonLabel(text: "Initialize RemoteCall", icon: "house")
                        }
                    }
                    .buttonStyle(TranslucentButtonStyle())
                    .disabled(!mgr.dsready || mgr.rcready)
                    .disabled(isdebugged())
                    
                    Button(action: {
                        mgr.rcdestroy()
                    }) {
                        ButtonLabel(text: "Destroy RemoteCall", icon: "trash")
                    }
                    .buttonStyle(TranslucentButtonStyle())
                    .disabled(!mgr.rcready)
                }
            }
            #endif
        }
    }
    
    private var ActionsSection: some View {
        Section(header: HeaderLabel(text: "Actions", icon: "wrench.and.screwdriver")) {
            HStack {
                Button(action: {
                    mgr.respring()
                }) {
                    ButtonLabel(text: "Respring", icon: "goforward")
                }
                .buttonStyle(TranslucentButtonStyle(color: .orange))
                
                Button(action: {
                    mgr.panic()
                }) {
                    ButtonLabel(text: "Panic", icon: "ant")
                }
                .buttonStyle(TranslucentButtonStyle(color: .purple))
                .disabled(!mgr.dsready)
            }
            if mgr.dsready {
                NavigationLink("Tools", destination: ToolsView())
            }
        }
    }
}

#Preview {
    ContentView()
}
