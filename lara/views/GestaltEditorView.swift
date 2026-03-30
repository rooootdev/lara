import SwiftUI

struct GestaltEditorView: View {
    @Environment(\.dismiss) var dismiss
    @State private var gestaltText: String = ""
    @State private var isLoading: Bool = true
    @State private var statusMessage: String = ""
    
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
                .padding()
            }
        }
        .onAppear {
            loadGestalt()
        }
    }

    func loadGestalt() {
        guard let data = vfs_read_swift(gestaltPath) else {
            statusMessage = "Mobilegestalt not found"
            isLoading = false
            return
        }

        do {
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            let xmlData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            if let text = String(data: xmlData, encoding: .utf8) {
                self.gestaltText = text
            }
        } catch {
            statusMessage = "Unknown parse- error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func applyGestaltChanges() {
        statusMessage = "Applying..."
        guard let xmlData = gestaltText.data(using: .utf8) else { return }
        
        do {
            let plist = try PropertyListSerialization.propertyList(from: xmlData, options: .mutableContainers, format: nil)
            let binaryData = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            
            if vfs_write_swift(gestaltPath, binaryData) {
                statusMessage = "Success"
                
                let pid = get_pid_for_name("gestaltd")
                if pid > 0 {
                    kill(pid, SIGKILL)
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    dismiss()
                }
            } else {
                statusMessage = "Failed to apply"
            }
        } catch {
            statusMessage = "Invalid mobilegestalt!"
        }
    }
}
