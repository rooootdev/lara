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
    @State private var hasoffsets = true
    @State private var showsettings = false
    @State private var selectedmethod: method = .hybrid

    let os = ProcessInfo().operatingSystemVersion

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
                            offsets_init()
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
                        .disabled(isdebugged())

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
                        
                        if isdebugged() {
                            Button {
                                exit(0)
                            } label: {
                                Text("Detach")
                            }
                            .foregroundColor(.red)
                        }
                    } header: {
                        Text("Kernel Read Write")
                    } footer: {
                        if g_isunsupported {
                            Text("Your device/installation method may not be supported.")
                        }
                        
                        if isdebugged() {
                            Text("Not available while debugger is attached.")
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
                                NavigationLink("Tweaks") {
                                    List {
                                        Section {
                                            NavigationLink {
                                                FontPicker(mgr: mgr)
                                            } label: {
                                                Label("Font Overwrite", systemImage: "textformat.alt")
                                            }

                                            NavigationLink {
                                                CardView()
                                            } label: {
                                                Label("Card Overwrite", systemImage: "creditcard")
                                            }

                                            NavigationLink {
                                                ZeroView(mgr: mgr)
                                            } label: {
                                                Label("DirtyZero", systemImage: "doc")
                                            }
                                        } header: {
                                            Text("UI Tweaks")
                                        }

                                        Section {
                                            if !showfmintabs {
                                                NavigationLink {
                                                    SantanderView(startPath: "/")
                                                } label: {
                                                    Label("File Manager", systemImage: "folder")
                                                }
                                            }
                                            
                                            NavigationLink {
                                                CustomView(mgr: mgr)
                                            } label: {
                                                Label("Custom Overwrite", systemImage: "pencil")
                                            }
                                        } header: {
                                            Text("Other")
                                        }
                                    }
                                    .navigationTitle(Text("Tweaks"))
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
                                NavigationLink("Tweaks") {
                                    List {
                                        Section {
                                            NavigationLink {
                                                CardView()
                                            } label: {
                                                Label("Card Overwrite", systemImage: "creditcard")
                                            }
                                        } header: {
                                            Text("UI Tweaks")
                                        }

                                        Section {
                                            NavigationLink {
                                                AppsView(mgr: mgr)
                                            } label: {
                                                Label("3 App Bypass", systemImage: "lock.open.fill")
                                            }

                                            NavigationLink {
                                                WhitelistView()
                                            } label: {
                                                Label("Unblacklist", systemImage: "checkmark.seal")
                                            }
                                        } header: {
                                            Text("App Management")
                                        }

                                        Section {
                                            if !showfmintabs {
                                                NavigationLink {
                                                    SantanderView(startPath: "/")
                                                } label: {
                                                    Label("File Manager", systemImage: "folder")
                                                }
                                            }
                                        } header: {
                                            Text("Filesystem")
                                        }

                                        Section {
                                            NavigationLink {
                                                VarCleanView()
                                            } label: {
                                                Label("VarClean", systemImage: "sparkles")
                                            }
                                        } header: {
                                            Text("Cleanup")
                                        }

                                        if 1 == 2 {
                                            NavigationLink {
                                                EditorView()
                                            } label: {
                                                Label("MobileGestalt", systemImage: "gear")
                                            }
                                            NavigationLink {
                                                PasscodeView(mgr: mgr)
                                            } label: {
                                                Label("Passcode Theme", systemImage: "1.circle")
                                            }
                                        }
                                    }
                                    .navigationTitle(Text("Tweaks"))
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
                                NavigationLink("Tweaks") {
                                    List {
                                        Section {
                                            NavigationLink {
                                                FontPicker(mgr: mgr)
                                            } label: {
                                                Label("Font Overwrite", systemImage: "textformat.alt")
                                            }

                                            NavigationLink {
                                                CardView()
                                            } label: {
                                                Label("Card Overwrite", systemImage: "creditcard")
                                            }

                                            NavigationLink {
                                                ZeroView(mgr: mgr)
                                            } label: {
                                                Label("DirtyZero", systemImage: "doc")
                                            }
                                            
                                            if 1 == 2 {
                                                NavigationLink {
                                                    DarkBoardView()
                                                } label: {
                                                    Label("DarkBoard", systemImage: "app.badge")
                                                }
                                            }
                                            
                                            if os.majorVersion >= 26 {
                                                NavigationLink {
                                                    LGView()
                                                } label: {
                                                    Label("Liquid Glass", systemImage: "capsule")
                                                }
                                            }
                                        } header: {
                                            Text("SpringBoard")
                                        }
                                        Section {
                                            NavigationLink() {
                                                PasscodeView(mgr: mgr)
                                            } label: {
                                                Label("Passcode Theme", systemImage: "key")
                                            }
                                        } header: {
                                            Text("Lockscreen")
                                        }
                                        Section {
                                            NavigationLink {
                                                AppsView(mgr: mgr)
                                            } label: {
                                                Label("3 App Bypass", systemImage: "lock.open.fill")
                                            }
                                            NavigationLink {
                                                WhitelistView()
                                            } label: {
                                                Label("Unblacklist", systemImage: "checkmark.seal")
                                            }
                                        } header: {
                                            Text("App Management")
                                        }
                                        Section {
                                            if !showfmintabs {
                                                NavigationLink {
                                                    SantanderView(startPath: "/")
                                                } label: {
                                                    Label("File Manager", systemImage: "folder")
                                                }
                                            }

                                            NavigationLink {
                                                CustomView(mgr: mgr)
                                            } label: {
                                                Label("Custom Overwrite", systemImage: "pencil")
                                            }

                                            NavigationLink {
                                                EditorView()
                                            } label: {
                                                Label("MobileGestalt", systemImage: "gear")
                                            }
                                        } header: {
                                            Text("Filesystem")
                                        }

                                        Section {
                                            NavigationLink {
                                                VarCleanView()
                                            } label: {
                                                Label("VarClean", systemImage: "sparkles")
                                            }
                                        } header: {
                                            Text("Cleanup")
                                        }

                                        if 1 == 2 {
                                            NavigationLink("Control Center") {
                                                CCView()
                                            }
                                        }
                                    }
                                    .navigationTitle(Text("Tweaks"))
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

                    #if !DISABLE_REMOTECALL
                    Section {
                        Button {
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
                        } label: {
                            if mgr.rcrunning {
                                Text("Initialising RemoteCall...")
                            } else if !mgr.rcready {
                                Text("Initialise RemoteCall")
                            } else {
                                HStack {
                                    Text("Initialised RemoteCall")
                                    Spacer()
                                    Image(systemName: "checkmark.circle")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .disabled(!mgr.dsready || mgr.rcready)
                        .disabled(isdebugged())

                        if mgr.rcready {
                            NavigationLink("Tweaks") {
                                RemoteView(mgr: mgr)
                            }

                            Button("Destroy RemoteCall") {
                                mgr.rcdestroy()
                            }
                        }
                        
                        if isdebugged() {
                            Button {
                                exit(0)
                            } label: {
                                Text("Detach")
                            }
                            .foregroundColor(.red)
                        }
                    } header: {
                        Text("RemoteCall")
                    } footer: {
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
                    }
                    .disabled(mgr.rcrunning)
                    #endif

                    Section {
                        if mgr.dsready {
                            NavigationLink("TrollStore Installer") {
                                TrollStoreInstallerView(mgr: mgr)
                            }

                            NavigationLink("Tools") {
                                ToolsView()
                            }
                        }

                        Button("Respring") {
                            mgr.respring()
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
            SettingsView(mgr: mgr, hasoffsets: $hasoffsets)
        }
        .onAppear {
            refreshselectedmethod()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            refreshselectedmethod()
        }
    }

    private func refreshselectedmethod() {
        if let raw = UserDefaults.standard.string(forKey: "selectedmethod"),
           let m = method(rawValue: raw) {
            selectedmethod = m
        }
    }
}
