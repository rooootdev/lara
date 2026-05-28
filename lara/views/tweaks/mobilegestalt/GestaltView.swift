//
//  EditorView.swift
//  lara
//
//  Created by ruter on 27.03.26.
//

// Most of the code is from Duy's SparseBox
// thank you @jurre111 for the original implementation + all the nugget tweak implements
// thank you @lunginspector for the rewrite + tweak additions

import SwiftUI

enum fileloc: String, CaseIterable {
    case springboard = "/var/Managed Preferences/mobile/com.apple.springboard.plist"
    case footnote = "/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles/SharedDeviceConfiguration.plist"
    case airdrop = "/var/Managed Preferences/mobile/com.apple.sharingd.plist"
    case nanoregistry = "/var/mobile/Library/Preferences/com.apple.NanoRegistry.plist"

    case globalprefs = "/var/Managed Preferences/mobile/.GlobalPreferences.plist"
    case appstore = "/var/Managed Preferences/mobile/com.apple.AppStore.plist"
    case backboardd = "/var/Managed Preferences/mobile/com.apple.backboardd.plist"
    case coremotion = "/var/Managed Preferences/mobile/com.apple.CoreMotion.plist"
    case pasteboard = "/var/Managed Preferences/mobile/com.apple.Pasteboard.plist"
    case notes = "/var/Managed Preferences/mobile/com.apple.mobilenotes.plist"
    case uikit = "/var/Managed Preferences/mobile/com.apple.UIKit.plist"
}

let mgCurrentPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"

struct GestaltView: View {
    @AppStorage("gestaltwarn") private var gestaltwarn: Bool = true
    @AppStorage("mgDeviceName") private var mgDeviceName: String = ""
    
    let mgr: laramgr
    @State private var mgCurrentDict: NSMutableDictionary = NSMutableDictionary()
    @State private var isGestaltVaild: Bool = false
    
    @State private var showgestaltwarn: Bool = false
    @State private var mgSubtype: Int = 0
    @State private var mgOriginalSubtype: Int = 0
    @State private var mgEnableDeviceName: Bool = false
    @State private var mgProductType: String = ""
    
    @State private var mgShowFileSheet: Bool = false
    
