//
//  ToolsView.swift
//  lara
//
//  Created by ruter on 04.04.26.
//

import SwiftUI

struct ToolsView: View {
    private enum tokenclass: String, CaseIterable, Identifiable {
        case read = "com.apple.app-sandbox.read"
        case write = "com.apple.app-sandbox.write"
        case readWrite = "com.apple.app-sandbox.read-write"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .read: return "read"
            case .write: return "write"
            case .readWrite: return "read-write"
            }
        }
    }

    @ObservedObject private var mgr = laramgr.shared
    @State private var isaslr: Bool = aslrstate
    @State var showtoken: Bool = false
    @AppStorage("lara.sbx.issuedToken") private var token: String = ""
    @State private var issueclass: tokenclass = .readWrite
    @State private var issuepath: String = "/"
    @State private var uid: uid_t = getuid()
    @State private var pid: pid_t = getpid()
    
    var body: some View {
        List {
            if !mgr.dsready {
                Section {
                    Text("Kernel R/W is not ready. Run the exploit first.")
                        .foregroundColor(.secondary)
                } header: {
                    Text("Status")
                }
            }

            Section {
                HStack {
                    Text("ASLR:")
                    
                    Spacer()
                    
                    Text(isaslr ? "enabled" : "disabled")
                        .foregroundColor(isaslr ? Color.red : Color.green)
                        .monospaced()
                    
                    Button {
                        isaslr = aslrstate
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                
                Button {
                    toggleaslr()
                    isaslr = aslrstate
                } label: {
                    Text("Toggle ASLR")
                }
            } header: {
                Text("ASLR")
            } footer: {
                Text("Address Space Layout Randomization. Probably not useful for you.")
            }
            
            Section {
                Button("Respring") {
                    mgr.respring()
                }
                
                HStack {
                    Text("ourproc: ")
                    Spacer()
                    Text(mgr.dsready ? String(format: "0x%llx", ds_get_our_proc()) : "N/A")
                        .foregroundColor(.secondary)
                        .monospaced()
                }
                
                HStack {
                    Text("ourtask: ")
                    Spacer()
                    Text(mgr.dsready ? String(format: "0x%llx", ds_get_our_task()) : "N/A")
                        .foregroundColor(.secondary)
                        .monospaced()
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
            } header: {
                Text("Process")
            }

            Section {
                NavigationLink("LaraJIT") {
                    JitView()
                }
                .disabled(!mgr.dsready)
            } header: {
                Text("JIT")
            } footer: {
                Text("Currently broken.")
            }
            
            Section {
                HStack {
                    if showtoken {
                        Text(mgr.sbxready ? "tkn" : "No Saved Token.")
                            .foregroundColor(.secondary)
                            .monospaced()
                    } else {
                        if !token.isEmpty {
                            Text(token)
                                .foregroundColor(.secondary)
                                .monospaced()
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("No Saved Token.")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button {
                        UIPasteboard.general.string = token.isEmpty ? nil : token
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .disabled(token.isEmpty)
                }
                .contextMenu {
                    if !token.isEmpty {
                        Button {
                            UIPasteboard.general.string = token
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                }

                HStack {
                    Text("Class:")
                    Spacer()

                    Picker(" ", selection: $issueclass) {
                        ForEach(tokenclass.allCases) { tokenClass in
                            Text(tokenClass.label).tag(tokenClass)
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack {
                    Text("Path:")
                    Spacer()
                    
                    TextField("/", text: $issuepath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundColor(.secondary)
                        .monospaced()
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Button {
                    token = mgr.sbxissuetoken(extClass: issueclass.rawValue, path: issuepath) ?? ""
                } label: {
                    Text("Issue Token")
                }
                .disabled(!mgr.sbxready)
            } header: {
                Text("Sandbox")
            }
        }
        .navigationTitle("Tools")
        .onAppear {
            if mgr.dsready {
                getaslrstate()
                isaslr = aslrstate
            }
        }
    }
}
