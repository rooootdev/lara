//
//  FontPicker.swift
//  lara
//
//  Created by ruter on 28.03.26.
//

import SwiftUI
import Foundation
import CoreText
import UIKit
import UniformTypeIdentifiers
import Combine

struct importedfont: Identifiable, Codable {
    var id: String { name }
    let name: String
    let path: String
}

enum styletarget: String, CaseIterable {
    case standard = "Standard"
    case mono = "Mono"
    case italic = "Italic"

    var path: String {
        switch self {
            case .standard: return laramgr.fontpath
            case .mono: return laramgr.monofontpath
            case .italic: return laramgr.italicfontpath
        }
    }
}

struct FontPicker: View {
    @ObservedObject var mgr: laramgr
    @State private var showimporter = false
    @State private var customfonts: [importedfont] = load()
    @StateObject private var repostore = fontrepostore()
    @State private var showrepomgr = false
    @State private var selectedTarget: styletarget = .standard
    private let emojipath = "/System/Library/Fonts/CoreAddition/AppleColorEmoji-160px.ttc"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if repostore.repos.isEmpty {
                        Text("No repos added yet.")
                            .foregroundColor(.secondary)
                    }
                }

                ForEach(repostore.repos) { repo in
                    Section {
                        if let repodata = repo.data {
                            ForEach(repodata.fonts) { font in
                                repofontrow(mgr: mgr, repo: repodata, font: font, repostore: repostore)
                            }
                        } else {
                            HStack {
                                Text("Loading...")
                                Spacer()
                                
                                if repo.isloading {
                                    ProgressView()
                                } else if let error = repo.error {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    } header: {
                        Text(repo.data?.name ?? repo.url)
                    }
                }

                ForEach(repostore.repos) { repo in
                    if let repodata = repo.data, !repodata.emojis.isEmpty {
                        Section {
                            ForEach(repodata.emojis) { emoji in
                                repoemojirow(mgr: mgr, repo: repodata, emoji: emoji, repostore: repostore, emojipath: emojipath)
                            }
                        } header: {
                            Text("Emojis — \(repodata.name)")
                        }
                    }
                }
	                
                Section {
                    Picker("Target Style", selection: $selectedTarget) {
                        ForEach(styletarget.allCases, id: \.self) { target in
                            Text(target.rawValue).tag(target)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 5)

                    if !customfonts.isEmpty {
                        ForEach(customfonts) { font in
                            Button {
                                if !FileManager.default.fileExists(atPath: font.path) {
                                    mgr.logmsg("custom font missing: \(font.name)")
                                    customfonts.removeAll { $0.name == font.name }
                                    save(customfonts)
                                    return
                                }
                                let success = mgr.vfsoverwritefromlocalpath(target: selectedTarget.path, source: font.path)
                                success ? mgr.logmsg("font changed to \(font.name)") : mgr.logmsg("failed to change font")
                            } label: {
                                Text(font.name)
                                    .font(viewfontfile(path: font.path, size: 17))
                            }
                        }
                    }
                    
                    Button("Import Font") {
                        showimporter = true
                    }
                } header: {
                    Text("Settings")
                } footer: {
                    Text("Some custom fonts will not work for app icons and other stuff, some will not work at all. If you want them to work, patch your .ttf [here](https://neonmodder123.github.io/lara-font-patcher/).")
                }
                
                Section {
                    Text(globallogger.logs.last ?? "No logs yet")
                        .font(.system(size: 13, design: .monospaced))
                    
                    Button("Respring") {
                        mgr.respring()
                    }
                }
            }
            .navigationTitle("Font Overwrite")
            .task {
                await repostore.refreshrepos()
            }
            .fileImporter(
                isPresented: $showimporter,
                allowedContentTypes: [.font],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let importurl = urls.first {
                    importfont(importurl)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showrepomgr = true
                    } label: {
                        Image(systemName: "shippingbox")
                    }
                }
            }
            .sheet(isPresented: $showrepomgr) {
                FontRepoView(repostore: repostore)
            }
        }
    }
    
    func importfont(_ url: URL) {
        let fm = FileManager.default
        let dir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Custom")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(url.lastPathComponent)

        do {
            if !fm.fileExists(atPath: dest.path) {
                try fm.copyItem(at: url, to: dest)
            }

            let name = url.deletingPathExtension().lastPathComponent
            let font = importedfont(name: name, path: dest.path)

            if !customfonts.contains(where: {$0.name == name}) {
                customfonts.append(font)
                save(customfonts)
            }

        } catch {
            print("font import failed:", error)
        }
    }

    
}

