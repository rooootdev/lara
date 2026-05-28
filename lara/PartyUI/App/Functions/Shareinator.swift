//
//  Shareinator.swift
//  PartyUI
//
//  Created by lunginspector on 2/12/26.
//

import Foundation
import UIKit

@MainActor
public func presentShareSheet(with url: URL) {
    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
       let window = windowScene.windows.first,
       var topController = window.rootViewController {
        
        while let presentedViewController = topController.presentedViewController {
            topController = presentedViewController
        }
        
        let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            activityViewController.popoverPresentationController?.sourceView = topController.view
            activityViewController.popoverPresentationController?.sourceRect = CGRect(
                x: topController.view.bounds.midX,
                y: topController.view.bounds.midY,
                width: 0, height: 0
            )
            activityViewController.popoverPresentationController?.permittedArrowDirections = []
        }
        
        topController.present(activityViewController, animated: true)
    }
}

