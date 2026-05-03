//
//  VarCleanView.swift
//  lara
//
//  credits to: m1337v
//

import SwiftUI

private struct varcleanmatch: Identifiable, Hashable {
    let path: String
    let name: String
    let isdir: Bool
    let issymlink: Bool
    var isselected: Bool

    var id: String { path }
}

private struct varcleangroup: Identifiable, Hashable {
    let path: String
    var items: [varcleanmatch]

    var id: String { path }
}

struct VarCleanView: View {
    @ObservedObject private var mgr = laramgr.shared
    @State private var groups: [varcleangroup] = []
    @State private var isrefreshing = false
    @State private var isdeleting = false
    @State private var statusmsg: String?
    @State private var showdeleteconfirm = false

    private var cleanupok: Bool { mgr.sbxready }

    private var selectedcount: Int {
        groups.reduce(0) { $0 + $1.items.filter(\.isselected).count }
    }

    var body: some View {
        List {
            Section("Status") {
                Text(cleanupok
                     ? "Cleanup enabled via sandbox escape."
                     : "Detection only. Escape the sandbox to delete matched paths.")
                    .foregroundColor(.secondary)

                if let statusmsg, !statusmsg.isEmpty {
                    Text(statusmsg)
                        .foregroundColor(.secondary)
                        .font(.footnote)
                }
            }

            if groups.isEmpty && !isrefreshing {
                Section("Matches") {
                    Text("No blacklisted residue from VarCleanRules.json was found.")
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(groups.indices, id: \.self) { groupidx in
                    Section(groups[groupidx].path) {
                        ForEach(groups[groupidx].items.indices, id: \.self) { itemidx in
                            let item = groups[groupidx].items[itemidx]
                            Button {
                                guard cleanupok else { return }
                                groups[groupidx].items[itemidx].isselected.toggle()
                            } label: {
                                HStack(spacing: 12) {
                                    Text(item.issymlink ? "🔗" : (item.isdir ? "🗂️" : "📄"))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .foregroundColor(.primary)
                                        Text(item.path)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    if cleanupok {
                                        Image(systemName: item.isselected ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(item.isselected ? .red : .secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(!cleanupok)
                        }
                    }
                }
            }
        }
        .navigationTitle("VarClean")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await refresh() }
                } label: {
                    if isrefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isrefreshing || isdeleting)

                Button(selectedcount == 0 ? "Select All" : "Clear") {
                    toggleselection()
                }
                .disabled(!cleanupok || groups.isEmpty || isdeleting)

                Button("Clean") {
                    showdeleteconfirm = true
                }
                .disabled(!cleanupok || selectedcount == 0 || isdeleting)
            }
        }
        .task {
            await refresh()
        }
        .alert("Delete Selected Items?", isPresented: $showdeleteconfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteselected() }
            }
        } message: {
            Text("Delete \(selectedcount) matched path\(selectedcount == 1 ? "" : "s")?")
        }
    }

    private func toggleselection() {
        let shouldselect = selectedcount == 0
        for groupidx in groups.indices {
            for itemidx in groups[groupidx].items.indices {
                groups[groupidx].items[itemidx].isselected = shouldselect
            }
        }
    }

    @MainActor
    private func refresh() async {
        guard !isrefreshing else { return }
        isrefreshing = true
        defer { isrefreshing = false }

        let newgroups = await Task.detached(priority: .userInitiated) {
            loadvarcleangroups()
        }.value

        groups = newgroups
        if groups.isEmpty {
            statusmsg = nil
        } else {
            let matchcount = groups.reduce(0) { $0 + $1.items.count }
            statusmsg = "Found \(matchcount) matched path\(matchcount == 1 ? "" : "s")."
        }
    }

    @MainActor
    private func deleteselected() async {
        guard cleanupok else { return }
        isdeleting = true
        defer { isdeleting = false }

        let selectedpaths = groups
            .flatMap(\.items)
            .filter(\.isselected)
            .map(\.path)
            .sorted { $0.count > $1.count }

        var deletedcount = 0
        var failures: [String] = []
        let filemgr = FileManager.default

        for path in selectedpaths {
            do {
                if filemgr.fileExists(atPath: path) {
                    try filemgr.removeItem(atPath: path)
                }
                deletedcount += 1
            } catch {
                failures.append("\(path): \(error.localizedDescription)")
            }
        }

        if failures.isEmpty {
            statusmsg = "Deleted \(deletedcount) path\(deletedcount == 1 ? "" : "s")."
        } else {
            statusmsg = "Deleted \(deletedcount) path\(deletedcount == 1 ? "" : "s"), failed \(failures.count)."
        }

        await refresh()
    }
}

private func loadvarcleangroups() -> [varcleangroup] {
    var error: NSError?
    guard let rules = VarCleanBridge.loadRulesNamed("VarCleanRules", in: .main, error: &error) as? [String: Any] else {
        return []
    }

    var grouped: [String: [varcleanmatch]] = [:]
    var seenpaths = Set<String>()
    var direntriescache: [String: [String]] = [:]
    let sortedrulepaths = rules.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

    for basepath in sortedrulepaths {
        guard let rule = rules[basepath] as? [String: Any],
              let blacklist = rule["blacklist"] as? [Any] else {
            continue
        }

        for probepath in probepaths(
            for: basepath,
            blacklist: blacklist,
            seenpaths: &seenpaths,
            direntriescache: &direntriescache
        ) {
            var isdir = ObjCBool(false)
            var issymlink = ObjCBool(false)
            guard VarCleanBridge.probePathExists(probepath, isDirectory: &isdir, isSymlink: &issymlink) else {
                continue
            }

            let grouppath = (probepath as NSString).deletingLastPathComponent.isEmpty
                ? "/"
                : (probepath as NSString).deletingLastPathComponent

            let match = varcleanmatch(
                path: probepath,
                name: (probepath as NSString).lastPathComponent,
                isdir: isdir.boolValue,
                issymlink: issymlink.boolValue,
                isselected: false
            )
            grouped[grouppath, default: []].append(match)
        }
    }

    let sortedgroups = grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    return sortedgroups.map { grouppath in
        let items = (grouped[grouppath] ?? [])
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return varcleangroup(path: grouppath, items: items)
    }
}

private func probepaths(
    for basepath: String,
    blacklist: [Any],
    seenpaths: inout Set<String>,
    direntriescache: inout [String: [String]]
) -> [String] {
    var out: [String] = []

    for entry in blacklist {
        if let name = entry as? String, !name.isEmpty {
            let probepath = (basepath as NSString).appendingPathComponent(name)
            if seenpaths.insert(probepath).inserted {
                out.append(probepath)
            }
            continue
        }

        guard let condition = entry as? [String: Any],
              let matchtype = condition["match"] as? String,
              matchtype == "regexp",
              let pattern = condition["name"] as? String,
              let regex = try? NSRegularExpression(pattern: pattern) else {
            continue
        }

        let entries = direntries(atpath: basepath, cache: &direntriescache)
        for name in entries where regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil {
            let probepath = (basepath as NSString).appendingPathComponent(name)
            if seenpaths.insert(probepath).inserted {
                out.append(probepath)
            }
        }
    }

    return out
}

private func direntries(atpath path: String, cache: inout [String: [String]]) -> [String] {
    if let cached = cache[path] {
        return cached
    }

    let entries = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
    cache[path] = entries
    return entries
}
