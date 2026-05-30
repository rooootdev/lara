import SwiftUI

struct RootControllerWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        UINavigationController(
            rootViewController: MFSRootViewController()
        )
    }

    func updateUIViewController(
        _ uiViewController: UINavigationController,
        context: Context
    ) {}
}

struct DowngradeView: View {
    var body: some View {
        RootControllerWrapper()
            .ignoresSafeArea()
    }
}