    @State private var nuggetValues: [String: Bool] = [:]
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: HeaderLabel(text: "Applying", icon: "checkmark")) {
                    Button {
                        applyGestalt()
                    } label: {
                        Text("Apply Tweaks")
                    }
                    
                    Button {
                        resetnugget()
                        restoreGestalt()
                    } label: {
                        Text("Reset Tweaks")
                    }
                }
                
                // artwork tweaks will be added when applying mobilegestalt because there's no "toggleable" bindings.
                Section(header: HeaderLabel(text: "Device Artwork", icon: "paintbrush.pointed")) {
                    Picker(selection: $mgSubtype) {
                        Text("Original (\(mgOriginalSubtype))").tag(mgOriginalSubtype)
                        if isDeviceNotBroke() {
                            Text("Disable Dynamic Island").tag(2436)
                        }
                        Text("iPhone 14 Pro").tag(2436)
                        Text("iPhone 14 Pro Max").tag(2796)
                        Text("iPhone 15 Pro Max").tag(2976)
                        if doubleSystemVersion() >= 18.0 {
                            Text("iPhone 16 Pro").tag(2622)
                            Text("iPhone 16 Pro Max").tag(2868)
                        }
                        if doubleSystemVersion() >= 26.0 {
                            Text("iPhone Air").tag(2736)
                        }
                        if UIDevice._hasHomeButton() {
                            Text("iPhone X Gestures").tag(2436)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "iphone")
                                .frame(width: 20, alignment: .center)
                            Text("Subtype")
                            Spacer()
                        }
                    }
                    
                    Toggle("Custom Device Name", isOn: $mgEnableDeviceName)
                    
                    if mgEnableDeviceName {
                        TextField("Device Name", text: $mgDeviceName)
                    }
                }
                
                // basic tweak toggles
                Section(header: HeaderLabel(text: "Software-Oriented Features", icon: "gearshape")) {
                    PlainToggle(text: "Dynamic Island", icon: "platter.filled.top.iphone", minSupportedVersion: 19.0, isOn: mgKeyBinding(["YlEtTtHlNesRBMal1CqRaA"]))
                    PlainToggle(text: "Always On Display", icon: "sun.max", minSupportedVersion: 18.0, isOn: mgKeyBinding(["j8/Omm6s1lsmTDFsXjsBfA", "2OOJf1VhaM7NxfRok3HbWQ"]))
                    PlainToggle(text: "AOD Vibrancy", icon: "rays", minSupportedVersion: 18.0, isOn: mgKeyBinding(["ykpu7qyhqFweVMKtxNylWA"]))
                    PlainToggle(text: "Charge Limit", icon: "battery.100.bolt", minSupportedVersion: 17.0, isOn: mgKeyBinding(["37NVydb//GP/GrhuTN+exg"]))
                    PlainToggle(text: "Boot Chime", icon: "speaker.wave.3", isOn: mgKeyBinding(["QHxt+hGLaBPbQJbXiUJX3w"]))
                    PlainToggle(text: "Liquid Glass LPM", icon: "app.background.dotted", minSupportedVersion: 19.0, isOn: mgKeyBinding(["SAGvsp6O6kAQ4fEfDJpC4Q"]))
                }
                
                Section(header: HeaderLabel(text: "Hardware-Oriented Features", icon: "iphone")) {
                    PlainToggle(text: "Camera Control", icon: "camera.shutter.button", minSupportedVersion: 18.0, isOn: mgKeyBinding(["CwvKxM2cEogD3p+HYgaW0Q", "oOV1jhJbdV3AddkcCg0AEA"]))
                    PlainToggle(text: "Action Button", icon: "button.vertical.left.press", minSupportedVersion: 17.0, isOn: mgKeyBinding(["cT44WE1EohiwRzhsZ8xEsw"]))
                    PlainToggle(text: "Crash Detection", icon: "car", isOn: mgKeyBinding(["HCzWusHQwZDea6nNhaKndw"]))
                    if UIDevice._hasHomeButton() {
                        PlainToggle(text: "Enable Tap to Wake", icon: "hand.tap", isOn: mgKeyBinding(["yZf3GTRMGTuwSV/lD7Cagw"]))
                    }
                    PlainToggle(text: "Pulse Width Modulation", icon: "eye", minSupportedVersion: 19.0, isOn: mgKeyBinding(["6IejgN+1Fmu5/QrZFOIeNw"]))
                }
                
                // some odd bindings in here that i dislike.
                Section(header: HeaderLabel(text: "Eligibility", icon: "checklist")) {
                    PlainToggle(text: "Security Research Device UI", icon: "terminal", minSupportedVersion: 26.0, isOn: mgKeyBinding(["XYlJKKkj2hztRP1NWWnhlw"]))
                    PlainToggle(text: "Disable Region Restrictions", icon: "globe", isOn: mgRegionRestrictionsBinding())
                    PlainToggle(text: "Apple Intelligence", icon: "apple.intelligence", minSupportedVersion: 18.1, isOn: mgKeyBinding(["A62OafQ85EJAiiqKn4agtg"]))
                    HStack(spacing: 10) {
                        Picker("Spoofing", selection: $mgProductType) {
                            Text("Default").tag(machineName())
                            if UIDevice.current.userInterfaceIdiom == .pad {
                                if doubleSystemVersion() >= 17.4 {
                                    Text("iPad Pro 11-inch (M4)").tag("iPad16,3")
                                    Text("iPad Pro 11-inch (M4, Cellular)").tag("iPad16,4")
                                }
                                Text("iPad Pro 11-inch (4th Gen)").tag("iPad14,3")
                                Text("iPad Pro 11-inch (4th Gen, Cellular)").tag("iPad14,4")
                            } else {
                                Text("iPhone 15 Pro").tag("iPhone16,1")
                                Text("iPhone 15 Pro Max").tag("iPhone16,2")
                                if doubleSystemVersion() >= 18.0 {
                                    Text("iPhone 16").tag("iPhone17,3")
                                    Text("iPhone 16 Plus").tag("iPhone17,4")
                                    Text("iPhone 16 Pro").tag("iPhone17,1")
                                    Text("iPhone 16 Pro Max").tag("iPhone17,2")
                                }
                                if doubleSystemVersion() >= 19.0 {
                                    Text("iPhone 17").tag("iPhone18,3")
                                    Text("iPhone 17 Pro").tag("iPhone18,1")
                                    Text("iPhone 17 Pro Max").tag("iPhone18,2")
                                    Text("iPhone Air").tag("iPhone18,4")
                                }
                            }
                        }
                        
                        Button(action: {
                            Alertinator.shared.alert(title: "Device Spoofing Info", body: "Only spoof your device model if you want to download Apple Intelligence. This may break Face ID. If you decide to unspoof and want to keep Apple Intelligence, do NOT re-enter the Apple Intelligence & Siri menu in Settings.")
                        }) {
                            Image(systemName: "info.circle")
                                .frame(width: 24, height: 22)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Section(header: HeaderLabel(text: "iPadOS Features", icon: "ipad")) {
                    let cacheExtra = mgCurrentDict["CacheExtra"] as? NSMutableDictionary
                    
                    PlainToggle(text: "Allow Installing iPadOS Apps", icon: "plus.app", isOn: mgKeyBinding(["9MZ5AdH43csAUajl/dU+IQ"], type: [Int].self, defaultValue: [1], enableValue: [1, 2]))
                    PlainToggle(text: "Apple Pencil Settings", icon: "pencil", isOn: mgKeyBinding(["yhHcB0iH0d1XzPO/CFd3ow"]))
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        PlainToggle(text: "Stage Manager", icon: "squares.leading.rectangle", isOn: mgKeyBinding(["qeaj75wk3HF4DwQ8qbIi7g"]))
                    }
                    PlainToggle(text: "iPadOS UI", icon: "ipad", infoType: .warning, infoMessage: "This is a very dangerous tweak to use! If you use an alphanumeric passcode, DO NOT USE THIS TWEAK AT ALL! Please do not turn off \"Show Dock In Stage Manager\" or your device will BOOTLOOP when rotating to landscape! With these two things in mind, you may experience general instability, or other major issues such as app data randomly disappearing. But I guess some funny multitasking features that still make the device relatively unusable are cool? Whatever dude, I'm not here to tell you how to use your own device.", isOn: mgTrollPadBinding())
                        .disabled(cacheExtra?["+3Uf0Pm5F8Xy7Onyvko0vA"] as? String != "iPhone")
                }
                
                Section(header: HeaderLabel(text: "Internal", icon: "ant")) {
                    PlainToggle(text: "Internal Storage", icon: "externaldrive", isOn: mgKeyBinding(["LBJfwOEzExRxzlAnSuI7eg"]))
                    PlainToggle(text: "Internal Features", icon: "gearshape", isOn: mgInternalStuffBinding())
                    PlainToggle(text: "Metal HUD in All Apps", icon: "terminal", isOn: mgKeyBinding(["EqrsVvjcYDdxHBiQmGhAWw"]))
                }
                
                Section {
                    PlainToggle(
                        text: "Hide Dynamic Island Completely",
                        icon: "capsule",
                        isOn: nuggetbinding(
                            "SBSuppressDynamicIslandCompletely",
                            path: fileloc.springboard.rawValue
                        )
                    )

                    PlainToggle(
                        text: "Authentication Debug Line",
                        icon: "faceid",
                        isOn: nuggetbinding(
                            "SBShowAuthenticationEngineeringUI",
                            path: fileloc.springboard.rawValue
                        )
                    )

                    PlainToggle(
                        text: "Show Build Version",
                        icon: "number",
                        isOn: nuggetbinding(
                            "UIStatusBarShowBuildVersion",
                            path: fileloc.globalprefs.rawValue
                        )
                    )

                    PlainToggle(
                        text: "Force RTL Layout",
                        icon: "arrow.left",
                        isOn: nuggetbinding(
                            "NSForceRightToLeftWritingDirection",
                            path: fileloc.globalprefs.rawValue
                        )
                    )

                    PlainToggle(
                        text: "Keyboard Character Flick",
                        icon: "keyboard",
                        isOn: nuggetbinding(
                            "GesturesEnabled",
                            path: fileloc.globalprefs.rawValue
                        )
                    )

                    PlainToggle(
                        text: "Disable Breadcrumbs",
                        icon: "chevron.backward",
                        isOn: nuggetbinding(
                            "SBNeverBreadcrumb",
                            path: fileloc.springboard.rawValue
                        )
                    )
                } header: {
                    HeaderLabel(text: "UI Tweaks", icon: "eye")
                }
                
                Section {
                    PlainToggle(
                        text: "Disable Lock After Respring",
                        icon: "lock.open",
                        isOn: nuggetbinding(
                            "SBDontLockAfterCrash",
                            path: fileloc.springboard.rawValue
                        )
                    )

                    PlainToggle(
                        text: "Disable Low Battery Alerts",
                        icon: "battery.25",
                        isOn: nuggetbinding(
                            "SBHideLowPowerAlerts",
                            path: fileloc.springboard.rawValue
                        )
                    )

                    PlainToggle(
                        text: "Show Dynamic Island in Screenshots",
                        icon: "camera",
                        isOn: nuggetbinding(
                            "SBAlwaysShowSystemApertureInSnapshots",
                            path: fileloc.springboard.rawValue
                        )
                    )

                    PlainToggle(
                        text: "Play Sound on Paste",
                        icon: "speaker.wave.2",
                        isOn: nuggetbinding(
                            "PlaySoundOnPaste",
                            path: fileloc.pasteboard.rawValue
                        )
                    )

                    PlainToggle(
                        text: "System Paste Notifications",
                        icon: "doc.on.clipboard",
                        isOn: nuggetbinding(
                            "AnnounceAllPastes",
                            path: fileloc.pasteboard.rawValue
                        )
                    )
                } header: {
                    HeaderLabel(text: "SpringBoard", icon: "gear")
                }

                Section {
                    PlainToggle(
                        text: "Metal HUD Debug",
                        icon: "cpu",
                        isOn: nuggetbinding(
                            "MetalForceHudEnabled",
                            path: fileloc.globalprefs.rawValue
                        )
                    )

                    PlainToggle(
                        text: "App Store Debug Gesture",
                        icon: "hand.tap",
                        isOn: nuggetbinding(
                            "debugGestureEnabled",
                            path: fileloc.appstore.rawValue
                        )
                    )

                    PlainToggle(
                        text: "Notes Debug Mode",
                        icon: "note.text",
                        isOn: nuggetbinding(
                            "DebugModeEnabled",
                            path: fileloc.notes.rawValue
                        )
                    )

                    PlainToggle(
                        text: "Show Touches",
                        icon: "hand.point.up.left",
                        isOn: nuggetbinding(
                            "BKDigitizerVisualizeTouches",
                            path: fileloc.backboardd.rawValue
                        )
                    )
                } header: {
                    HeaderLabel(text: "Debug", icon: "ladybug")
                }
            }
            .navigationTitle("MobileGestalt")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        mgShowFileSheet.toggle()
                    }) {
                        Image(systemName: "doc")
                    }
                }
            }
            .onAppear {
                loadCurrentGestalt()
                loadnuggettweaks()
                
                if gestaltwarn {
                    showgestaltwarn = true
                }
            }
            .sheet(isPresented: $mgShowFileSheet) {
                GestaltFileView()
            }
            .alert("Warning", isPresented: $showgestaltwarn) {
                Button("Alright.", role: .cancel) {
                    showgestaltwarn = false
                    gestaltwarn = false
                }
            } message: {
                Text("This stuff is risky! You may temporarily break your device, cause it to crash, or even bootloop. Dont say I didnt warn you.")
            }
        }
    }
    
    private func loadCurrentGestalt() {
        do {
            mgCurrentDict = try loadMutablePlistDictionary(from: URL(fileURLWithPath: mgCurrentPath))
            print(mgCurrentDict.description)
            prepareGestaltData()
        } catch {
            Alertinator.shared.alert(title: "Failed to load current MobileGestalt!", body: "\(error)")
        }
    }
    
    private func prepareGestaltData() {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let mgSavedURL = docsDir.appendingPathComponent("SavedGestalt.plist")
        let mgCurrentURL = URL(fileURLWithPath: mgCurrentPath)
        
        do {
            // check if MobileGestalt has ever been saved, and if it hasn't, save it.
            if !FileManager.default.fileExists(atPath: mgSavedURL.path) {
                try FileManager.default.copyItem(at: mgCurrentURL, to: mgSavedURL)
            }
            
            let mgSavedDict = try loadMutablePlistDictionary(from: mgSavedURL)
            let cacheExtra = mgSavedDict["CacheExtra"] as? NSMutableDictionary ?? NSMutableDictionary()
            let ArtworkDict = cacheExtra["oPeik/9e8lQWMszEjbPzng"] as? NSMutableDictionary ?? NSMutableDictionary()
            
            let currentCacheExtra = mgCurrentDict["CacheExtra"] as? NSMutableDictionary ?? NSMutableDictionary()
            let currentArtworkDict = currentCacheExtra["oPeik/9e8lQWMszEjbPzng"] as? NSMutableDictionary ?? NSMutableDictionary()
            let originalSubType = ArtworkDict["ArtworkDeviceSubType"] as? Int
                ?? currentArtworkDict["ArtworkDeviceSubType"] as? Int
                ?? 0
            mgOriginalSubtype = originalSubType
            mgSubtype = currentArtworkDict["ArtworkDeviceSubType"] as? Int ?? originalSubType

            if let productType = currentCacheExtra["h9jDsbgj7xIVeIQ8S3/X3Q"] as? String, !productType.isEmpty {
                mgProductType = productType
            } else {
                mgProductType = machineName()
            }
            
            let deviceName = ArtworkDict["ArtworkDeviceProductDescription"] as? String
                ?? currentArtworkDict["ArtworkDeviceProductDescription"] as? String
                ?? machineName()
            mgDeviceName = deviceName
            
            if mgDeviceName == "" {
                mgDeviceName = deviceName
            }
        } catch {
            Alertinator.shared.alert(title: "Failed to load data from MobileGestalt!", body: "Please restart the app and try again.\n\nError: \(error)")
        }
    }
    
    private func vaildateCacheExtra(_ dict: NSMutableDictionary) -> Bool {
        guard let cacheExtra = dict["CacheExtra"] as? NSMutableDictionary else { return false }
        return !cacheExtra.allKeys.isEmpty
    }
    
    private func applyGestalt() {
        do {
            // first, update the dictionary with some specific properties.
            let cacheExtra = mgCurrentDict["CacheExtra"] as? NSMutableDictionary ?? NSMutableDictionary()
            if !mgProductType.isEmpty {
                cacheExtra["h9jDsbgj7xIVeIQ8S3/X3Q"] = mgProductType
            }
            
            let ArtworkDict = cacheExtra["oPeik/9e8lQWMszEjbPzng"] as? NSMutableDictionary ?? NSMutableDictionary()
            ArtworkDict["ArtworkDeviceSubType"] = mgSubtype
            if mgEnableDeviceName {
                ArtworkDict["ArtworkDeviceProductDescription"] = mgDeviceName
            }
            
            // then, check to make sure it's actually valid
            if !vaildateCacheExtra(mgCurrentDict) { throw "MobileGestalt is not vaild! Please restart the app." }
            
            // bro please dont bootloop
            let mgData = try verifyPlist(mgCurrentDict, targetPath: mgCurrentPath)
            let result = mgr.lara_overwritefile(target: mgCurrentPath, data: mgData, fallback_vfs: false)
            
            if result.ok {
                Alertinator.shared.alert(title: "Successfully applied MobileGestalt!", body: "Respring to see any changes", actionLabel: "Respring", action: { mgr.respring() })
            } else {
                throw "Overwrite failed: \(result.message)"
            }
        } catch {
            Alertinator.shared.alert(title: "Failed to overwrite MobileGestalt!", body: "\(error)")
        }
    }
    
    private func restoreGestalt() {
        do {
            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let mgSavedURL = docsDir.appendingPathComponent("SavedGestalt.plist")
            
            if FileManager.default.fileExists(atPath: mgSavedURL.path) {
                let restored = try loadMutablePlistDictionary(from: mgSavedURL)
                _ = try verifyPlist(restored, targetPath: mgCurrentPath)
                mgCurrentDict = restored
            } else {
                throw "No MobileGestalt file found!"
            }
        } catch {
            Alertinator.shared.alert(title: "Failed to restore MobileGestalt!", body: "\(error)")
        }
    }
    
    func isDeviceNotBroke() -> Bool {
        let supportedDevices: [String] = ["iPhone15,2", "iPhone15,3", "iPhone15,4", "iPhone15,5", "iPhone16,1", "iPhone16,2", "iPhone17,3", "iPhone17,4", "iPhone17,1", "iPhone17,2", "iPhone18,3", "iPhone18,1", "iPhone18,2", "iPhone17,5"]
        if supportedDevices.contains(machineName()) && doubleSystemVersion() < 19.0 {
            return true
        }
        return false
    }
    
    // https://stackoverflow.com/questions/26028918/how-to-determine-the-current-iphone-device-model
    // read device model from kernel
    func machineName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
    }

    // default = 0 (off in Gesalt Terms), enable = 1 (on)
    // "gesalt" lol (roooot, 12.05.2026)
    // return just returns a boolean
    private func mgKeyBinding<T: Equatable>(_ keys: [String], type: T.Type = Int.self, defaultValue: T? = 0, enableValue: T? = 1) -> Binding<Bool>  {
        // immediately return false if it can't find cacheextra, again why is this here? i think it's safety.
        guard let cacheExtra = mgCurrentDict["CacheExtra"] as? NSMutableDictionary else {
            return State(initialValue: false).projectedValue
        }
        
        // then return the binding
        return Binding(get: {
            // get the value in terms of the type and return it as a bool.
            if let value = cacheExtra[keys.first!] as? T?, let enableValue {
                return value == enableValue
            }
            return false
        }, set: { enabled in
            for key in keys {
                // if it exists inside of the plist, then update it. if not then pull the value completely. that also makes sense.
                if enabled {
                    cacheExtra[key] = enableValue
                } else {
                    cacheExtra.removeObject(forKey: key)
                }
            }
        })
    }
    
    private func mgTrollPadBinding() -> Binding<Bool> {
        guard let cacheData = mgCurrentDict["CacheData"] as? NSMutableData,
                let cacheExtra = mgCurrentDict["CacheExtra"] as? NSMutableDictionary else {
            return State(initialValue: false).projectedValue
        }
        let valueOffset = findcachedataoff("mtrAoWJ3gsq+I90ZnQ0vQw")
        let keys = [
            "uKc7FPnEO++lVhHWHFlGbQ", // ipad
            "mG0AnH/Vy1veoqoLRAIgTA", // MedusaFloatingLiveAppCapability
            "UCG5MkVahJxG1YULbbd5Bg", // MedusaOverlayAppCapability
            "ZYqko/XM5zD3XBfN5RmaXA", // MedusaPinnedAppCapability
            "nVh/gwNpy7Jv1NOk00CMrw", // MedusaPIPCapability,
            "qeaj75wk3HF4DwQ8qbIi7g", // DeviceSupportsEnhancedMultitasking
        ]
        
        return Binding(get: {
            if let value = cacheExtra[keys.first!] as? Int? {
                return value == 1
            }
            return false
        }, set: { enabled in
            if enabled {
                Alertinator.shared.alert(title: "Warning!", body: "This is a very dangerous tweak to use! If you use an alphanumeric passcode, DO NOT USE THIS TWEAK AT ALL! Please do not turn off \"Show Dock In Stage Manager\" or your device will BOOTLOOP when rotating to landscape! With these two things in mind, you may experience general instability, or other major issues such as app data randomly disappearing. But I guess some funny multitasking features that still make the device relatively unusable are cool? Whatever dude, I'm not here to tell you how to use your own device.")
            }
            cacheData.mutableBytes.storeBytes(of: enabled ? 3 : 1, toByteOffset: valueOffset, as: Int.self)
            for key in keys {
                if enabled {
                    cacheExtra[key] = 1
                } else {
                    cacheExtra.removeObject(forKey: key)
                }
            }
        })
    }
    
    func mgRegionRestrictionsBinding() -> Binding<Bool> {
        guard let cacheExtra = mgCurrentDict["CacheExtra"] as? NSMutableDictionary else {
            return State(initialValue: false).projectedValue
        }
        
        return Binding<Bool>(
            get: {
                return cacheExtra["h63QSdBCiT/z0WU6rdQv6Q"] as? String == "US" &&
                    cacheExtra["zHeENZu+wbg7PUprwNwBWg"] as? String == "LL/A"
            },
            set: { enabled in
                if enabled {
                    Alertinator.shared.alert(title: "Warning!", body: "Please do not use this feature to bypass region restrictions that would equate to breaking regional laws (e.g. disabling the camera shutter sound). We will NOT be held responsible for enabling any illegal activites!")
                    cacheExtra["h63QSdBCiT/z0WU6rdQv6Q"] = "US"
                    cacheExtra["zHeENZu+wbg7PUprwNwBWg"] = "LL/A"
                } else {
                    cacheExtra.removeObject(forKey: "h63QSdBCiT/z0WU6rdQv6Q")
                    cacheExtra.removeObject(forKey: "zHeENZu+wbg7PUprwNwBWg")
                }
            }
        )
    }
    
    func mgInternalStuffBinding() -> Binding<Bool> {
        guard let cacheData = mgCurrentDict["CacheData"] as? NSMutableData else {
            return State(initialValue: false).projectedValue
        }
        
        let off_appleInternalInstall = findcachedataoff("EqrsVvjcYDdxHBiQmGhAWw")
        let off_HasInternalSettingsBundle = findcachedataoff("Oji6HRoPi7rH7HPdWVakuw")
        let off_InternalBuild = findcachedataoff("LBJfwOEzExRxzlAnSuI7eg")
        
        return Binding(
            get: {
                return cacheData.bytes.load(fromByteOffset: off_appleInternalInstall, as: Int.self) == 1
            },
            set: { enabled in
                cacheData.mutableBytes.storeBytes(of: enabled ? 1 : 0, toByteOffset: off_appleInternalInstall, as: Int.self)
                cacheData.mutableBytes.storeBytes(of: enabled ? 1 : 0, toByteOffset: off_HasInternalSettingsBundle, as: Int.self)
                cacheData.mutableBytes.storeBytes(of: enabled ? 1 : 0, toByteOffset: off_InternalBuild, as: Int.self)
            }
        )
    }
    
    private func loadnuggettweaks() {
        nuggetValues.removeAll()

        let tweaks: [(String, String)] = [
            ("SBSuppressDynamicIslandCompletely", fileloc.springboard.rawValue),
            ("SBShowAuthenticationEngineeringUI", fileloc.springboard.rawValue),
            ("UIStatusBarShowBuildVersion", fileloc.globalprefs.rawValue),
            ("NSForceRightToLeftWritingDirection", fileloc.globalprefs.rawValue),
            ("NSForceLeftToRightWritingDirection", fileloc.globalprefs.rawValue),
            ("GesturesEnabled", fileloc.globalprefs.rawValue),
            ("SBDisableClockIconSecondsHand", fileloc.globalprefs.rawValue),
            ("SBHardwareButtonHintDropletsAlwaysVisibleInSnapshots", fileloc.globalprefs.rawValue),
            ("BKHideAppleLogoOnLaunch", fileloc.backboardd.rawValue),
            ("SBNeverBreadcrumb", fileloc.springboard.rawValue),
            ("SBShowSupervisionTextOnLockScreen", fileloc.springboard.rawValue),

            ("OverrideTimeLimitEveryoneMode", fileloc.airdrop.rawValue),
            ("SBDontLockAfterCrash", fileloc.springboard.rawValue),
            ("SBDontDimOrLockOnAC", fileloc.springboard.rawValue),
            ("SBHideLowPowerAlerts", fileloc.springboard.rawValue),
            ("SBHideACPower", fileloc.springboard.rawValue),
            ("SBAlwaysShowSystemApertureInSnapshots", fileloc.springboard.rawValue),
            ("SBExtendedDisplayOverrideSupportForAirPlayAndDontFileRadars", fileloc.springboard.rawValue),
            ("SBIconVisibility", fileloc.globalprefs.rawValue),
            ("SBSearchDisabledDomains", fileloc.globalprefs.rawValue),
            ("EnableWakeGestureHaptic", fileloc.coremotion.rawValue),
            ("PlaySoundOnPaste", fileloc.pasteboard.rawValue),
            ("AnnounceAllPastes", fileloc.pasteboard.rawValue),

            ("MetalForceHudEnabled", fileloc.globalprefs.rawValue),
            ("iMessageDiagnosticsEnabled", fileloc.globalprefs.rawValue),
            ("IDSDiagnosticsEnabled", fileloc.globalprefs.rawValue),
            ("VCDiagnosticsEnabled", fileloc.globalprefs.rawValue),
            ("AccessoryDeveloperEnabled", fileloc.globalprefs.rawValue),
            ("debugGestureEnabled", fileloc.appstore.rawValue),
            ("DebugModeEnabled", fileloc.notes.rawValue),
            ("BKDigitizerVisualizeTouches", fileloc.backboardd.rawValue)
        ]

        for (key, path) in tweaks {
            let result = mgr.getplistvalue(path: path, key: key)

            if result.ok, let value = result.value as? Bool {
                nuggetValues[key] = value
            } else {
                nuggetValues[key] = false
            }
        }
    }

    private func nuggetbinding(
        _ key: String,
        path: String
    ) -> Binding<Bool> {
        Binding(
            get: {
                nuggetValues[key] ?? false
            },
            set: { enabled in
                nuggetValues[key] = enabled

                let result = mgr.setplistvalue(
                    path: path,
                    key: (key, enabled ? true : nil),
                    force: true
                )

                if !result.ok {
                    Alertinator.shared.alert(
                        title: "Failed to Apply Tweak",
                        body: result.message
                    )
                }
            }
        )
    }

    private func resetnugget() {
        let tweaks: [(String, String)] = [
            ("SBSuppressDynamicIslandCompletely", fileloc.springboard.rawValue),
            ("SBShowAuthenticationEngineeringUI", fileloc.springboard.rawValue),
            ("UIStatusBarShowBuildVersion", fileloc.globalprefs.rawValue),
            ("NSForceRightToLeftWritingDirection", fileloc.globalprefs.rawValue),
            ("NSForceLeftToRightWritingDirection", fileloc.globalprefs.rawValue),
            ("GesturesEnabled", fileloc.globalprefs.rawValue),
            ("SBDisableClockIconSecondsHand", fileloc.globalprefs.rawValue),
            ("SBHardwareButtonHintDropletsAlwaysVisibleInSnapshots", fileloc.globalprefs.rawValue),
            ("BKHideAppleLogoOnLaunch", fileloc.backboardd.rawValue),
            ("SBNeverBreadcrumb", fileloc.springboard.rawValue),
            ("SBShowSupervisionTextOnLockScreen", fileloc.springboard.rawValue),

            ("OverrideTimeLimitEveryoneMode", fileloc.airdrop.rawValue),
            ("SBDontLockAfterCrash", fileloc.springboard.rawValue),
            ("SBDontDimOrLockOnAC", fileloc.springboard.rawValue),
            ("SBHideLowPowerAlerts", fileloc.springboard.rawValue),
            ("SBHideACPower", fileloc.springboard.rawValue),
            ("SBAlwaysShowSystemApertureInSnapshots", fileloc.springboard.rawValue),
            ("SBExtendedDisplayOverrideSupportForAirPlayAndDontFileRadars", fileloc.springboard.rawValue),
            ("SBIconVisibility", fileloc.globalprefs.rawValue),
            ("SBSearchDisabledDomains", fileloc.globalprefs.rawValue),
            ("EnableWakeGestureHaptic", fileloc.coremotion.rawValue),
            ("PlaySoundOnPaste", fileloc.pasteboard.rawValue),
            ("AnnounceAllPastes", fileloc.pasteboard.rawValue),

            ("MetalForceHudEnabled", fileloc.globalprefs.rawValue),
            ("iMessageDiagnosticsEnabled", fileloc.globalprefs.rawValue),
            ("IDSDiagnosticsEnabled", fileloc.globalprefs.rawValue),
            ("VCDiagnosticsEnabled", fileloc.globalprefs.rawValue),
            ("AccessoryDeveloperEnabled", fileloc.globalprefs.rawValue),
            ("debugGestureEnabled", fileloc.appstore.rawValue),
            ("DebugModeEnabled", fileloc.notes.rawValue),
            ("BKDigitizerVisualizeTouches", fileloc.backboardd.rawValue)
        ]

        for (key, path) in tweaks {
            _ = mgr.setplistvalue(
                path: path,
                key: (key, nil),
                force: true
            )
        }

        loadnuggettweaks()
    }
}

