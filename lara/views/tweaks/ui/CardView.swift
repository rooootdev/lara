//
//  CardView.swift
//  lara
//
//  Created by ruter on 29.03.26.
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers

enum replaceoption: String, CaseIterable, Identifiable {
    case photos = "Photos"
    case files = "Files"
    
    var id: String { self.rawValue }
}

struct CardView: View {
    @ObservedObject private var mgr = laramgr.shared
    @State private var cards: [carditem] = []
    @State private var status: String?
    @State private var working = false
    @State private var showimgpicker = false
    @State private var showdocpicker = false
    @State private var pendingcard: carditem?
    @State private var pickedimgdata: Data?
    @State private var shownumbereditor = false
    @State private var cardnuminput = ""
    @State private var currentcardnum = ""
    @State private var pendingnumcard: carditem?
    @State private var pendingrestorecard: carditem?
    @State private var promptforrespring = false

    private static let cardfiles = [
        "cardBackground@2x.png",
        "cardBackgroundCombined@2x.png",
        "cardBackgroundCombined-watch@2x.png"
    ]

    private struct carditem: Identifiable {
        let id: String
        let imgpath: String
        let dirpath: String
        let bundlename: String
        let bgfilename: String
    }

    private struct cardrow: View {
        let card: carditem
        let onreplace: (carditem, replaceoption) -> Void
        let onrestore: (carditem) -> Void
        let oneditnum: (carditem) -> Void
        let previewimg: (carditem) -> UIImage?

        @State private var selected: replaceoption? = nil

        var body: some View {
            Section(header: Text(card.bgfilename)) {
                HStack(spacing: 12) {
                    if let img = previewimg(card) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 140, height: 90)
                            .cornerRadius(8)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 140, height: 90)
                            .overlay(
                                Image(systemName: "creditcard.fill")
                                    .foregroundColor(.secondary)
                            )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(card.bundlename)
                            .font(.headline)

                        Text(card.imgpath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()
                }

                Picker("Replace", selection: $selected) {
                    Text("Select... ").tag(replaceoption?.none)
                    ForEach(replaceoption.allCases) { option in
                        Text(option.rawValue).tag(Optional(option))
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: selected) { option in
                    guard let option = option else { return }
                    onreplace(card, option)
                    selected = nil
                }

                Button("Restore") {
                    onrestore(card)
                }
                .foregroundColor(.red)

                Button("Edit Card Number") {
                    oneditnum(card)
                }
            }
        }
    }
    
