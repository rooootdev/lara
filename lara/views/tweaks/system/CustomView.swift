//
//  CustomView.swift
//  lara
//
//  Created by ruter on 29.03.26.
//

import SwiftUI
import UniformTypeIdentifiers

struct CustomView: View {
    @ObservedObject var mgr: laramgr
    @State private var target: String = "/"
    @State private var showimport = false
    @State private var srcpath: String = ""
    @State private var srcname: String = "No file selected"
    @State private var isoverwriting = false

    var body: some View {
        List {
            Section {
                TextField("/path/to/target", text: $target)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)

                HStack {
                    Text("Source")
                    Spacer()
                    Text(srcname)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Button("Choose Source File") {
                    showimport = true
                }

                Button(isoverwriting ? "Overwriting..." : "Overwrite Target") {
                    guard !isoverwriting else { return }
                    overwrite()
                }
                .disabled(!canoverwrite)
            } header: {
                Text("Custom Path Overwrite")
            } footer: {
                Text("This will overwrite the target file with the contents of the selected source file. Target size must be >= source size.")
            }

            Section {
                Text(globallogger.logs.last ?? "No logs yet")
                    .font(.system(size: 13, design: .monospaced))
            }
        }
        .navigationTitle("Custom Overwrite")
        .fileImporter(
            isPresented: $showimport,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                importsource(url)
            }
        }
    }

    private var canoverwrite: Bool {
        mgr.vfsready && !target.isEmpty && !srcpath.isEmpty && !isoverwriting
    }

    private func importsource(_ url: URL) {
        let fm = FileManager.default
        let tmpdir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dest = tmpdir.appendingPathComponent("customwrite-\(UUID().uuidString)")

        do {
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: url, to: dest)
            srcpath = dest.path
            srcname = url.lastPathComponent
            mgr.logmsg("selected source: \(srcname)")
        } catch {
            mgr.logmsg("failed to import source: \(error.localizedDescription)")
        }
    }

    private func overwrite() {
        guard canoverwrite else { return }
        isoverwriting = true
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = mgr.vfsoverwritefromlocalpath(target: target, source: srcpath)
            DispatchQueue.main.async {
                isoverwriting = false
                ok ? mgr.logmsg("overwrite ok: \(target)") : mgr.logmsg("overwrite failed: \(target)")
            }
        }
    }
}