private func viewfontfile(path: String, size: CGFloat) -> Font {
    let fileurl = URL(fileURLWithPath: path)

    if let data = try? Data(contentsOf: fileurl) as CFData,
       let provider = CGDataProvider(data: data),
       let cgFont = CGFont(provider) {

        let ctFont = CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
        let uiFont = ctFont as UIFont
        return Font(uiFont)
    }

    return .system(size: size)
}

private let fontkey = "customfonts"
private let fontrepokey = "fontrepos"
private let defaultrepo = "https://raw.githubusercontent.com/rooootdev/larafonts/main/fonts.json"

private func load() -> [importedfont] {
    guard let storeddata = UserDefaults.standard.data(forKey: fontkey),
          let fonts = try? JSONDecoder().decode([importedfont].self, from: storeddata)
    else { return [] }
    let fm = FileManager.default
    let filtered = fonts.filter { fm.fileExists(atPath: $0.path) }
    if filtered.count != fonts.count {
        save(filtered)
    }
    return filtered
}

private func save(_ fonts: [importedfont]) {
    if let encoded = try? JSONEncoder().encode(fonts) {
        UserDefaults.standard.set(encoded, forKey: fontkey)
    }
}

private func loadrepourls() -> [String] {
    if let storeddata = UserDefaults.standard.data(forKey: fontrepokey),
       let urls = try? JSONDecoder().decode([String].self, from: storeddata),
       !urls.isEmpty {
        return urls
    }
    return [defaultrepo]
}

private func saverepourls(_ urls: [String]) {
    if let encoded = try? JSONEncoder().encode(urls) {
        UserDefaults.standard.set(encoded, forKey: fontrepokey)
    }
}

private func isdefaultrepo(_ url: String) -> Bool {
    url == defaultrepo
}

struct fontrepostate: Identifiable {
    let id: String
    let url: String
    var isloading: Bool
    var error: String?
    var data: fontrepodata?

    init(url: String, isloading: Bool, error: String?, data: fontrepodata?) {
        self.id = url
        self.url = url
        self.isloading = isloading
        self.error = error
        self.data = data
    }
}

	struct fontrepodata: Decodable, Identifiable {
	    var id: String { name }
	    let name: String
	    let author: String
	    let icon: String?
	    let fonts: [fontrepofont]
	    let emojis: [fontrepofont]

	    enum CodingKeys: String, CodingKey {
	        case name = "repo_name"
	        case author = "repo_author"
	        case icon = "repo_icon"
	        case fonts
	        case emojis
	        case emoji
	    }

	    init(from decoder: Decoder) throws {
	        let container = try decoder.container(keyedBy: CodingKeys.self)
	        name = try container.decode(String.self, forKey: .name)
	        author = try container.decode(String.self, forKey: .author)
	        icon = try container.decodeIfPresent(String.self, forKey: .icon)
	        fonts = try container.decodeIfPresent([fontrepofont].self, forKey: .fonts) ?? []
	        emojis = try container.decodeIfPresent([fontrepofont].self, forKey: .emojis)
	            ?? container.decodeIfPresent([fontrepofont].self, forKey: .emoji)
	            ?? []
	    }
	}

struct fontrepofont: Decodable, Identifiable {
    var id: String { url }
    let name: String
    let url: String
    let format: String?
}

struct repofontrow: View {
    @ObservedObject var mgr: laramgr
    let repo: fontrepodata
    let font: fontrepofont
    @ObservedObject var repostore: fontrepostore

    var body: some View {
        let localurl = localfonturl(repo: repo, font: font)
        let iddownloaded = localurl.map { FileManager.default.fileExists(atPath: $0.path) } ?? false

        Button {
            if iddownloaded, let localurl {
                let success = mgr.vfsoverwritefromlocalpath(
                    target: laramgr.fontpath,
                    source: localurl.path
                )
                success ? mgr.logmsg("font changed to \(font.name)") : mgr.logmsg("failed to change font")
            } else {
                Task {
                    await repostore.dlfont(font, repo: repo)
                }
            }
        } label: {
            HStack {
                Text(font.name)
                    .font(iddownloaded && localurl != nil
                        ? viewfontfile(path: localurl!.path, size: 17)
                        : .system(size: 17))
                Spacer()
                if repostore.downloading.contains(font.url) {
                    ProgressView()
                }
            }
        }
    }
}

