//
//  ToolsView.swift
//  lara
//
//  Created by ruter on 04.04.26.
//

import SwiftUI

struct procentry: Identifiable, Hashable {
    let id = UUID()
    let pid: Int32
    let name: String
}

struct ToolsView: View {
    @ObservedObject private var mgr = laramgr.shared
    @State private var isaslr: Bool = aslrstate
    @State var showtoken: Bool = false
    @AppStorage("lara.sbx.issuedToken")
    private var token: String = ""
    @State private var issueclass: tokenclass = .rw
    @State private var issuepath: String = "/"
    @State private var uid: uid_t = getuid()
    @State private var pid: pid_t = getpid()
    @State private var status: String?
    @State private var crashname: String = "SpringBoard"
    @State private var pausedProcesses: Set<String> = []

    private enum tokenclass: String, CaseIterable, Identifiable {
        case read = "com.apple.app-sandbox.read"
        case write = "com.apple.app-sandbox.write"
        case rw = "com.apple.app-sandbox.read-write"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .read:
                return "read"

            case .write:
                return "write"

            case .rw:
                return "read-write"
            }
        }
    }

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
                        .foregroundColor(
                            isaslr ? Color.red : Color.green
                        )
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
                    Text("ourproc:")

                    Spacer()

                    Text(
                        mgr.dsready
                        ? String(format: "0x%llx", ds_get_our_proc())
                        : "N/A"
                    )
                    .foregroundColor(.secondary)
                    .monospaced()
                }

                HStack {
                    Text("ourtask:")

                    Spacer()

                    Text(
                        mgr.dsready
                        ? String(format: "0x%llx", ds_get_our_task())
                        : "N/A"
                    )
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
                    Text("Number of Processes:")
                    
                    Spacer()
                    
                    Text("\(count_pid())")
                    
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

                HStack {
                    Text("Process:")

                    Spacer()

                    TextField(
                        "e.g. SpringBoard",
                        text: $crashname
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(.secondary)
                    .monospaced()
                    .fixedSize(
                        horizontal: true,
                        vertical: false
                    )
                }

                Button("Crash") {
                    crashname.withCString { cstr in
                        _ = crashproc(cstr)
                    }
                }
                .disabled(crashname.isEmpty)

                Button("Pause") {
                    crashname.withCString { cstr in
                        _ = proc_pause_resume(cstr, false)
                    }

                    pausedProcesses.insert(crashname)
                }
                .disabled(
                    crashname.isEmpty ||
                    pausedProcesses.contains(crashname)
                )

                Button("Resume") {
                    crashname.withCString { cstr in
                        _ = proc_pause_resume(cstr, true)
                    }

                    pausedProcesses.remove(crashname)
                }
                .disabled(
                    crashname.isEmpty ||
                    !pausedProcesses.contains(crashname)
                )

            } header: {
                Text("Task Manager")

            } footer: {
                Text("Pause, Resume or Crash the selected process")
            }

            Section {

                Button {

                    if mgr.PPHelper() {
                        status = """
                        Succeeded. Open the Pocket Poster app, \
                        open settings and tap Detect.
                        """

                    } else {
                        status = "Failed. Check logs."
                    }

                } label: {
                    Text("Pocket Poster Helper")
                }
                .disabled(!mgr.sbxready)

            } header: {
                Text("Pocket Poster")

            } footer: {
                Text(
                    """
                    Get the needed hashes for Pocket Poster \
                    without the need of a PC.
                    """
                )
            }

            Section {

                HStack {

                    if showtoken {

                        Text(
                            mgr.sbxready
                            ? "tkn"
                            : "No Saved Token."
                        )
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
                        UIPasteboard.general.string =
                            token.isEmpty ? nil : token

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
                            Label(
                                "Copy",
                                systemImage: "doc.on.doc"
                            )
                        }
                    }
                }

                HStack {

                    Text("Class:")

                    Spacer()

                    Picker(" ", selection: $issueclass) {

                        ForEach(tokenclass.allCases) {
                            tokenClass in

                            Text(tokenClass.label)
                                .tag(tokenClass)
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
                        .fixedSize(
                            horizontal: true,
                            vertical: false
                        )
                }

                Button {
                    token =
                        mgr.sbxissuetoken(
                            extClass: issueclass.rawValue,
                            path: issuepath
                        ) ?? ""

                } label: {
                    Text("Issue Token")
                }
                .disabled(!mgr.sbxready)

            } header: {
                Text("Sandbox")
            }
        }
        .navigationTitle("Tools")

        .alert(
            "Status",
            isPresented: .constant(status != nil)
        ) {
            Button("OK") {
                status = nil
            }

        } message: {
            Text(status ?? "")
        }

        .onAppear {

            if mgr.dsready {
                getaslrstate()
                isaslr = aslrstate
            }
        }
    }
}
