import SwiftUI
import UniformTypeIdentifiers

struct GestaltEditorView: View {
    @Environment(\.dismiss) var dismiss
    @State private var gestaltText: String = ""
    @State private var isLoading: Bool = false
    @State private var statusMessage: String = "Import the mobilegestalt here after getting the mobilegestalt from shortcuts app."
    @State private var isImporting: Bool = false
    
    let gestaltPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"

    var body: some View {
        ZStack {
            Color(red: 0.1, green: 0.1, blue: 0.1).ignoresSafeArea()
            
            VStack(spacing: 0) {
                HStack {
                    Text("Currently editing mobilegestalt...")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                
                if isLoading {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                    Spacer()
                } else {
                    TextEditor(text: $gestaltText)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white)
                        .scrollContentBackground(.hidden)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.yellow)
                        .padding(.top, 5)
                }

                HStack(spacing: 12) {
                    Button(action: {
                        isImporting = true
                    }) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 20, weight: .bold))
                            .frame(width: 55, height: 55)
                            .background(Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    
                Button(action: {
                    applyGestaltChanges()
                }) {
                    Text("Apply")
                        .font(.system(size: 16, weight: .black, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .padding()
        }
    }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.propertyList, .data, .xml],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result: result)
        }
    }
func handleImport(result: Result<[URL], Error>) {
        isLoading = true
        do {
            guard let fileURL = try result.get().first else { return }
            
            guard fileURL.startAccessingSecurityScopedResource() else {
                statusMessage = "Permission denied to read file"
                isLoading = false
                return
            }
            defer { fileURL.stopAccessingSecurityScopedResource() }
            
            let data = try Data(contentsOf: fileURL)
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            let xmlData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            
            if let text = String(data: xmlData, encoding: .utf8) {
                self.gestaltText = text
                self.statusMessage = "File imported successfully!"
            }
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func applyGestaltChanges() {
        if gestaltText.isEmpty {
            statusMessage = "Nothing to apply."
            return
        }
        
        statusMessage = "Applying..."
        guard let xmlData = gestaltText.data(using: .utf8) else { return }
        
        do {
            let plist = try PropertyListSerialization.propertyList(from: xmlData, options: .mutableContainers, format: nil)
            let binaryData = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            
            if vfs_write_swift(gestaltPath, binaryData) {
                statusMessage = "Successfully wrote mobilegestalt, Trying to refresh..."

                for i in 1...3 {
                    let pid = get_pid_for_name("gestaltd")
                    if pid > 0 {
                        kill(pid, SIGKILL)
                        print("Attempted to refreshe gestaltd (attempt \(i))")
                    }
                    Thread.sleep(forTimeInterval: 0.1)
                }

                let bpid = get_pid_for_name("backboardd")
                if bpid > 0 {
                    kill(bpid, SIGKILL)
                }

                statusMessage = "Successfuly applied mobilegestalt!"
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    dismiss()
                }
            } else {
                statusMessage = "Failed to apply changes..."
            }
        } catch {
            statusMessage = "Invalid mobilegestalt!"
        }
    }
}
