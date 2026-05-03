//
//  PasscodeView.swift
//  lara
//
//  Created by ruter on 29.03.26.
//

import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import Compression

struct PasscodeKey: Identifiable {
    let id: String
    let digit: String
    let displayName: String
    
    var sourceFilename: String { "\(id).png" }
}

struct PasscodeView: View {
    @ObservedObject var mgr: laramgr
    
    @State private var selectedKeys: [String: Data] = [:]
    @State private var showImagePicker: String?
    @State private var showFilePicker = false
    @State private var processing = false
    @State private var statusMessage: String = ""
    
    let telephonyOptions = [
        "TelephonyUI-15",
        "TelephonyUI-14",
        "TelephonyUI-13",
        "TelephonyUI-12",
        "TelephonyUI-11",
        "TelephonyUI-10",
        "TelephonyUI-9",
        "TelephonyUI-8"
    ]
    
    let passcodeKeys: [PasscodeKey] = [
        PasscodeKey(id: "0", digit: "0", displayName: "0"),
        PasscodeKey(id: "1", digit: "1", displayName: "1"),
        PasscodeKey(id: "2", digit: "2", displayName: "2"),
        PasscodeKey(id: "3", digit: "3", displayName: "3"),
        PasscodeKey(id: "4", digit: "4", displayName: "4"),
        PasscodeKey(id: "5", digit: "5", displayName: "5"),
        PasscodeKey(id: "6", digit: "6", displayName: "6"),
        PasscodeKey(id: "7", digit: "7", displayName: "7"),
        PasscodeKey(id: "8", digit: "8", displayName: "8"),
        PasscodeKey(id: "9", digit: "9", displayName: "9"),
    ]

    private var passcodeKeyMap: [String: PasscodeKey] {
        Dictionary(uniqueKeysWithValues: passcodeKeys.map { ($0.id, $0) })
    }

