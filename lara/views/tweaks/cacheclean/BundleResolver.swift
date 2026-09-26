//
//  BundleResolver.swift
//  lara
//

import Foundation
import UIKit

// MARK: - Model

struct ResolvedApp {
    let dataUUID: String
    let bundleID: String
    let bundlePath: String
    let name: String
    let icon: UIImage?
}

// MARK: - Resolver

final class BundleResolver {

    private let fm = FileManager.default

    private let bundleRoot = "/var/containers/Bundle/Application"
    private let dataRoot = "/var/mobile/Containers/Data/Application"

    // MARK: Public

    func resolveAll() -> [ResolvedApp] {

        let bundleMap = buildBundleMap()

        guard let dataContainers = try? fm.contentsOfDirectory(atPath: dataRoot) else {
            return []
        }

        var results: [ResolvedApp] = []

        for dataUUID in dataContainers {

            let dataPath = dataRoot + "/" + dataUUID
            let metaPath = dataPath + "/.com.apple.mobile_container_manager.metadata.plist"

            // MARK: STEP 1 - metadata
            var bundleID =
                NSDictionary(contentsOfFile: metaPath)?["MCMMetadataIdentifier"] as? String

            // MARK: STEP 2 - fallback scan inside container
            if bundleID == nil {
                bundleID = findBundleIDInDataContainer(dataPath)
            }

            // ❗ DO NOT DROP APP
            let finalBundleID = bundleID ?? "unknown.\(dataUUID)"

            // MARK: STEP 3 - resolve bundle path
            let resolvedBundlePath =
                bundleID != nil
                ? (bundleMap[finalBundleID] ?? findBundlePathFallback(bundleID: finalBundleID))
                : nil

            let finalBundlePath = resolvedBundlePath ?? ""

            // MARK: STEP 4 - name resolution (NEVER FAIL)
            let finalName = readSafeName(
                bundlePath: finalBundlePath.isEmpty ? dataPath : finalBundlePath,
                fallback: dataUUID
            )

            // MARK: STEP 5 - icon resolution (NEVER FAIL)
            let finalIcon =
                finalBundlePath.isEmpty
                ? UIImage(systemName: "app")
                : readIcon(finalBundlePath)

            results.append(
                ResolvedApp(
                    dataUUID: dataUUID,
                    bundleID: finalBundleID,
                    bundlePath: finalBundlePath,
                    name: finalName,
                    icon: finalIcon
                )
            )
        }

        return results
    }

    // MARK: Bundle Map

    private func buildBundleMap() -> [String: String] {

        var map: [String: String] = [:]

        guard let roots = try? fm.contentsOfDirectory(atPath: bundleRoot) else {
            return map
        }

        for root in roots {

            let rootPath = bundleRoot + "/" + root

            guard let items = try? fm.contentsOfDirectory(atPath: rootPath) else {
                continue
            }

            for item in items where item.hasSuffix(".app") {

                let appPath = rootPath + "/" + item

                // PRIMARY
                if let meta = NSDictionary(contentsOfFile: appPath + "/.com.apple.mobile_container_manager.metadata.plist"),
                   let bundleID = meta["MCMMetadataIdentifier"] as? String {
                    map[bundleID] = appPath
                    continue
                }

                // FALLBACK
                if let info = NSDictionary(contentsOfFile: appPath + "/Info.plist"),
                   let bundleID = info["CFBundleIdentifier"] as? String {
                    map[bundleID] = appPath
                }
            }
        }

        return map
    }

    // MARK: Data container scan

    private func findBundleIDInDataContainer(_ dataPath: String) -> String? {

        guard let items = try? fm.contentsOfDirectory(atPath: dataPath) else {
            return nil
        }

        for item in items where item.hasSuffix(".app") {

            let infoPath = dataPath + "/" + item + "/Info.plist"

            if let info = NSDictionary(contentsOfFile: infoPath),
               let bundleID = info["CFBundleIdentifier"] as? String {
                return bundleID
            }
        }

        return nil
    }

    // MARK: Bundle fallback

    private func findBundlePathFallback(bundleID: String) -> String? {

        guard let roots = try? fm.contentsOfDirectory(atPath: bundleRoot) else {
            return nil
        }

        for root in roots {

            let rootPath = bundleRoot + "/" + root

            guard let items = try? fm.contentsOfDirectory(atPath: rootPath) else {
                continue
            }

            for item in items where item.hasSuffix(".app") {

                let appPath = rootPath + "/" + item

                if let info = NSDictionary(contentsOfFile: appPath + "/Info.plist"),
                   let id = info["CFBundleIdentifier"] as? String,
                   id == bundleID {
                    return appPath
                }
            }
        }

        return nil
    }

    // MARK: SAFE NAME (never empty)

    private func readSafeName(bundlePath: String, fallback: String) -> String {

        let infoPath = bundlePath + "/Info.plist"

        guard let info = NSDictionary(contentsOfFile: infoPath) else {
            return fallback
        }

        return info["CFBundleDisplayName"] as? String ??
               info["CFBundleName"] as? String ??
               fallback
    }

    // MARK: Icon

    private func readIcon(_ bundlePath: String) -> UIImage? {

        let infoPath = bundlePath + "/Info.plist"

        guard let info = NSDictionary(contentsOfFile: infoPath) else {
            return UIImage(systemName: "app")
        }

        if let icons = info["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let iconName = files.last {

            let path = bundlePath + "/" + iconName

            return UIImage(contentsOfFile: path)
                ?? UIImage(contentsOfFile: path + "@2x.png")
                ?? UIImage(contentsOfFile: path + ".png")
        }

        return UIImage(systemName: "app")
    }
}
