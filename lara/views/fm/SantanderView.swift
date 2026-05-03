//
//  SantanderView.swift
//  symlin2k
//
//  Created by ruter on 15.02.26.
//

import SwiftUI
import UniformTypeIdentifiers
import AVKit
import UIKit
import Combine

struct SantanderView: View {
    let startpath: String

    @AppStorage("selectedmethod") private var selectedmethod: method = .hybrid
    @ObservedObject private var mgr = laramgr.shared

    init(startPath: String = "/") {
        self.startpath = startPath.isEmpty ? "/" : startPath
    }

    private var readsbx: Bool {
        selectedmethod != .vfs
    }

    private var writevfs: Bool {
        selectedmethod != .sbx
    }

    private var ready: Bool {
        switch selectedmethod {
        case .sbx:
            return mgr.sbxready
        case .vfs:
            return mgr.vfsready
        case .hybrid:
            return mgr.sbxready && mgr.vfsready
        }
    }

    var body: some View {
        Group {
            if ready {
                santanderroot(startpath: startpath, readsbx: readsbx, writevfs: writevfs)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 36, weight: .semibold))

                    Text("File Manager not ready")
                        .font(.headline)

                    Text("1. Switch to hybrid mode in settings\n2. Escape the Sandbox\n3. Initialise VFS\n4. Try again.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
    }
}

private struct santanderroot: View {
    let readsbx: Bool
    let writevfs: Bool

    @StateObject private var nav: santandernav

    init(startpath: String, readsbx: Bool, writevfs: Bool) {
        self.readsbx = readsbx
        self.writevfs = writevfs
        _nav = StateObject(wrappedValue: santandernav(root: santanderitem(path: startpath, isdir: true)))
    }

    var body: some View {
        NavigationStack(path: $nav.stack) {
            santanderdirview(item: nav.root, readsbx: readsbx, writevfs: writevfs)
                .environmentObject(nav)
                .navigationDestination(for: santanderitem.self) { item in
                    if item.isdir {
                        santanderdirview(item: item, readsbx: readsbx, writevfs: writevfs)
                            .environmentObject(nav)
                    } else {
                        santanderfileview(item: item, readsbx: readsbx, writevfs: writevfs)
                    }
                }
        }
    }
}

private final class santandernav: ObservableObject {
    @Published var root: santanderitem
    @Published var stack: [santanderitem] = []

    init(root: santanderitem) {
        self.root = root
    }

    func go(_ item: santanderitem) {
        root = item
        stack.removeAll()
    }
}

private struct santanderitem: Identifiable, Hashable {
    let path: String
    let name: String
    let display: String
    let isdir: Bool
    let type: UTType?

    var id: String { path }

    init(path: String, isdir: Bool, display: String? = nil) {
        self.path = path
        self.isdir = isdir
        let name = path == "/" ? "/" : (path as NSString).lastPathComponent
        self.name = name
        self.display = display ?? name
        let ext = (path as NSString).pathExtension
        self.type = ext.isEmpty ? nil : UTType(filenameExtension: ext)
    }

    var icon: String {
        if isdir { return "folder.fill" }
        guard let type else { return "doc" }
        if type.isSubtype(of: .text) { return "doc.text" }
        if type.isSubtype(of: .image) { return "photo" }
        if type.isSubtype(of: .audio) { return "waveform" }
        if type.isSubtype(of: .movie) || type.isSubtype(of: .video) { return "play.rectangle" }
        return "doc"
    }
}

private struct santanderclipitem {
    let path: String
    let isdir: Bool
    let name: String
}

private final class santanderclip: ObservableObject {
    static let shared = santanderclip()
    @Published var item: santanderclipitem?
    private init() {}
}

private struct santandermsg: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}

private enum santandersort: String, CaseIterable {
    case az
    case za
}

private struct santanderlisting {
    let items: [santanderitem]
    let empty: String?
}

private final class santanderdirmodel: ObservableObject {
    @Published var allitems: [santanderitem] = []
    @Published var shownitems: [santanderitem] = []
    @Published var emptymsg: String?
    @Published var loading = false

    let item: santanderitem
    let readsbx: Bool
    let writevfs: Bool

    var sort: santandersort = .az
    var showhidden = true
    var recsearch = false

    init(item: santanderitem, readsbx: Bool, writevfs: Bool) {
        self.item = item
        self.readsbx = readsbx
        self.writevfs = writevfs
    }

    func load(query: String = "") {
        loading = true
        let item = item
        let readsbx = readsbx
        let sort = sort
        let showhidden = showhidden
        let recsearch = recsearch

        DispatchQueue.global(qos: .userInitiated).async {
            let listing = santanderfs.listdir(item: item, readsbx: readsbx)
            let shown = santanderfs.filteritems(
                all: listing.items,
                base: item.path,
                query: query,
                showhidden: showhidden,
                recsearch: recsearch,
                sort: sort,
                readsbx: readsbx
            )
            let empty = santanderfs.emptymessage(
                shown: shown,
                all: listing.items,
                query: query,
                showhidden: showhidden,
                fallback: listing.empty
            )

            DispatchQueue.main.async {
                self.allitems = listing.items
                self.shownitems = shown
                self.emptymsg = empty
                self.loading = false
            }
        }
    }
}

