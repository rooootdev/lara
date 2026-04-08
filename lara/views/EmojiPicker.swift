//
//  EmojiPicker.swift
//  lara
//
//  Created by user on 8/4/2026.
//

import SwiftUI

struct EmojiPicker: View {
    @ObservedObject var mgr: laramgr
    private let emojipath = "/System/Library/Fonts/CoreAddition/AppleColorEmoji-160px.ttc"
    
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        applyemojis(url :"https://github.com/PoomSmart/EmojiFonts/releases/download/17.0.0/AppleColorEmoji.ttc",
                        label: "AppleColorEmoji.ttc")
                    } label: {
                        Text("Apple Color Emoji (default)")
                    }
                    
                    Button {
                        applyemojis(url :"https://github.com/PoomSmart/EmojiFonts/releases/download/17.0.0/AppleColorEmoji-pixel.ttc",
                        label: "AppleColorEmoji-pixel.ttc")
                    } label: {
                        Text("Apple Color Emoji (pixel)")
                    }
                    
                    Button {
                        applyemojis(url :"https://github.com/PoomSmart/EmojiFonts/releases/download/17.0.0/twemoji.ttc",
                        label: "twemoji.ttc")
                    } label: {
                        Text("Twemoji")
                    }
                    
                    Button {
                        applyemojis(url :"https://github.com/PoomSmart/EmojiFonts/releases/download/17.0.0/blobmoji.ttc",
                        label: "blobmoji.ttc")
                    } label: {
                        Text("Blobmoji")
                    }
                    
                    Button {
                        applyemojis(url :"https://github.com/PoomSmart/EmojiFonts/releases/download/17.0.0/oneui.ttc",
                        label: "oneui.ttc")
                    } label: {
                        Text("OneUI")
                    }
                    
                    Button {
                        applyemojis(url :"https://github.com/PoomSmart/EmojiFonts/releases/dow;nload/17.0.0/noto-emoji.ttc",
                        label: "noto-emoji.ttc")
                    } label: {
                        Text("Noto Emoji")
                    }
                }
                
                Section {
                    Text(globallogger.logs.last ?? "No logs yet")
                        .font(.system(size: 13, design: .monospaced))
                    
                    if #unavailable(iOS 18.2) {
                        Button("Respring") {
                            mgr.respring()
                        }
                    }
                }
            }
            .navigationTitle("Emoji Overwrite")

        }
    }
    
    private func applyemojis(url: String, label: String) {
        Task {
            let fm = FileManager.default
            var source: URL?
            
            if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
                let fileURL = docs.appendingPathComponent("Emojis").appendingPathComponent(label)
                if !fm.fileExists(atPath: fileURL.path) {
                    mgr.logmsg("downloading emojis from \(url)")
                    source = await downloademoji(url: url)
                    if source == nil {
                        mgr.logmsg("download failed!")
                        return
                    }
                } else {
                    source = fileURL
                }
            }
            
            guard let src = source else {
                mgr.logmsg("no source");
                return
            }
            
            let success = mgr.vfsoverwritefromlocalpath(target: emojipath, source: src.path)
            
            success ? mgr.logmsg("emoji changed to \(label)") : mgr.logmsg("failed to change emojis")
        }
    }
}



private func downloademoji(url: String) async -> URL? {
    guard let remoteurl = URL(string: url) else { return nil }
    let fm = FileManager.default
    let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let dir = docs.appendingPathComponent("Emojis")
    
    do {
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }

        let dest = dir.appendingPathComponent(remoteurl.lastPathComponent)
        if fm.fileExists(atPath: dest.path) {
            return dest
        }
        
        let (tempurl, _) = try await URLSession.shared.download(from: remoteurl)

        try fm.moveItem(at: tempurl, to: dest)
        return dest
    } catch {
        return nil
    }
}