private struct repoemojirow: View {
    @ObservedObject var mgr: laramgr
    let repo: fontrepodata
    let emoji: fontrepofont
    @ObservedObject var repostore: fontrepostore
    let emojipath: String

    var body: some View {
        let localurl = localemojiurl(repo: repo, emoji: emoji)
        let isdownloaded = localurl.map { FileManager.default.fileExists(atPath: $0.path) } ?? false

        Button {
            if isdownloaded, let localurl {
				guard localurl.pathExtension.lowercased() == "ttc" else {
            		mgr.logmsg("emoji font must be .ttc, got .\(localurl.pathExtension)")
            		return
        		}
                let success = mgr.vfsoverwritefromlocalpath(target: emojipath, source: localurl.path)
                success ? mgr.logmsg("emoji changed to \(emoji.name)") : mgr.logmsg("failed to change emojis")
            } else {
                Task { await repostore.dlemoji(emoji, repo: repo) }
            }
        } label: {
            HStack {
                Text(emoji.name)
				if let remoteurl = URL(string: emoji.url),
           			remoteurl.pathExtension.lowercased() != "ttc" {
            		Text("not .ttc")
                	.font(.caption2)
                	.foregroundColor(.red)
                	.padding(.horizontal, 5)
                	.padding(.vertical, 2)
                	.background(Color.red.opacity(0.1))
                	.clipShape(Capsule())
        		}
                Spacer()
                if repostore.downloading.contains(emoji.url) {
                    ProgressView()
                }
            }
        }
    }
}

