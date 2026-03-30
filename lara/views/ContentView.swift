//
//  ContentView.swift
//  lara
//
//  Created by ruter on 23.03.26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject private var mgr = laramgr.shared
    @State private var uid: uid_t = getuid()
    @State private var pid: pid_t = getpid()
    @State private var hasoffsets = haskernproc()
    @State private var showsettings = false
    @State private var showingGestaltEditor = false
    
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
                    Section("Kernel Read Write") {
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
                    }

                    Section("Virtual File System") {
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
                            NavigationLink("Font Overwrite") {
                                FontPicker(mgr: mgr)
                            }
                            NavigationLink("DirtyZero (Broken)") {
                                ZeroView(mgr: mgr)
                            }
                            
                            if 1 == 2 {
                                NavigationLink("3 App Bypass") {
                                    AppsView(mgr: mgr)
                                }
                                
                                NavigationLink("Passcode Theme") {
                                    PasscodeView(mgr: mgr)
                                }
                                
                                NavigationLink("Unblacklist") {
                                    WhitelistView()
                                }

                                NavigationLink("MobileGestalt") {
                                    EditorView()
                                }
                            }
                        }
                        
                        HStack {
                            Text("UID:")
                            
                            Spacer()
                            
                            Text("\(uid)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                            
                            Button {
                                uid = getuid()
                                print(uid)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        
                        HStack {
                            Text("PID:")
                            
                            Spacer()
                            
                            Text("\(pid)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                            
                            Button {
                                pid = getpid()
                                print(pid)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    }
                    
                    Section {
                        if #unavailable(iOS 18.2) {
                            Button("Respring") {
                                mgr.respring()
                            }
                        }
                        
                        Button("Panic!") {
                            mgr.panic()
                        }
                        .disabled(!mgr.dsready)
                        Button(action: {
                            showingGestaltEditor = true
                        }) {
                            Text("Modify MobileGestalt")
                            .font(.system(size: 15, weight: .bold)
                                  .foregroundColor(.blue)
                                  .cornerRadius(10)
                                 }
                            .sheet(isPresented: $showingGestaltEditor) {
                                GestaltEditorView()
                            }
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
    }
}