private struct santanderdirview: View {
    let item: santanderitem
    let readsbx: Bool
    let writevfs: Bool

    @EnvironmentObject private var nav: santandernav
    @ObservedObject private var clip = santanderclip.shared
    @AppStorage("fmRecursiveSearch") private var recsearch = false

    @StateObject private var model: santanderdirmodel
    @State private var query = ""
    @State private var showimport = false
    @State private var msg: santandermsg?
    @State private var infoitem: santanderitem?
    @State private var chmoditem: santanderitem?
    @State private var chownitem: santanderitem?
    @State private var delitem: santanderitem?
    @State private var renameitem: santanderitem?
    @State private var shownewfolder = false
    @State private var shownewfile = false
    @State private var showvfsinfo = false

    init(item: santanderitem, readsbx: Bool, writevfs: Bool) {
        self.item = item
        self.readsbx = readsbx
        self.writevfs = writevfs
        _model = StateObject(wrappedValue: santanderdirmodel(item: item, readsbx: readsbx, writevfs: writevfs))
    }

    var body: some View {
        List {
            if model.loading && model.shownitems.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if model.shownitems.isEmpty {
                Section {
                    Text(model.emptymsg ?? "Directory is empty.")
                        .foregroundColor(.secondary)
                }
            } else {
                Section {
                    ForEach(model.shownitems) { entry in
                        Button {
                            nav.stack.append(entry)
                        } label: {
                            row(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                copy(entry)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }

                            Button {
                                infoitem = entry
                            } label: {
                                Label("Get Info", systemImage: "info.circle")
                            }

                            Button {
                                renameitem = entry
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .disabled(!readsbx)

                            Button {
                                replace(entry)
                            } label: {
                                Label("Replace With Clipboard", systemImage: "doc.on.clipboard")
                            }
                            .disabled(clip.item == nil || (!readsbx && !writevfs))

                            Button {
                                chmoditem = entry
                            } label: {
                                Label("Chmod", systemImage: "lock.open")
                            }

                            Button {
                                chownitem = entry
                            } label: {
                                Label("Chown", systemImage: "person.crop.circle")
                            }

                            Button(role: .destructive) {
                                delitem = entry
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    if !readsbx {
                        Text("This file manager is powered by vfs namecache lookups, not full directory enumeration. It may display inaccurate information.")
                    }
                }
            }
        }
        .navigationTitle(item.path == "/" ? "/" : item.name)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        .onAppear {
            syncsettings()
            model.load()
        }
        .onChange(of: query) { newvalue in
            syncsettings()
            model.load(query: newvalue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        .onChange(of: recsearch) { _ in
            syncsettings()
            model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        .refreshable {
            syncsettings()
            model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !readsbx {
                    Button {
                        showvfsinfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }

                Menu {
                    Button {
                        if readsbx {
                            showimport = true
                        } else {
                            msg = santandermsg(title: "Upload Unavailable", text: "Upload is only supported in SBX mode.")
                        }
                    } label: {
                        Label("Upload File", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        if readsbx {
                            shownewfolder = true
                        } else {
                            msg = santandermsg(title: "New Folder Unavailable", text: "Creating folders is only supported in SBX mode.")
                        }
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }

                    Button {
                        if readsbx {
                            shownewfile = true
                        } else {
                            msg = santandermsg(title: "Create File Unavailable", text: "Creating files is only supported in SBX mode.")
                        }
                    } label: {
                        Label("Create File", systemImage: "doc.badge.plus")
                    }

                    Button {
                        paste(replace: false)
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    .disabled(clip.item == nil || !readsbx)

                    Button {
                        paste(replace: true)
                    } label: {
                        Label("Paste (Replace)", systemImage: "doc.on.clipboard.fill")
                    }
                    .disabled(clip.item == nil || !readsbx)

                    Menu {
                        Button("Sort A-Z") {
                            model.sort = .az
                            model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        Button("Sort Z-A") {
                            model.sort = .za
                            model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }

                    Button {
                        model.showhidden.toggle()
                        model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
                    } label: {
                        Label(model.showhidden ? "Hide hidden files" : "Display hidden files", systemImage: "eye")
                    }

                    Button {
                        nav.go(santanderitem(path: "/", isdir: true))
                    } label: {
                        Label("Go to Root", systemImage: "externaldrive")
                    }

                    Button {
                        nav.go(santanderitem(path: NSHomeDirectory(), isdir: true))
                    } label: {
                        Label("Go to Home", systemImage: "house")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .fileImporter(isPresented: $showimport, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                upload(url)
            case .failure(let err):
                msg = santandermsg(title: "Upload Failed", text: err.localizedDescription)
            }
        }
        .alert(item: $msg) { msg in
            Alert(title: Text(msg.title), message: Text(msg.text), dismissButton: .default(Text("OK")))
        }
        .alert("Delete", isPresented: Binding(get: { delitem != nil }, set: { if !$0 { delitem = nil } })) {
            Button("Cancel", role: .cancel) {
                delitem = nil
            }
            Button("Delete", role: .destructive) {
                if let entry = delitem {
                    delete(entry)
                }
                delitem = nil
            }
        } message: {
            Text("Delete \(delitem?.name ?? "item")?")
        }
        .sheet(item: $infoitem) { entry in
            santanderinfosheet(title: entry.name, text: santanderfs.details(path: entry.path))
        }
        .sheet(item: $renameitem) { entry in
            santandernamesheet(
                title: "Rename",
                itemname: entry.name,
                placeholder: entry.name,
                actiontitle: "Rename"
            ) { newname in
                rename(entry, newname: newname)
            }
        }
        .sheet(item: $chmoditem) { entry in
            santanderchmodsheet(item: entry) { mode in
                let ok = entry.path.withCString { apfs_mod($0, mode) == 0 }
                msg = santandermsg(title: "Chmod", text: ok ? "Operation completed." : "Operation failed.")
            }
        }
        .sheet(item: $chownitem) { entry in
            santanderchownsheet(item: entry) { uid, gid in
                let ok = entry.path.withCString { apfs_own($0, uid, gid) == 0 }
                msg = santandermsg(title: "Chown", text: ok ? "Operation completed." : "Operation failed.")
            }
        }
        .alert("File Manager Info", isPresented: $showvfsinfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This browser is powered by vfs namecache lookups, not full directory enumeration. Some folders may appear empty unless entries are already cached. Symlinks may also be shown as files even when their targets are directories.")
        }
        .sheet(isPresented: $shownewfolder) {
            santandernamesheet(
                title: "New Folder",
                itemname: item.name,
                placeholder: "New Folder",
                actiontitle: "Create"
            ) { name in
                newfolder(name: name)
            }
        }
        .sheet(isPresented: $shownewfile) {
            santandernewfilesheet(itemname: item.name) { name, text in
                newfile(name: name, text: text)
            }
        }
    }

    private func syncsettings() {
        model.recsearch = recsearch
    }

    @ViewBuilder
    private func row(entry: santanderitem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.icon)
                .foregroundColor(entry.isdir ? .accentColor : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.display)
                    .foregroundColor(entry.name.hasPrefix(".") ? .gray : .primary)
                    .lineLimit(1)

                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(entry.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if entry.isdir {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Color(uiColor: .tertiaryLabel))
            }
        }
        .contentShape(Rectangle())
    }

    private func copy(_ entry: santanderitem) {
        clip.item = santanderclipitem(path: entry.path, isdir: entry.isdir, name: entry.name)
        msg = santandermsg(title: "Copied", text: entry.name)
    }

    private func rename(_ entry: santanderitem, newname: String) {
        guard readsbx else {
            msg = santandermsg(title: "Rename Unavailable", text: "Rename is only supported in SBX mode.")
            return
        }

        let trimmed = newname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            msg = santandermsg(title: "Rename Failed", text: "Name cannot be empty.")
            return
        }
        guard !trimmed.contains("/") else {
            msg = santandermsg(title: "Rename Failed", text: "Name cannot contain '/'.")
            return
        }
        guard trimmed != entry.name else { return }

        let dest = ((entry.path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(trimmed)
        guard !FileManager.default.fileExists(atPath: dest) else {
            msg = santandermsg(title: "Rename Failed", text: "A file with that name already exists.")
            return
        }

        do {
            try FileManager.default.moveItem(atPath: entry.path, toPath: dest)
            model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            msg = santandermsg(title: "Rename Failed", text: error.localizedDescription)
        }
    }

    private func newfolder(name: String) {
        guard readsbx else {
            msg = santandermsg(title: "New Folder Unavailable", text: "Creating folders is only supported in SBX mode.")
            return
        }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            msg = santandermsg(title: "New Folder Failed", text: "Name cannot be empty.")
            return
        }
        guard !trimmed.contains("/") else {
            msg = santandermsg(title: "New Folder Failed", text: "Name cannot contain '/'.")
            return
        }

        let dest = (item.path as NSString).appendingPathComponent(trimmed)
        guard !FileManager.default.fileExists(atPath: dest) else {
            msg = santandermsg(title: "New Folder Failed", text: "A file with that name already exists.")
            return
        }

        do {
            try FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: false, attributes: nil)
            model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            msg = santandermsg(title: "New Folder Failed", text: error.localizedDescription)
        }
    }

    private func newfile(name: String, text: String) {
        guard readsbx else {
            msg = santandermsg(title: "Create File Unavailable", text: "Creating files is only supported in SBX mode.")
            return
        }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            msg = santandermsg(title: "Create File Failed", text: "Name cannot be empty.")
            return
        }
        guard !trimmed.contains("/") else {
            msg = santandermsg(title: "Create File Failed", text: "Name cannot contain '/'.")
            return
        }

        let dest = (item.path as NSString).appendingPathComponent(trimmed)
        guard !FileManager.default.fileExists(atPath: dest) else {
            msg = santandermsg(title: "Create File Failed", text: "A file with that name already exists.")
            return
        }

        do {
            try Data(text.utf8).write(to: URL(fileURLWithPath: dest), options: .atomic)
            model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            msg = santandermsg(title: "Create File Failed", text: error.localizedDescription)
        }
    }

    private func paste(replace: Bool) {
        guard readsbx else {
            msg = santandermsg(title: "Paste Unavailable", text: "Paste is only supported in SBX mode.")
            return
        }
        guard let clipitem = clip.item else { return }

        if clipitem.isdir && (item.path == clipitem.path || item.path.hasPrefix(clipitem.path + "/")) {
            msg = santandermsg(title: "Paste Failed", text: "Cannot paste a folder into itself.")
            return
        }

        let base = (item.path as NSString).appendingPathComponent(clipitem.name)
        let dest = replace ? base : santanderfs.uniquepath(base: base)

        do {
            if replace && FileManager.default.fileExists(atPath: dest) {
                try FileManager.default.removeItem(atPath: dest)
            }
            try FileManager.default.copyItem(atPath: clipitem.path, toPath: dest)
            model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            msg = santandermsg(title: "Paste Failed", text: error.localizedDescription)
        }
    }

    private func replace(_ entry: santanderitem) {
        guard let clipitem = clip.item else { return }

        if writevfs && !entry.isdir && !clipitem.isdir {
            let ok = laramgr.shared.vfsoverwritefromlocalpath(target: entry.path, source: clipitem.path)
            if ok {
                model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                msg = santandermsg(title: "Replace Failed", text: "VFS overwrite failed.")
            }
            return
        }

        guard readsbx else {
            msg = santandermsg(title: "Replace Unavailable", text: "Replace is only supported in SBX mode.")
            return
        }

        if clipitem.isdir && (entry.path == clipitem.path || entry.path.hasPrefix(clipitem.path + "/")) {
            msg = santandermsg(title: "Replace Failed", text: "Cannot replace with a folder into itself.")
            return
        }

        do {
            if FileManager.default.fileExists(atPath: entry.path) {
                try FileManager.default.removeItem(atPath: entry.path)
            }
            try FileManager.default.copyItem(atPath: clipitem.path, toPath: entry.path)
            model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            msg = santandermsg(title: "Replace Failed", text: error.localizedDescription)
        }
    }

    private func delete(_ entry: santanderitem) {
        guard readsbx else {
            msg = santandermsg(title: "Delete Unavailable", text: "Delete is only supported in SBX mode.")
            return
        }

        do {
            try FileManager.default.removeItem(atPath: entry.path)
            model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            msg = santandermsg(title: "Delete Failed", text: error.localizedDescription)
        }
    }

    private func upload(_ url: URL) {
        guard readsbx else {
            msg = santandermsg(title: "Upload Unavailable", text: "Upload is only supported in SBX mode.")
            return
        }
        guard url.startAccessingSecurityScopedResource() else {
            msg = santandermsg(title: "Upload Failed", text: "Unable to access selected file.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let base = (item.path as NSString).appendingPathComponent(url.lastPathComponent)
        let dest = santanderfs.uniquepath(base: base)

        do {
            if FileManager.default.fileExists(atPath: dest) {
                try FileManager.default.removeItem(atPath: dest)
            }
            try FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: dest))
            model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            msg = santandermsg(title: "Upload Failed", text: error.localizedDescription)
        }
    }
}

private enum santanderpreview {
    case loading
    case text(String, Bool)
    case image(UIImage)
    case media(URL)
    case error(String)
}

private struct santanderfileview: View {
    let item: santanderitem
    let readsbx: Bool
    let writevfs: Bool

    @State private var preview: santanderpreview = .loading
    @State private var editing = false
    @State private var editable = false
    @State private var text = ""
    @State private var original = ""
    @State private var query = ""
    @State private var msg: santandermsg?
    @State private var exporturl: URL?
    @State private var showexport = false

    var body: some View {
        Group {
            switch preview {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case let .text(value, canedit):
                if editing && canedit {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 4)
                } else {
                    ScrollView {
                        Text(highlighted(text: value, query: query))
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .textSelection(.enabled)
                    }
                }

            case let .image(img):
                GeometryReader { geo in
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                    }
                }

            case let .media(url):
                VideoPlayer(player: AVPlayer(url: url))
                    .ignoresSafeArea(edges: .bottom)

            case let .error(err):
                ScrollView {
                    Text(err)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(item.name)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        .onAppear {
            load()
        }
        .onDisappear {
            cleanup()
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if caneditfile {
                    Button(editing ? "Save" : "Edit") {
                        if editing {
                            save()
                        } else {
                            startedit()
                        }
                    }
                }

                if exporturl != nil {
                    Button {
                        showexport = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .alert(item: $msg) { msg in
            Alert(title: Text(msg.title), message: Text(msg.text), dismissButton: .default(Text("OK")))
        }
        .fileExporter(
            isPresented: $showexport,
            document: santanderfiledoc(url: exporturl ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("empty")),
            contentType: item.type ?? .data,
            defaultFilename: item.name
        ) { result in
            if case .failure(let err) = result {
                msg = santandermsg(title: "Export Failed", text: err.localizedDescription)
            }
        }
    }

    private var caneditfile: Bool {
        switch preview {
        case let .text(_, canedit):
            return canedit && (readsbx || writevfs)
        default:
            return false
        }
    }

    private func load() {
        preview = .loading
        let item = item
        let readsbx = readsbx

        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = santanderfs.loadfile(item: item, readsbx: readsbx)
            let outurl = santanderfs.preparetemp(item: item, readsbx: readsbx, maxbytes: 128 * 1024 * 1024)

            DispatchQueue.main.async {
                preview = loaded.preview
                text = loaded.text
                original = loaded.text
                editable = loaded.editable
                exporturl = outurl
            }
        }
    }

    private func startedit() {
        guard editable else {
            msg = santandermsg(title: "Edit Unavailable", text: "This file type isn't editable in the viewer.")
            return
        }
        editing = true
        text = original
    }

    private func save() {
        let data = Data(text.utf8)
        let ok = santanderfs.writefile(path: item.path, data: data, readsbx: readsbx, writevfs: writevfs)
        if ok {
            editing = false
            original = text
            preview = .text(text, true)
            msg = santandermsg(title: "Saved", text: "File updated.")
            if !readsbx {
                exporturl = santanderfs.preparetemp(item: item, readsbx: readsbx, maxbytes: 128 * 1024 * 1024)
            }
        } else {
            msg = santandermsg(title: "Save Failed", text: writevfs ? "VFS overwrite failed." : "Unable to write file.")
        }
    }

    private func highlighted(text: String, query: String) -> AttributedString {
        var out = AttributedString(text)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return out }

        var scan = text.startIndex..<text.endIndex
        while let found = text.range(of: q, options: [.caseInsensitive], range: scan, locale: .current) {
            if let lower = AttributedString.Index(found.lowerBound, within: out),
               let upper = AttributedString.Index(found.upperBound, within: out) {
                out[lower..<upper].backgroundColor = .yellow.opacity(0.35)
            }

            if found.upperBound == text.endIndex {
                break
            }
            scan = found.upperBound..<text.endIndex
        }
        return out
    }

    private func cleanup() {
        if case let .media(url) = preview, url.path.hasPrefix(NSTemporaryDirectory()) {
            try? FileManager.default.removeItem(at: url)
        }
        guard let exporturl else { return }
        if exporturl.path.hasPrefix(NSTemporaryDirectory()) {
            try? FileManager.default.removeItem(at: exporturl)
        }
    }
}

private struct santanderloadedfile {
    let preview: santanderpreview
    let text: String
    let editable: Bool
}

private enum santanderfs {
    static func listdir(item: santanderitem, readsbx: Bool) -> santanderlisting {
        guard item.isdir else { return santanderlisting(items: [], empty: "Not a directory.") }

        if readsbx {
            return listsbx(item: item)
        }

        let mgr = laramgr.shared
        guard mgr.vfsready else {
            return santanderlisting(items: [], empty: "VFS not ready.")
        }
        guard let entries = mgr.vfslistdir(path: item.path) else {
            return santanderlisting(items: [], empty: "Unable to list directory.")
        }

        let items = entries.map { entry in
            let full = item.path == "/" ? "/" + entry.name : item.path + "/" + entry.name
            return santanderitem(path: full, isdir: entry.isDir)
        }

        return santanderlisting(items: items, empty: items.isEmpty ? "Directory is empty." : nil)
    }

    static func listsbx(item: santanderitem) -> santanderlisting {
        let fm = FileManager.default
        var isdir = ObjCBool(false)
        let exists = fm.fileExists(atPath: item.path, isDirectory: &isdir)
        guard exists, isdir.boolValue else {
            return santanderlisting(items: [], empty: "Directory no longer exists.")
        }
        guard fm.isReadableFile(atPath: item.path) else {
            return santanderlisting(items: [], empty: "Cannot list directory (missing permissions).")
        }

        do {
            let names = try fm.contentsOfDirectory(atPath: item.path)
            let mode = fmAppsDisplayMode(rawValue: UserDefaults.standard.string(forKey: "selectedFmAppsDisplayMode") ?? "") ?? .appName
            let datadirs = [
                "/private/var/mobile/Containers/Data/Application",
                "/var/mobile/Containers/Data/Application"
            ]
            let bundledirs = [
                "/private/var/containers/Bundle/Application",
                "/var/containers/Bundle/Application"
            ]
            var appnames: [String: String] = [:]

            if mode == .appName && datadirs.contains(item.path) {
                appnames = appnamecache()
            }

            let items = names.map { name in
                let full = item.path == "/" ? "/" + name : item.path + "/" + name
                var isdir = ObjCBool(false)
                fm.fileExists(atPath: full, isDirectory: &isdir)
                var display = name

                if (bundledirs + datadirs).contains(item.path) {
                    if mode == .appName {
                        if bundledirs.contains(item.path) {
                            display = bundleappname(at: full) ?? name
                        } else if let bundleid = bundleidforcontainer(at: full) {
                            display = appnames[bundleid] ?? bundleid
                        }
                    } else if mode == .bundleID, let bundleid = bundleidforcontainer(at: full) {
                        display = bundleid
                    }
                }

                return santanderitem(path: full, isdir: isdir.boolValue, display: display)
            }

            return santanderlisting(items: items, empty: items.isEmpty ? "Directory is empty." : nil)
        } catch {
            let err = error as NSError
            if err.domain == NSCocoaErrorDomain && err.code == NSFileReadNoPermissionError {
                return santanderlisting(items: [], empty: "Cannot list directory (missing permissions).")
            }
            return santanderlisting(items: [], empty: "Unable to list directory: \(err.localizedDescription)")
        }
    }

    static func filteritems(all: [santanderitem], base: String, query: String, showhidden: Bool, recsearch: Bool, sort: santandersort, readsbx: Bool) -> [santanderitem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [santanderitem]

        if !q.isEmpty && recsearch && readsbx {
            items = recsearchsbx(root: base, query: q)
        } else if !q.isEmpty {
            items = all.filter { $0.display.localizedCaseInsensitiveContains(q) || $0.path.localizedCaseInsensitiveContains(q) }
        } else {
            items = all
        }

        if q.isEmpty && !showhidden {
            items = items.filter { !$0.name.hasPrefix(".") }
        }

        switch sort {
        case .az:
            items.sort { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending }
        case .za:
            items.sort { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedDescending }
        }

        return items
    }

    static func emptymessage(shown: [santanderitem], all: [santanderitem], query: String, showhidden: Bool, fallback: String?) -> String? {
        guard shown.isEmpty else { return nil }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { return "No matching items." }
        if !showhidden && !all.isEmpty { return "No visible items. Enable hidden files to show dotfiles." }
        return fallback ?? "Directory is empty."
    }

    static func recsearchsbx(root: String, query: String) -> [santanderitem] {
        let fm = FileManager.default
        var out: [santanderitem] = []
        guard let en = fm.enumerator(atPath: root) else { return [] }

        for case let name as String in en {
            let full = (root as NSString).appendingPathComponent(name)
            var isdir = ObjCBool(false)
            fm.fileExists(atPath: full, isDirectory: &isdir)

            if name.localizedCaseInsensitiveContains(query) || full.localizedCaseInsensitiveContains(query) {
                out.append(santanderitem(path: full, isdir: isdir.boolValue))
            }
        }

        return out
    }

    static func uniquepath(base: String) -> String {
        let fm = FileManager.default
        if !fm.fileExists(atPath: base) { return base }

        let dir = (base as NSString).deletingLastPathComponent
        let file = (base as NSString).lastPathComponent
        let ext = (file as NSString).pathExtension
        let stem = ext.isEmpty ? file : (file as NSString).deletingPathExtension

        var i = 1
        while true {
            let suffix = i == 1 ? " copy" : " copy \(i)"
            let name = ext.isEmpty ? "\(stem)\(suffix)" : "\(stem)\(suffix).\(ext)"
            let candidate = (dir as NSString).appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate) {
                return candidate
            }
            i += 1
        }
    }

    static func details(path: String) -> String {
        let fm = FileManager.default
        var lines: [String] = []

        var isdir = ObjCBool(false)
        let exists = fm.fileExists(atPath: path, isDirectory: &isdir)
        lines.append("Exists: \(exists ? "yes" : "no")")
        if exists {
            lines.append("Kind: \(isdir.boolValue ? "directory" : "file")")
        }

        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .contentTypeKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .isSymbolicLinkKey
        ]

        if let values = try? url.resourceValues(forKeys: keys) {
            if let type = values.contentType {
                lines.append("UTType: \(type.identifier)")
            }
            if let size = values.fileSize {
                lines.append("Size: \(size) bytes")
            }
            if let created = values.creationDate {
                lines.append("Created: \(created)")
            }
            if let modified = values.contentModificationDate {
                lines.append("Modified: \(modified)")
            }
            if let sym = values.isSymbolicLink {
                lines.append("Symlink: \(sym ? "yes" : "no")")
            }
        }

        if let attrs = try? fm.attributesOfItem(atPath: path) {
            if let perms = attrs[.posixPermissions] as? NSNumber {
                lines.append(String(format: "POSIX perms: %04o", perms.intValue))
            }
            if let owner = attrs[.ownerAccountName] as? String {
                lines.append("Owner: \(owner)")
            }
            if let group = attrs[.groupOwnerAccountName] as? String {
                lines.append("Group: \(group)")
            }
        }

        lines.append("Readable: \(fm.isReadableFile(atPath: path) ? "yes" : "no")")
        lines.append("Writable: \(fm.isWritableFile(atPath: path) ? "yes" : "no")")
        lines.append("Executable: \(fm.isExecutableFile(atPath: path) ? "yes" : "no")")
        return lines.joined(separator: "\n")
    }

    static func loadfile(item: santanderitem, readsbx: Bool) -> santanderloadedfile {
        if isimage(item) {
            if let data = readdata(path: item.path, readsbx: readsbx, max: 8 * 1024 * 1024),
               let img = UIImage(data: data) {
                return santanderloadedfile(preview: .image(img), text: "", editable: false)
            }
        }

        if ismedia(item), let url = preparetemp(item: item, readsbx: readsbx, maxbytes: 128 * 1024 * 1024) {
            return santanderloadedfile(preview: .media(url), text: "", editable: false)
        }

        guard let data = readdata(path: item.path, readsbx: readsbx, max: 2 * 1024 * 1024) else {
            let err = readsbx ? "Failed to read file.\n\n" + unreadabledetails(path: item.path) : "Failed to read file."
            return santanderloadedfile(preview: .error(err), text: err, editable: false)
        }

        let rendered = render(data: data)
        return santanderloadedfile(preview: .text(rendered.text, rendered.editable), text: rendered.text, editable: rendered.editable)
    }

    static func writefile(path: String, data: Data, readsbx: Bool, writevfs: Bool) -> Bool {
        if writevfs {
            return laramgr.shared.vfsoverwritewithdata(target: path, data: data)
        }
        guard readsbx else { return false }
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func readdata(path: String, readsbx: Bool, max: Int) -> Data? {
        if readsbx {
            let url = URL(fileURLWithPath: path)
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            if #available(iOS 13.4, *) {
                return try? handle.read(upToCount: max) ?? Data()
            }
            return handle.readData(ofLength: max)
        }
        return laramgr.shared.vfsread(path: path, maxSize: max)
    }

    static func preparetemp(item: santanderitem, readsbx: Bool, maxbytes: Int64) -> URL? {
        if readsbx {
            guard let size = sbxfilesize(path: item.path), size > 0, size <= maxbytes else { return nil }
            return URL(fileURLWithPath: item.path)
        }

        let size = vfs_filesize(item.path)
        guard size > 0, size <= maxbytes else { return nil }

        let ext = (item.path as NSString).pathExtension
        let name = "santander_" + UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: nil)

        guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
        defer { try? handle.close() }

        let chunk = 1024 * 1024
        var off: Int64 = 0
        while off < size {
            let want = Int(min(Int64(chunk), size - off))
            var buf = [UInt8](repeating: 0, count: want)
            let got = vfs_read(item.path, &buf, want, off_t(off))
            if got <= 0 { return nil }
            handle.write(Data(buf.prefix(Int(got))))
            off += Int64(got)
        }

        return url
    }

    static func isimage(_ item: santanderitem) -> Bool {
        if let type = item.type, type.isSubtype(of: .image) { return true }
        let ext = (item.path as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "heic", "heif", "bmp", "tif", "tiff", "webp"].contains(ext)
    }

    static func ismedia(_ item: santanderitem) -> Bool {
        if let type = item.type, type.isSubtype(of: .audio) || type.isSubtype(of: .movie) || type.isSubtype(of: .video) {
            return true
        }
        let ext = (item.path as NSString).pathExtension.lowercased()
        if ["mp4", "mov", "m4v", "avi", "mkv"].contains(ext) { return true }
        if ["mp3", "m4a", "m4b", "aac", "aiff", "wav", "caf", "flac", "opus", "ogg", "wma", "amr", "3gp"].contains(ext) { return true }
        return false
    }

    static func render(data: Data) -> (text: String, editable: Bool) {
        if data.isEmpty {
            return ("(empty file)", true)
        }
        if let plist = plisttext(data: data) {
            return (plist, false)
        }
        if let text = textdecode(data: data) {
            return (text, true)
        }
        return (hexdump(data: data), false)
    }

    static func plisttext(data: Data) -> String? {
        guard data.starts(with: Data("bplist".utf8)) || data.starts(with: Data("<?xml".utf8)) else {
            return nil
        }
        guard let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return nil
        }
        if JSONSerialization.isValidJSONObject(obj),
           let jsondata = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let json = String(data: jsondata, encoding: .utf8) {
            return json
        }
        if let xmldata = try? PropertyListSerialization.data(fromPropertyList: obj, format: .xml, options: 0),
           let xml = String(data: xmldata, encoding: .utf8) {
            return xml
        }
        return String(describing: obj)
    }

    static func textdecode(data: Data) -> String? {
        let encs: [String.Encoding] = [
            .utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .utf32, .utf32LittleEndian,
            .utf32BigEndian, .ascii, .isoLatin1, .windowsCP1252, .macOSRoman, .nonLossyASCII
        ]
        for enc in encs {
            guard let value = String(data: data, encoding: enc) else { continue }
            if lookstext(value) {
                return value
            }
        }
        return nil
    }

    static func lookstext(_ value: String) -> Bool {
        if value.isEmpty { return true }
        let scalars = value.unicodeScalars
        let bad = scalars.filter { scalar in
            let v = scalar.value
            if v == 9 || v == 10 || v == 13 { return false }
            if v < 32 { return true }
            if v >= 0x7F && v <= 0x9F { return true }
            return false
        }
        return Double(bad.count) / Double(scalars.count) < 0.01
    }

    static func hexdump(data: Data) -> String {
        let limit = min(data.count, 4096)
        let chunk = data.prefix(limit)
        var lines: [String] = []
        lines.append("Binary data (\(data.count) bytes). Showing first \(limit) bytes:")
        lines.append("")

        var off = 0
        while off < chunk.count {
            let row = chunk[off..<min(off + 16, chunk.count)]
            let hex = row.map { String(format: "%02X", $0) }.joined(separator: " ")
            let ascii = row.map { byte -> String in
                if byte >= 32 && byte <= 126 {
                    return String(UnicodeScalar(byte))
                }
                return "."
            }.joined()
            lines.append(String(format: "%08X  %-47@  %@", off, hex as NSString, ascii))
            off += 16
        }

        return lines.joined(separator: "\n")
    }

    static func unreadabledetails(path: String) -> String {
        let fm = FileManager.default
        var lines: [String] = []

        var isdir = ObjCBool(false)
        let exists = fm.fileExists(atPath: path, isDirectory: &isdir)
        lines.append("Exists: \(exists ? "yes" : "no")")
        if exists {
            lines.append("Kind: \(isdir.boolValue ? "directory" : "regular item")")
        }

        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [.contentTypeKey, .isSymbolicLinkKey, .isAliasFileKey, .fileSizeKey]
        if let values = try? url.resourceValues(forKeys: keys) {
            if let type = values.contentType {
                lines.append("UTType: \(type.identifier)")
            }
            if let size = values.fileSize {
                lines.append("Size: \(size) bytes")
            }
            if let sym = values.isSymbolicLink {
                lines.append("Symlink: \(sym ? "yes" : "no")")
            }
            if values.isSymbolicLink == true,
               let target = try? fm.destinationOfSymbolicLink(atPath: path) {
                lines.append("Symlink target: \(target)")
            }
            if let alias = values.isAliasFile {
                lines.append("Alias file: \(alias ? "yes" : "no")")
            }
        }

        if let attrs = try? fm.attributesOfItem(atPath: path) {
            if let filetype = attrs[.type] as? FileAttributeType {
                lines.append("File attribute type: \(filetype.rawValue)")
            }
            if let owner = attrs[.ownerAccountName] as? String {
                lines.append("Owner: \(owner)")
            }
            if let group = attrs[.groupOwnerAccountName] as? String {
                lines.append("Group: \(group)")
            }
            if let perms = attrs[.posixPermissions] as? NSNumber {
                lines.append(String(format: "POSIX perms: %04o", perms.intValue))
            }
        }

        lines.append("Readable: \(fm.isReadableFile(atPath: path) ? "yes" : "no")")
        lines.append("Writable: \(fm.isWritableFile(atPath: path) ? "yes" : "no")")
        lines.append("Executable: \(fm.isExecutableFile(atPath: path) ? "yes" : "no")")
        return lines.joined(separator: "\n")
    }

    static func sbxfilesize(path: String) -> Int64? {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? NSNumber {
            return size.int64Value
        }
        return nil
    }

    static func appnamecache() -> [String: String] {
        let fm = FileManager.default
        let bundlepath = "/private/var/containers/Bundle/Application"
        guard let apps = try? fm.contentsOfDirectory(atPath: bundlepath) else { return [:] }
        var out: [String: String] = [:]

        for app in apps {
            let apppath = bundlepath + "/" + app
            guard let contents = try? fm.contentsOfDirectory(atPath: apppath) else { continue }
            for item in contents where item.hasSuffix(".app") {
                let infopath = apppath + "/" + item + "/Info.plist"
                guard let plist = NSDictionary(contentsOf: URL(fileURLWithPath: infopath)),
                      let bundleid = plist["CFBundleIdentifier"] as? String else { continue }
                let appname = (plist["CFBundleDisplayName"] as? String) ??
                    (plist["CFBundleName"] as? String) ??
                    (plist["CFBundleExecutable"] as? String) ??
                    bundleid
                out[bundleid] = appname
                break
            }
        }

        return out
    }

    static func bundleappname(at path: String) -> String? {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path) else { return nil }
        for item in contents where item.hasSuffix(".app") {
            let infopath = path + "/" + item + "/Info.plist"
            guard let plist = NSDictionary(contentsOf: URL(fileURLWithPath: infopath)) else { continue }
            return (plist["CFBundleDisplayName"] as? String) ??
                (plist["CFBundleName"] as? String) ??
                (plist["CFBundleExecutable"] as? String)
        }
        return nil
    }

    static func bundleidforcontainer(at path: String) -> String? {
        let meta = path + "/.com.apple.mobile_container_manager.metadata.plist"
        guard let plist = NSDictionary(contentsOf: URL(fileURLWithPath: meta)) else { return nil }
        return plist["MCMMetadataIdentifier"] as? String
    }
}

private struct santanderinfosheet: View {
    let title: String
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct santandernamesheet: View {
    let title: String
    let itemname: String
    let placeholder: String
    let actiontitle: String
    let apply: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(itemname) {
                    TextField(placeholder, text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if name.isEmpty {
                    name = placeholder
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(actiontitle) {
                        apply(name)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct santandernewfilesheet: View {
    let itemname: String
    let apply: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = "untitled.txt"
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(itemname) {
                    TextField("Filename", text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Contents") {
                    TextEditor(text: $text)
                        .frame(minHeight: 180)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .navigationTitle("Create File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        apply(name, text)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct santanderchmodsheet: View {
    let item: santanderitem
    let apply: (UInt16) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(item.name) {
                    TextField("e.g. 755", text: $text)
                        .keyboardType(.numberPad)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .navigationTitle("Chmod")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        guard let mode = UInt16(text, radix: 8) else { return }
                        apply(mode)
                        dismiss()
                    }
                    .disabled(UInt16(text, radix: 8) == nil)
                }
            }
        }
    }
}

private struct santanderchownsheet: View {
    let item: santanderitem
    let apply: (UInt32, UInt32) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var uid = ""
    @State private var gid = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(item.name) {
                    TextField("UID (e.g. 501)", text: $uid)
                        .keyboardType(.numberPad)
                    TextField("GID (e.g. 501)", text: $gid)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Chown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        guard let uid = UInt32(uid), let gid = UInt32(gid) else { return }
                        apply(uid, gid)
                        dismiss()
                    }
                    .disabled(UInt32(uid) == nil || UInt32(gid) == nil)
                }
            }
        }
    }
}

private struct santanderfiledoc: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    let url: URL

    init(url: URL) {
        self.url = url
    }

    init(configuration: ReadConfiguration) throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let data = configuration.file.regularFileContents ?? Data()
        try data.write(to: tmp)
        self.url = tmp
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return try FileWrapper(url: url, options: .immediate)
    }
}
