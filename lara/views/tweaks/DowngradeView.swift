import SwiftUI
import UIKit

struct RootControllerWrapper: UIViewControllerRepresentable {

    func makeUIViewController(context: Context) -> UIViewController {
        MFSCreateController()
    }

    func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {
    }
}

struct DowngradeView: View {
    var body: some View {
        RootControllerWrapper()
            .ignoresSafeArea()
    }
}
