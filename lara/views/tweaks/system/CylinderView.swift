import UIKit
import UniformTypeIdentifiers

VStack(alignment: .leading, spacing: 6) {
    Text("Cylinder")
        .font(.largeTitle)
        .fontWeight(.bold)
        .foregroundColor(.blue)
}
.padding()

Button(action: {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName("com.lara.cylinder.trigger" as CFString),
        nil,
        nil,
        true
    )   
}) {
    Text("Run Cylinder")
        .fontWeight(.semibold)
        .foregroundColor(.white)
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.blue)
        .cornerRadius(12)
}
.padding()

@objc class FolderBridge: NSObject, UIDocumentPickerDelegate {

    static let shared = FolderBridge()

    private let key = "folderBookmark"
    private weak var presenterVC: UIViewController?

    @objc static var sharedFolderURL: URL?

    private override init() {}

    // MARK: - Public API (NO PARAMS)

    @objc func requestFolder() {
        guard let vc = getTopViewController() else {
            print("❌ No view controller found")
            return
        }

        presenterVC = vc

        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.folder],
            asCopy: false
        )

        picker.delegate = self
        vc.present(picker, animated: true)
    }

    // MARK: - Get top VC

    private func getTopViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else {
            return nil
        }

        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    // MARK: - Save bookmark

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {

        guard let url = urls.first else { return }

        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            UserDefaults.standard.set(bookmark, forKey: key)
            _ = resolveFolder(url)
            if url.startAccessingSecurityScopedResource() {
                // Save to Shared App Group UserDefaults
                if let sharedDefaults = UserDefaults(suiteName: "lara.com.themystery.uitweaks") {
                    sharedDefaults.set(url.path, forKey: "sharedFolderPath")
                    sharedDefaults.synchronize()
                }
            }
            FolderBridge.sharedFolderURL = url
        } catch {
            print("Bookmark error:", error)
        }
    }

    // MARK: - Resolve

    @objc func resolveFolder(_ incomingURL: URL? = nil) -> URL? {

        var url: URL?
        var stale = false

        if let incomingURL = incomingURL {
            url = incomingURL
        } else if let data = UserDefaults.standard.data(forKey: key) {
            url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        }

        guard let finalURL = url else { return nil }

        if finalURL.startAccessingSecurityScopedResource() {
            FolderBridge.sharedFolderURL = finalURL
        } else {
            print("❌ Cannot access folder")
        }

        return finalURL
    }
}