    private let passcodeKeyLayout: [String?] = [
        "1", "2", "3",
        "4", "5", "6",
        "7", "8", "9",
        nil, "0", nil
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Import Theme")) {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Import .passthm / .zip File", systemImage: "square.and.arrow.down")
                    }
                }
                
                Section {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 0),
                        GridItem(.flexible(), spacing: 0),
                        GridItem(.flexible(), spacing: 0)
                    ], spacing: 0) {
                        ForEach(Array(passcodeKeyLayout.enumerated()), id: \.offset) { _, keyId in
                            if let keyId, let key = passcodeKeyMap[keyId] {
                                PasscodeKeyButton(
                                    key: key,
                                    imageData: selectedKeys[key.id],
                                    onSelect: {
                                        showImagePicker = key.id
                                    }
                                )
                            } else {
                                Color.clear
                                    .aspectRatio(1, contentMode: .fit)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                
                Section(header: Text("Apply")) {
                    Button("Apply Passcode Theme") {
                        applyTheme()
                    }
                    .disabled(selectedKeys.isEmpty || processing)
                    
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .foregroundColor(statusMessage.contains("Error") ? .red : .green)
                            .font(.footnote)
                    }
                }
                
                Section(header: Text("Danger Zone")) {
                    Button("Clear All Keys", role: .destructive) {
                        selectedKeys.removeAll()
                    }
                }
            }
            .headerProminence(.increased)
            .navigationTitle("Passcode Theme")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $showImagePicker) { keyId in
                ImagePicker(imageData: $selectedKeys[keyId])
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [UTType(filenameExtension: "passthm") ?? .zip, .zip],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
        }
    }
    
    func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importPassthmFile(url: url)
        case .failure(let error):
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }
    
    func importPassthmFile(url: URL) {
        processing = true
        statusMessage = "Importing theme..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            do {
                let data = try Data(contentsOf: url)
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer {
                    try? FileManager.default.removeItem(at: tempDir)
                }
                
                let zipPath = tempDir.appendingPathComponent("theme.zip")
                try data.write(to: zipPath)
                
                try unzipFile(at: zipPath, to: tempDir)
                
                let extractedKeys = try findAndExtractImages(from: tempDir)
                
                DispatchQueue.main.async {
                    for (keyId, imageData) in extractedKeys {
                        selectedKeys[keyId] = imageData
                    }
                    processing = false
                    statusMessage = "Imported \(extractedKeys.count) key(s)"
                }
            } catch {
                DispatchQueue.main.async {
                    processing = false
                    statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func unzipFile(at source: URL, to destination: URL) throws {
        let fileData = try Data(contentsOf: source)
        var offset = 0
        
        while offset < fileData.count - 4 {
            let signature = fileData.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }
            
            if signature == 0x04034b50 {
                guard let entry = readLocalFileEntry(data: fileData, offset: offset) else { break }
                
                let entryName = String(data: fileData.subdata(in: offset+30..<offset+30+entry.nameLength), encoding: .utf8) ?? ""
                
                if !entryName.hasSuffix("/") {
                    let entryDestination = destination.appendingPathComponent(entryName)
                    let parentDir = entryDestination.deletingLastPathComponent()
                    try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                    
                    if entry.compressionMethod == 0 {
                        let fileDataEntry = fileData.subdata(in: offset+30+entry.nameLength..<offset+30+entry.nameLength+entry.compressedSize)
                        try fileDataEntry.write(to: entryDestination)
                    } else if entry.compressionMethod == 8 {
                        let compressedData = fileData.subdata(in: offset+30+entry.nameLength..<offset+30+entry.nameLength+entry.compressedSize)
                        let decompressed = decompress(deflate: compressedData, originalSize: entry.uncompressedSize)
                        if let decompressed {
                            try decompressed.write(to: entryDestination)
                        }
                    }
                }
                
                offset += 30 + entry.nameLength + entry.extraLength + entry.compressedSize
            } else {
                break
            }
        }
    }
    
    struct ZipEntry {
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let nameLength: Int
        let extraLength: Int
    }
    
    func readLocalFileEntry(data: Data, offset: Int) -> ZipEntry? {
        guard offset + 30 <= data.count else { return nil }
        
        let compressionMethod = data.subdata(in: offset+8..<offset+10).withUnsafeBytes { $0.load(as: UInt16.self) }
        let compressedSize = Int(data.subdata(in: offset+18..<offset+22).withUnsafeBytes { $0.load(as: UInt32.self) })
        let uncompressedSize = Int(data.subdata(in: offset+22..<offset+26).withUnsafeBytes { $0.load(as: UInt32.self) })
        let nameLength = Int(data.subdata(in: offset+26..<offset+28).withUnsafeBytes { $0.load(as: UInt16.self) })
        let extraLength = Int(data.subdata(in: offset+28..<offset+30).withUnsafeBytes { $0.load(as: UInt16.self) })
        
        return ZipEntry(compressionMethod: compressionMethod, compressedSize: compressedSize, uncompressedSize: uncompressedSize, nameLength: nameLength, extraLength: extraLength)
    }
    
    func decompress(deflate data: Data, originalSize: Int) -> Data? {
        guard originalSize > 0 else { return Data() }
        
        let pageSize = 16384
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: originalSize)
        defer { destinationBuffer.deallocate() }
        
        let result = data.withUnsafeBytes { (sourceBuffer: UnsafeRawBufferPointer) -> Int in
            guard let baseAddress = sourceBuffer.baseAddress else { return 0 }
            return compression_decode_buffer(
                destinationBuffer,
                originalSize,
                baseAddress.assumingMemoryBound(to: UInt8.self),
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }
        
        return result == originalSize ? Data(bytes: destinationBuffer, count: originalSize) : nil
    }
    
    func findAndExtractImages(from directory: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return result
        }
        
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard ext == "png" || ext == "jpg" || ext == "jpeg" else { continue }
            
            let filename = fileURL.lastPathComponent.lowercased()
            let fullPath = fileURL.path.lowercased()
            
            if let keyId = matchFilenameToKey(filename) ?? matchFilenameToKey(fullPath) {
                if let imageData = try? Data(contentsOf: fileURL) {
                    result[keyId] = imageData
                }
            }
        }
        
        return result
    }
    
    func matchFilenameToKey(_ filename: String) -> String? {
        let lowercased = filename.lowercased()
        
        for i in 0...9 {
            if lowercased.contains("other-2-\(i)--dark") ||
                lowercased.contains("-\(i)-") ||
                lowercased.contains("-\(i)@") ||
                lowercased.contains("_\(i)_") ||
                lowercased.contains("_\(i)@") ||
                lowercased.contains("/\(i).png") ||
                lowercased.contains("/\(i).jpg") ||
                lowercased.contains("/\(i).jpeg") {
                return String(i)
            }
        }
        
        return nil
    }
    
    func applyTheme() {
        guard mgr.sbxready else {
            statusMessage = "Error: SBX not ready"
            return
        }
        
        processing = true
        statusMessage = "Applying theme..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let basePath = resolveTelephonyBasePath() else {
                DispatchQueue.main.async {
                    processing = false
                    statusMessage = "Error: TelephonyUI cache not found"
                }
                return
            }
            var successCount = 0
            var failCount = 0
            
            for (keyId, imageData) in selectedKeys {
                let filename = getFilenameForKey(keyId)
                let targetPath = "\(basePath)/\(filename)"
                
                if sbxwrite(path: targetPath, data: imageData) {
                    successCount += 1
                    mgr.logmsg("Applied \(filename) to \(targetPath)")
                } else {
                    failCount += 1
                    mgr.logmsg("Failed to apply \(filename)")
                }
            }
            
            DispatchQueue.main.async {
                processing = false
                if failCount == 0 {
                    statusMessage = "applied \(successCount) key(s)"
                } else {
                    statusMessage = "applied \(successCount), failed \(failCount)"
                }
            }
        }
    }

    func resolveTelephonyBasePath() -> String? {
        var candidates: [String] = []
        for version in telephonyOptions {
            candidates.append("/var/mobile/Library/Caches/\(version)")
            candidates.append("/var/mobile/Library/Caches/com.apple.\(version)")
            candidates.append("/var/mobile/Library/Caches/com.apple.\(version.lowercased())")
            candidates.append("/var/mobile/Library/Caches/com.apple.TelephonyUI/\(version)")
            candidates.append("/var/mobile/Library/Caches/com.apple.telephonyui/\(version)")
        }

        for path in candidates {
            if sbxdirExists(path: path) {
                mgr.logmsg("TelephonyUI cache: \(path)")
                return path
            }
        }

        mgr.logmsg("TelephonyUI cache not found. Tried: \(candidates.joined(separator: ", "))")
        return nil
    }

    func sbxdirExists(path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    func sbxwrite(path: String, data: Data) -> Bool {
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            return false
        }
    }
    
    func getFilenameForKey(_ keyId: String) -> String {
        switch keyId {
        case "delete": return "other-2-DELETE--dark.png"
        case "cancel": return "other-2-CANCEL--dark.png"
        default: return "other-2-\(keyId)--dark.png"
        }
    }
}

struct PasscodeKeyButton: View {
    let key: PasscodeKey
    let imageData: Data?
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            GeometryReader { geo in
                ZStack {
                    if let data = imageData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.width)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.width)
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var imageData: Data?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            guard let result = results.first else { return }
            
            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                guard let image = object as? UIImage else { return }
                guard let self else { return }
                
                let resized = self.resizeImage(image, targetHeight: 202)
                if let pngData = resized.pngData() {
                    DispatchQueue.main.async {
                        self.parent.imageData = pngData
                    }
                }
            }
        }
        
        func resizeImage(_ image: UIImage, targetHeight: CGFloat) -> UIImage {
            let scale = targetHeight / image.size.height
            let newWidth = image.size.width * scale
            let newSize = CGSize(width: newWidth, height: targetHeight)
            
            let renderer = UIGraphicsImageRenderer(size: newSize)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
    }
}