    var body: some View {
        List {
            Section {
                Button {
                    refresh()
                } label: {
                    if working {
                        HStack {
                            ProgressView()
                            Text("Scanning...")
                        }
                    } else {
                        Text("Refresh")
                    }
                }
                .disabled(working)
            } header: {
                Text("Actions")
            } footer: {
                Text("Uses SBX first and falls back to VFS for overwrite.\nGet card images [here](https://dynalist.io/d/ldKY6rbMR3LPnWz4fTvf_HCh).")
            }

            if cards.isEmpty {
                Section {
                    Text("No cards found.")
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(cards) { card in
                    cardrow(
                        card: card,
                        onreplace: { card, option in
                            pendingcard = card
                            switch option {
                            case .photos:
                                showimgpicker = true
                            case .files:
                                showdocpicker = true
                            }
                        },
                        onrestore: { card in
                            pendingrestorecard = card
                            restoreimg(card: card)
                        },
                        oneditnum: { card in
                            pendingnumcard = card
                            currentcardnum = readcardnum(for: card) ?? ""
                            cardnuminput = currentcardnum
                            shownumbereditor = true
                        },
                        previewimg: previewimg
                    )
                }

                Section {
                    HStack(alignment: .top) {
                        AsyncImage(url: URL(string: "https://github.com/drkm9743.png")) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())

                        VStack(alignment: .leading) {
                            Text("drkm9743")
                                .font(.headline)

                            Text("Inspiration.")
                                .font(.subheadline)
                                .foregroundColor(Color.secondary)
                        }

                        Spacer()
                    }
                    .onTapGesture {
                        if let url = URL(string: "https://github.com/drkm9743"),
                           UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url)
                        }
                    }
                } header: {
                    Text("Credits")
                }
            }
        }
        .navigationTitle("Card Overwrite")
        .alert("Status", isPresented: Binding(
            get: { status != nil },
            set: { presented in
                if !presented {
                    status = nil
                    promptforrespring = false
                }
            }
        )) {
            if promptforrespring {
                Button("Respring") {
                    status = nil
                    promptforrespring = false
                    mgr.respring()
                }
                Button("Later", role: .cancel) {
                    status = nil
                    promptforrespring = false
                }
            } else {
                Button("OK") { status = nil }
            }
        } message: {
            Text(status ?? "")
        }
        .alert("Edit Card Number", isPresented: $shownumbereditor) {
            TextField("Suffix", text: $cardnuminput)
            Button("Save") {
                if let card = pendingnumcard {
                    applycardnum(card: card, newsuffix: cardnuminput)
                }
            }
            if let card = pendingnumcard, haspassjsonbackup(card: card) {
                Button("Restore Original", role: .destructive) {
                    restorepassjson(card: card)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(currentcardnum.isEmpty ? "Current suffix: (none)" : "Current suffix: \(currentcardnum)")
        }
        .sheet(isPresented: $showimgpicker) {
            ImagePicker(imageData: $pickedimgdata)
        }
        .sheet(isPresented: $showdocpicker) {
            CardImageDocumentPicker(imgdata: $pickedimgdata)
        }
        .onChange(of: pickedimgdata) { _ in
            guard let card = pendingcard, let data = pickedimgdata else { return }
            pendingcard = nil
            pickedimgdata = nil
            applyreplace(card: card, imgdata: data)
        }
        .onAppear {
            refresh()
        }
    }

    private func refresh() {
        guard !working else { return }
        working = true
        DispatchQueue.global(qos: .userInitiated).async {
            let items = scancards()
            DispatchQueue.main.async {
                self.cards = items
                self.working = false
            }
        }
    }

    private func scancards() -> [carditem] {
        let candidates = [
            "/var/mobile/Library/Passes/Cards",
            "/private/var/mobile/Library/Passes/Cards",
            "/var/mobile/Library/Passes/Passes/Cards",
            "/private/var/mobile/Library/Passes/Passes/Cards"
        ]

        for root in candidates {
            let bundles = collectcardbundles(in: root)
            if !bundles.isEmpty {
                return bundles
            }
        }

        let passdirs = ["/var/mobile/Library/Passes", "/private/var/mobile/Library/Passes"]
        for container in passdirs {
            let topentries = listdir(container)
            for primary in ["Cards", "Passes", "Wallet"] where topentries.contains(primary) {
                let candidate = joinpath(container, primary)
                let bundles = collectcardbundles(in: candidate)
                if !bundles.isEmpty { return bundles }
                let nested = joinpath(candidate, "Cards")
                let nestedbundles = collectcardbundles(in: nested)
                if !nestedbundles.isEmpty { return nestedbundles }
            }
        }

        return []
    }

    private func collectcardbundles(in cardsroot: String) -> [carditem] {
        let entries = listdir(cardsroot)
        guard !entries.isEmpty else { return [] }

        var bundles: [carditem] = []
        var seendirs: Set<String> = []

        for entry in entries where entry != "." && entry != ".." {
            let candidatedir = joinpath(cardsroot, entry)
            if let bgfile = cardbgfile(in: candidatedir) {
                if !seendirs.contains(candidatedir) {
                    bundles.append(carditem(
                        id: candidatedir,
                        imgpath: joinpath(candidatedir, bgfile),
                        dirpath: candidatedir,
                        bundlename: entry,
                        bgfilename: bgfile
                    ))
                    seendirs.insert(candidatedir)
                }
                continue
            }

            let nestedentries = listdir(candidatedir)
            for nested in nestedentries where nested != "." && nested != ".." {
                let nesteddir = joinpath(candidatedir, nested)
                if let bgfile = cardbgfile(in: nesteddir),
                   !seendirs.contains(nesteddir) {
                    bundles.append(carditem(
                        id: nesteddir,
                        imgpath: joinpath(nesteddir, bgfile),
                        dirpath: nesteddir,
                        bundlename: "\(entry)/\(nested)",
                        bgfilename: bgfile
                    ))
                    seendirs.insert(nesteddir)
                }
            }
        }

        return bundles
    }

    private func cardbgfile(in carddir: String) -> String? {
        let files = listdir(carddir)
        guard !files.isEmpty else { return nil }

        for name in Self.cardfiles where files.contains(name) {
            return name
        }
        return nil
    }

    private func listdir(_ path: String) -> [String] {
        let fm = FileManager.default

        for variant in pathvariants(for: path) {
            do {
                return try fm.contentsOfDirectory(atPath: variant)
            } catch {
                continue
            }
        }

        return []
    }

    private func pathvariants(for path: String) -> [String] {
        var variants: [String] = [path]
        if path.hasPrefix("/private/var/") {
            variants.append(String(path.dropFirst("/private".count)))
        } else if path.hasPrefix("/var/") {
            variants.append("/private" + path)
        }
        var unique: [String] = []
        for variant in variants where !unique.contains(variant) {
            unique.append(variant)
        }
        return unique
    }

    private func joinpath(_ parent: String, _ child: String) -> String {
        if parent.hasSuffix("/") { return parent + child }
        return parent + "/" + child
    }

    private func previewimg(for card: carditem) -> UIImage? {
        let lower = card.bgfilename.lowercased()
        if lower.hasSuffix(".pdf") {
            if let doc = PDFDocument(url: URL(fileURLWithPath: card.imgpath)),
               let page = doc.page(at: 0) {
                return page.thumbnail(of: CGSize(width: 640, height: 400), for: .cropBox)
            }
        } else if let img = UIImage(contentsOfFile: card.imgpath) {
            return img
        }

        if mgr.vfsready, let data = mgr.vfsread(path: card.imgpath, maxSize: 8 * 1024 * 1024) {
            if lower.hasSuffix(".pdf") {
                if let doc = PDFDocument(data: data),
                   let page = doc.page(at: 0) {
                    return page.thumbnail(of: CGSize(width: 640, height: 400), for: .cropBox)
                }
            } else {
                return UIImage(data: data)
            }
        }
        return nil
    }

    private func applyreplace(card: carditem, imgdata: Data) {
        guard let image = UIImage(data: imgdata) else {
            status = "Invalid image data"
            return
        }

        let lower = card.bgfilename.lowercased()
        var payload: Data?
        if lower.hasSuffix(".png") {
            payload = image.pngData()
        } else if lower.hasSuffix(".pdf") {
            let pdf = PDFDocument()
            if let page = PDFPage(image: image) {
                pdf.insert(page, at: 0)
                payload = pdf.dataRepresentation()
            }
        } else {
            payload = image.pngData()
        }

        guard let data = payload else {
            status = "Failed to encode image"
            return
        }

        backupifneeded(card: card)
        if writeprefersbx(path: card.imgpath, data: data) {
            clearcache(for: card)
            promptforrespring = true
            status = "Card updated. Respring now?"
        } else {
            status = "Failed to overwrite card"
        }
    }

    private func backupifneeded(card: carditem) {
        let backuppath = card.imgpath + ".backup"
        let fm = FileManager.default
        if fm.fileExists(atPath: backuppath) { return }
        if let data = readprefersbx(path: card.imgpath, maxsize: 16 * 1024 * 1024) {
            _ = writeprefersbx(path: backuppath, data: data)
        }
    }

    private func restoreimg(card: carditem) {
        let backuppath = card.imgpath + ".backup"
        guard FileManager.default.fileExists(atPath: backuppath) else {
            status = "No backup found"
            return
        }
        guard let data = readprefersbx(path: backuppath, maxsize: 16 * 1024 * 1024) else {
            status = "Failed to read backup"
            return
        }
        if writeprefersbx(path: card.imgpath, data: data) {
            clearcache(for: card)
            promptforrespring = true
            status = "Restored card image. Respring now?"
        } else {
            status = "Restore failed"
        }
    }

    private func passjsonpath(for card: carditem) -> String {
        card.dirpath + "/pass.json"
    }

    private func passjsonbackuppath(for card: carditem) -> String {
        card.dirpath + "/pass.json.backup"
    }

    private func haspassjsonbackup(card: carditem) -> Bool {
        FileManager.default.fileExists(atPath: passjsonbackuppath(for: card))
    }

    private func readpassjson(for card: carditem) -> Data? {
        if let data = readprefersbx(path: passjsonpath(for: card), maxsize: 512 * 1024) {
            return data
        }
        return nil
    }

    private func readcardnum(for card: carditem) -> String? {
        guard let data = readpassjson(for: card),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let suffix = json["primaryAccountSuffix"] as? String else {
            return nil
        }
        return suffix
    }

    private func backuppassjsonifneeded(card: carditem) {
        let src = passjsonpath(for: card)
        let backup = passjsonbackuppath(for: card)
        guard !FileManager.default.fileExists(atPath: backup) else { return }
        guard let data = readprefersbx(path: src, maxsize: 512 * 1024) else { return }
        _ = writeprefersbx(path: backup, data: data)
    }

    private func applycardnum(card: carditem, newsuffix: String) {
        guard var json = (readpassjson(for: card)).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) else {
            status = "Failed to read pass.json"
            return
        }
        backuppassjsonifneeded(card: card)
        let trimmed = newsuffix.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            json.removeValue(forKey: "primaryAccountSuffix")
        } else {
            json["primaryAccountSuffix"] = trimmed
        }
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else {
            status = "Failed to encode pass.json"
            return
        }
        if writeprefersbx(path: passjsonpath(for: card), data: data) {
            clearcache(for: card)
            currentcardnum = trimmed
            status = "Card number updated"
        } else {
            status = "Failed to update pass.json"
        }
    }

    private func restorepassjson(card: carditem) {
        let backup = passjsonbackuppath(for: card)
        guard FileManager.default.fileExists(atPath: backup) else {
            status = "No pass.json backup"
            return
        }
        guard let data = readprefersbx(path: backup, maxsize: 512 * 1024) else {
            status = "Failed to read backup"
            return
        }
        if writeprefersbx(path: passjsonpath(for: card), data: data) {
            clearcache(for: card)
            currentcardnum = readcardnum(for: card) ?? ""
            status = "Restored pass.json"
        } else {
            status = "Failed to restore pass.json"
        }
    }

    private func clearcache(for card: carditem) {
        let fm = FileManager.default
        let dir = card.dirpath
        let cachepath: String
        if dir.lowercased().hasSuffix(".pkpass") {
            cachepath = dir.replacingOccurrences(of: "pkpass", with: "cache")
        } else {
            cachepath = dir + ".cache"
        }
        if fm.fileExists(atPath: cachepath) {
            try? fm.removeItem(atPath: cachepath)
        }
    }

    private func readprefersbx(path: String, maxsize: Int) -> Data? {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) {
            return data.count > maxsize ? data.prefix(maxsize) : data
        }
        if mgr.vfsready {
            return mgr.vfsread(path: path, maxSize: maxsize)
        }
        return nil
    }

    private func writeprefersbx(path: String, data: Data) -> Bool {
        do {
            print("(card) writing to \(path)")
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            guard mgr.vfsready else { return false }
            return mgr.vfsoverwritewithdata(target: path, data: data)
        }
    }
}

struct CardImageDocumentPicker: UIViewControllerRepresentable {
    @Binding var imgdata: Data?

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.png, .jpeg, .image]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: CardImageDocumentPicker
        init(_ parent: CardImageDocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }

            if let data = try? Data(contentsOf: url) {
                parent.imgdata = data
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