#Preview {
    GestaltView(mgr: laramgr.shared)
}

func loadMutablePlistDictionary(from url: URL) throws -> NSMutableDictionary {
    let data = try Data(contentsOf: url)
    var format = PropertyListSerialization.PropertyListFormat.binary
    let plist = try PropertyListSerialization.propertyList(
        from: data,
        options: [.mutableContainersAndLeaves],
        format: &format
    )
    guard let dict = plist as? NSMutableDictionary else {
        throw "Property list root is not a dictionary."
    }
    return dict
}

func verifyPlist(_ plist: Any, targetPath: String) throws -> Data {
    let fm = FileManager.default
    
    if fm.fileExists(atPath: targetPath) {
        let attrs = try fm.attributesOfItem(atPath: targetPath)
        if let current = attrs[.size] as? NSNumber,
           current.intValue == 0 {
            Alertinator.shared.alert(
                title: "Dangerous Plist State Detected",
                body: "The current plist file is already 0 bytes. Overwriting has been aborted to prevent corruption."
            )
            throw "Current MobileGestalt file is 0 bytes."
        }
    }
    
    guard PropertyListSerialization.propertyList(plist, isValidFor: .binary) else {
        Alertinator.shared.alert(
            title: "Invalid Property List",
            body: "The plist is invalid and cannot be written safely."
        )
        throw "Invalid plist structure."
    }
    
    let data = try PropertyListSerialization.data(
        fromPropertyList: plist,
        format: .binary,
        options: 0
    )
    
    if data.isEmpty || data.count == 0 {
        Alertinator.shared.alert(
            title: "Refusing Empty Plist Write",
            body: "The generated plist would become 0 bytes after overwrite. Operation cancelled."
        )
        throw "Serialized plist data is empty."
    }
    
    do {
        _ = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
    } catch {
        Alertinator.shared.alert(
            title: "Invalid Serialized Property List",
            body: "The generated plist failed validation after serialization."
        )
        throw "Serialized plist validation failed."
    }
    
    return data
}
