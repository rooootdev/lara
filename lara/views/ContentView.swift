//
//  ContentView.swift
//  lara
//
//  Created by ruter on 23.03.26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @AppStorage("showfmintabs") private var showfmintabs: Bool = true
    @ObservedObject private var mgr = laramgr.shared
    @State private var hasoffsets = haskernproc()
    @State private var showsettings = false
    @State private var selectedmethod: method = .hybrid
    
    var body: some View {
        NavigationStack {
            List {
                if !hasoffsets {
                    Section("Setup") {
                        Text("Kernelcache offsets are missing. Download them in Settings.")
                            .foregroundColor(.secondary)
                        Button("Open Settings") {
                            showsettings = true
                        }
                    }
                } else {
                    Section {
                        Button {
                            mgr.run()
                        } label: {
                            if mgr.dsrunning {
                                HStack {
                                    ProgressView(value: mgr.dsprogress)
                                        .progressViewStyle(.circular)
                                        .frame(width: 18, height: 18)
                                    Text("Running...")
                                    Spacer()
                                    Text("\(Int(mgr.dsprogress * 100))%")
                                }
                            } else {
                                if mgr.dsready {
                                    HStack {
                                        Text("Ran Exploit")
                                        Spacer()
                                        Image(systemName: "checkmark.circle")
                                            .foregroundColor(.green)
                                    }
                                } else if mgr.dsattempted && mgr.dsfailed {
                                    HStack {
                                        Text("Exploit Failed")
                                        Spacer()
                                        Image(systemName: "xmark.circle")
                                            .foregroundColor(.red)
                                    }
                                } else {
                                    Text("Run Exploit")
                                }
                            }
                        }
                        .disabled(mgr.dsrunning)
                        .disabled(mgr.dsready)
                        
                        HStack {
                            Text("kernproc:")
                            Spacer()
                            Text(String(format: "0x%llx", getrootvnode()))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("rootvnode:")
                            Spacer()
                            Text(String(format: "0x%llx", getkernproc()))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        if mgr.dsready {
                            HStack {
                                Text("kernel_base:")
                                Spacer()
                                Text(String(format: "0x%llx", mgr.kernbase))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text("kernel_slide:")
                                Spacer()
                                Text(String(format: "0x%llx", mgr.kernslide))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    } header: {
                        Text("Kernel Read Write")
                    } footer: {
                        if g_isunsupported {
                            Text("Your device/installation method may not be supported.")
                        }
                    }

                    Section {
                        if selectedmethod == .vfs {
                            Button {
                                mgr.vfsinit()
                            } label: {
                                if mgr.vfsrunning {
                                    HStack {
                                        ProgressView(value: mgr.vfsprogress)
                                            .progressViewStyle(.circular)
                                            .frame(width: 18, height: 18)
                                        Text("Initialising VFS...")
                                        Spacer()
                                        Text("\(Int(mgr.vfsprogress * 100))%")
                                    }
                                } else if !mgr.vfsready {
                                    if mgr.vfsattempted && mgr.vfsfailed {
                                        HStack {
                                            Text("VFS Init Failed")
                                            Spacer()
                                            Image(systemName: "xmark.circle")
                                                .foregroundColor(.red)
                                        }
                                    } else {
                                        Text("Initialise VFS")
                                    }
                                } else {
                                    HStack {
                                        Text("Initialised VFS")
                                        Spacer()
                                        Image(systemName: "checkmark.circle")
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                            .disabled(!mgr.dsready || mgr.vfsready || mgr.vfsrunning)
                            
                            if mgr.vfsready {
                                NavigationLink("Emoji Overwrite") {
                                    EmojiPicker(mgr: mgr)
                                }
                                
                                NavigationLink("Font Overwrite") {
                                    FontPicker(mgr: mgr)
                                }

                                NavigationLink("Card Overwrite") {
                                    CardView()
                                }
                                
                                NavigationLink("Custom Overwrite") {
                                    CustomView(mgr: mgr)
                                }
                                
                                NavigationLink("DirtyZero (Broken)") {
                                    ZeroView(mgr: mgr)
                                }
                                
                                if !showfmintabs {
                                    NavigationLink("File Manager") {
                                        SantanderView(startPath: "/")
                                    }
                                }
                            }
                        } else if selectedmethod == .sbx {
                            Button {
                                mgr.sbxescape()
                                // mgr.sbxelevate()
                            } label: {
                                if mgr.sbxrunning {
                                    HStack {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .frame(width: 18, height: 18)
                                        Text("Escaping Sandbox...")
                                    }
                                } else if !mgr.sbxready {
                                    if mgr.sbxattempted && mgr.sbxfailed {
                                        HStack {
                                            Text("Sandbox Escape Failed")
                                            Spacer()
                                            Image(systemName: "xmark.circle")
                                                .foregroundColor(.red)
                                        }
                                    } else {
                                        Text("Escape Sandbox")
                                    }
                                } else {
                                    HStack {
                                        Text("Sandbox Escaped")
                                        Spacer()
                                        Image(systemName: "checkmark.circle")
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                            .disabled(!mgr.dsready || mgr.sbxready || mgr.sbxrunning)
                            
                            if mgr.sbxready {
                                if !showfmintabs {
                                    NavigationLink("File Manager") {
                                        SantanderView(startPath: "/")
                                    }
                                }

                                NavigationLink("Card Overwrite") {
                                    CardView()
                                }
                                
                                NavigationLink("3 App Bypass (Broken?)") {
                                    AppsView(mgr: mgr)
                                }
                                
                                NavigationLink("Unblacklist (Broken?)") {
                                    WhitelistView()
                                }
                                
                                if 1 == 2 {
                                    NavigationLink("MobileGestalt") {
                                        EditorView()
                                    }
                                    
                                    NavigationLink("Passcode Theme") {
                                        PasscodeView(mgr: mgr)
                                    }
                                }
                            }
                        } else {
                            if !mgr.sbxattempted {
                                Button {
                                    mgr.sbxescape()
                                } label: {
                                    if mgr.sbxrunning {
                                        HStack {
                                            ProgressView()
                                                .progressViewStyle(.circular)
                                                .frame(width: 18, height: 18)
                                            Text("Escaping Sandbox...")
                                        }
                                    } else if !mgr.sbxready {
                                        if mgr.sbxattempted && mgr.sbxfailed {
                                            HStack {
                                                Text("Sandbox Escape Failed")
                                                Spacer()
                                                Image(systemName: "xmark.circle")
                                                    .foregroundColor(.red)
                                            }
                                        } else {
                                            Text("Escape Sandbox")
                                        }
                                    } else {
                                        HStack {
                                            Text("Sandbox Escaped")
                                            Spacer()
                                            Image(systemName: "checkmark.circle")
                                                .foregroundColor(.green)
                                        }
                                    }
                                }
                                .disabled(!mgr.dsready || mgr.sbxready || mgr.sbxrunning)
                            } else {
                                Button {
                                    mgr.vfsinit()
                                } label: {
                                    if mgr.vfsrunning {
                                        HStack {
                                            ProgressView(value: mgr.vfsprogress)
                                                .progressViewStyle(.circular)
                                                .frame(width: 18, height: 18)
                                            Text("Initialising VFS...")
                                            Spacer()
                                            Text("\(Int(mgr.vfsprogress * 100))%")
                                        }
                                    } else if !mgr.vfsready {
                                        if mgr.vfsattempted && mgr.vfsfailed {
                                            HStack {
                                                Text("VFS Init Failed")
                                                Spacer()
                                                Image(systemName: "xmark.circle")
                                                    .foregroundColor(.red)
                                            }
                                        } else {
                                            Text("Initialise VFS")
                                        }
                                    } else {
                                        HStack {
                                            Text("Initialised Hybrid")
                                            Spacer()
                                            Image(systemName: "checkmark.circle")
                                                .foregroundColor(.green)
                                        }
                                    }
                                }
                                .disabled(!mgr.dsready || mgr.vfsready || mgr.vfsrunning)
                            }
                            
                            if mgr.vfsready && mgr.sbxready {
                                if !showfmintabs {
                                    NavigationLink("File Manager") {
                                        SantanderView(startPath: "/")
                                    }
                                }
                                
                                NavigationLink("Emoji Overwrite") {
                                    EmojiPicker(mgr: mgr)
                                }
                                
                                NavigationLink("Font Overwrite") {
                                    FontPicker(mgr: mgr)
                                }

                                NavigationLink("Card Overwrite") {
                                    CardView()
                                }
                                
                                NavigationLink("Custom Overwrite") {
                                    CustomView(mgr: mgr)
                                }
                                
                                NavigationLink("MobileGestalt") {
                                    EditorView()
                                }
                                
                                NavigationLink("Whitelist") {
                                    WhitelistView()
                                }
                                
                                NavigationLink("DirtyZero") {
                                    ZeroView(mgr: mgr)
                                }
                                
                                if 1 == 2 {
                                    NavigationLink("Passcode Theme") {
                                        PasscodeView(mgr: mgr)
                                    }
                                    
                                    NavigationLink("3 App Bypass (Broken?)") {
                                        AppsView(mgr: mgr)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(selectedmethod == .vfs ? "Virtual File System" : (selectedmethod == .sbx ? "Sandbox Escape" : "Hybrid (SBX + VFS)"))
                    } footer: {
                        if selectedmethod == .sbx {
                            Text("Font Overwrite is only available in VFS or Hybrid mode. (Settings -> Method -> VFS/Hybrid)")
                        }
                    }
                    
                    Section {
                        if mgr.dsready {
                            NavigationLink("Tools") {
                                ToolsView()
                            }
                        }
                        
                        if #unavailable(iOS 18.2) {
                            Button("Respring") {
                                mgr.respring()
                            }
                        }
                        
                        Button("Panic!") {
                            mgr.panic()
                        }
                        .disabled(!mgr.dsready)
                    } header: {
                        Text("Other")
                    }
                }
                
            }
            .navigationTitle("lara")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showsettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .sheet(isPresented: $showsettings) {
            SettingsView(hasoffsets: $hasoffsets)
        }
        .onAppear {
            refreshSelectedMethod()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            refreshSelectedMethod()
        }
    }

    private func refreshSelectedMethod() {
        if let raw = UserDefaults.standard.string(forKey: "selectedmethod"),
           let m = method(rawValue: raw) {
            selectedmethod = m
        }
    }
}