struct FontRepoView: View {
    @ObservedObject var repostore: fontrepostore
    @State private var showaddrepo = false
    @State private var newrepourl = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(repostore.repos) { repo in
                        HStack {
                            if let iconurl = repo.data?.icon, let iconimgurl = URL(string: iconurl) {
                                AsyncImage(url: iconimgurl) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    ProgressView()
                                }
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                            } else {
                                ProgressView()
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(repo.data?.name ?? repo.url)
                                    .font(.headline)
                                if let author = repo.data?.author, !author.isEmpty {
                                    Text(author)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if repo.isloading {
                                ProgressView()
                            } else if let error = repo.error {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            } else if !isdefaultrepo(repo.url) {
                                Button(role: .destructive) {
                                    repostore.removerepo(repo.url)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                        .swipeActions {
                            if !isdefaultrepo(repo.url) {
                                Button(role: .destructive) {
                                    repostore.removerepo(repo.url)
                                } label: {
                                    Text("Remove")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Repos")
                } footer: {
                    Text("Make a repo by forking the [template repo](https://github.com/rooootdev/larafonts/) on GitHub and adding your custom fonts there.")
                }
            }
            .navigationTitle("Font Repos")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newrepourl = ""
                        showaddrepo = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task { await repostore.refreshrepos() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .alert("Add Font Repo", isPresented: $showaddrepo) {
                TextField("URL:", text: $newrepourl)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                Button("Add") {
                    Task { await repostore.addrepo(newrepourl) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Example: \n\(defaultrepo)")
            }
        }
    }
}

private func localfonturl(repo: fontrepodata, font: fontrepofont) -> URL? {
    guard let remoteurl = URL(string: font.url) else { return nil }
    let fm = FileManager.default
    let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let repoDir = docs.appendingPathComponent("FontRepos")
        .appendingPathComponent(sanitizefilename(repo.name))
    return repoDir.appendingPathComponent(remoteurl.lastPathComponent)
}

private func localemojiurl(repo: fontrepodata, emoji: fontrepofont) -> URL? {
    guard let remoteurl = URL(string: emoji.url) else { return nil }
    let fm = FileManager.default
    let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let repoDir = docs.appendingPathComponent("EmojiRepos")
        .appendingPathComponent(sanitizefilename(repo.name))
    return repoDir.appendingPathComponent(remoteurl.lastPathComponent)
}

private func sanitizefilename(_ name: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "._-"))
    let cleaned = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
    return String(cleaned)
}

final class fontrepostore: ObservableObject {
    @Published var repos: [fontrepostate] = []
    @Published var downloading: Set<String> = []

    private var repourls: [String] = loadrepourls()
    private var pendingdownload: Set<String> = []

    @MainActor
    func refreshrepos() async {
        let urls = repourls
        repos = urls.map { fontrepostate(url: $0, isloading: true, error: nil, data: nil) }

        await withTaskGroup(of: (String, Result<fontrepodata, Error>).self) { group in
            for url in urls {
                group.addTask {
                    do {
                        let repodata = try await self.fetchrepo(url)
                        return (url, .success(repodata))
                    } catch {
                        return (url, .failure(error))
                    }
                }
            }

            for await (url, result) in group {
                if let idx = repos.firstIndex(where: { $0.url == url }) {
                    repos[idx].isloading = false
                    switch result {
                    case .success(let repodata):
                        repos[idx].data = repodata
                        repos[idx].error = nil
                        let repo = repodata
                        Task {
                            await self.ensurerepofontsdownloaded(repo)
                            await MainActor.run {
                                self.pendingdownload.remove(url)
                            }
                        }
                    case .failure(let error):
                        repos[idx].data = nil
                        repos[idx].error = error.localizedDescription
                    }
                }
            }
        }
    }

    func addrepo(_ urlString: String) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, URL(string: trimmed) != nil else { return }
        guard !repourls.contains(trimmed) else { return }
        repourls.append(trimmed)
        saverepourls(repourls)
        pendingdownload.insert(trimmed)
        await refreshrepos()
    }

    func removerepo(_ url: String) {
        repourls.removeAll { $0 == url }
        if repourls.isEmpty {
            repourls = [defaultrepo]
        }
        saverepourls(repourls)
        Task { @MainActor in
            await refreshrepos()
        }
    }

    func dlallfonts(for repoURL: String, repo: fontrepodata? = nil) async {
        let repoData = repo ?? repos.first(where: { $0.url == repoURL })?.data
        guard let repoData else { return }
        for font in repoData.fonts {
            await dlfont(font, repo: repoData)
        }
    }

    func ensurerepofontsdownloaded(_ repo: fontrepodata) async {
        for font in repo.fonts {
            guard let localurl = localfonturl(repo: repo, font: font) else { continue }
            if FileManager.default.fileExists(atPath: localurl.path) {
                continue
            }
            await dlfont(font, repo: repo)
        }
    }

    func dlfont(_ font: fontrepofont, repo: fontrepodata) async {
        await MainActor.run { downloading.insert(font.url) }
        defer { Task { @MainActor in downloading.remove(font.url) } }

        guard let remoteurl = URL(string: font.url) else { return }
        guard let localurl = localfonturl(repo: repo, font: font) else { return }
        if FileManager.default.fileExists(atPath: localurl.path) { return }

        do {
            let (tempurl, _) = try await URLSession.shared.download(from: remoteurl)
            let fm = FileManager.default
            try fm.createDirectory(at: localurl.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: localurl.path) {
                try fm.removeItem(at: localurl)
            }
            try fm.moveItem(at: tempurl, to: localurl)
        } catch {
            await MainActor.run {
                if let idx = repos.firstIndex(where: { $0.data?.name == repo.name }) {
                    repos[idx].error = error.localizedDescription
                }
            }
        }
    }

    func dlemoji(_ emoji: fontrepofont, repo: fontrepodata) async {
        await MainActor.run { downloading.insert(emoji.url) }
        defer { Task { @MainActor in downloading.remove(emoji.url) } }

        guard let remoteurl = URL(string: emoji.url) else { return }
        guard let localurl = localemojiurl(repo: repo, emoji: emoji) else { return }
        if FileManager.default.fileExists(atPath: localurl.path) { return }

        do {
            let (tempurl, _) = try await URLSession.shared.download(from: remoteurl)
            let fm = FileManager.default
            try fm.createDirectory(at: localurl.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: localurl.path) {
                try fm.removeItem(at: localurl)
            }
            try fm.moveItem(at: tempurl, to: localurl)
        } catch {
            await MainActor.run {
                if let idx = repos.firstIndex(where: { $0.data?.name == repo.name }) {
                    repos[idx].error = error.localizedDescription
                }
            }
        }
    }

    private func fetchrepo(_ urlString: String) async throws -> fontrepodata {
        guard let repourl = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        let (repodata, _) = try await URLSession.shared.data(from: repourl)
        return try JSONDecoder().decode(fontrepodata.self, from: repodata)
    }
}
