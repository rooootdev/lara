//
//  EditorView.swift
//  lara
//
//  Created by ruter on 27.03.26.
//

// Most of the code is from Duy's SparseBox
// thank you @jurre111

import SwiftUI

struct EditorView: View {
    @ObservedObject private var mgr = laramgr.shared
    @State private var mg: NSMutableDictionary
    @State private var status: String?
    @State private var alert: String?
    @State private var valid: Bool = true
    @AppStorage("ogSubType") private var ogSubType: Int = -1
    @State private var selectedSubType: Int = -1
    
    private let path = "/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
    private let ogmgurl: URL
    let os = ProcessInfo().operatingSystemVersion
    var subtypes = [2556, 2796, 2976, 2622, 2868, 2436]
    var subtypeNames = [2556: "14 Pro (2556)", 2796: "14 Pro Max (2796)", 2976: "15 Pro Max (2976)", 2622: "16 Pro (2622)", 2868: "16 Pro Max (2868)", 2436: "X Gestures (2436)"]
    var subtypeDisabled: [Int: Bool] = [:]

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        ogmgurl = docs.appendingPathComponent("ogmobilegestalt.plist")
        let sysurl = URL(fileURLWithPath: path)
        do {
            if !FileManager.default.fileExists(atPath: ogmgurl.path) {
                try FileManager.default.copyItem(at: sysurl, to: ogmgurl)
            }
            chmod(ogmgurl.path, 0o644)
            
            _mg = State(initialValue: try NSMutableDictionary(contentsOf: URL(fileURLWithPath: path), error: ()))
        } catch {
            _mg = State(initialValue: [:])
            _status = State(initialValue: "Failed to copy MobileGestalt: \(error)")
        }
        guard let cacheExtra = mg["CacheExtra"] as? NSMutableDictionary, let oPeik = cacheExtra["oPeik/9e8lQWMszEjbPzng"] as? NSMutableDictionary else {
            _status = State(initialValue: "Failed to get dictionaries from MobileGestalt. Reopen the page.")
            return
        }
        guard let subType = oPeik["ArtworkDeviceSubType"] as? Int else {
            _status = State(initialValue: "Failed to get SubType from MobileGestalt. Reopen the page.")
            return
        }
        _selectedSubType = State(initialValue: subType)
        // This only happens on the first load
        if ogSubType == -1 {
            ogSubType = subType
        }
        let originalSubType = ogSubType
        subtypes.removeAll { $0 == originalSubType }
        subtypeDisabled = [2556: requiresVersion(16), 2796: requiresVersion(16), 2976: requiresVersion(17), 2622: requiresVersion(18), 2868: requiresVersion(18), 2436: !UIDevice._hasHomeButton()]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Dynamic Island")
                        Spacer()
                        Menu {
                            Button("Original (\(String(ogSubType)))") { selectedSubType = ogSubType }
                            ForEach(subtypes, id: \.self) { subtype in
                                Button(subtypeNames[subtype] ?? "??") { selectedSubType = subtype }
                                    .disabled(subtypeDisabled[subtype] ?? true)
                            }
                        } label: {
                            Text(selectedSubType == ogSubType ? "Original (\(String(selectedSubType)))" :  (subtypeNames[selectedSubType] ?? "Unknown (\(String(selectedSubType)))"))
                        }
                    }
                    Toggle("Action Button", isOn: mgkeybinding(["cT44WE1EohiwRzhsZ8xEsw"]))
                        .disabled(requiresVersion(17))
                    Toggle("Allow installing iPadOS apps", isOn: mgkeybinding(["9MZ5AdH43csAUajl/dU+IQ"], type: [Int].self, default: [1], enable: [1, 2]))
                    Toggle("Always on Display (18.0+)", isOn: mgkeybinding(["j8/Omm6s1lsmTDFsXjsBfA", "2OOJf1VhaM7NxfRok3HbWQ"]))
                        .disabled(requiresVersion(18))
                    // Toggle("Apple Intelligence", isOn: bindingForAppleIntelligence())
                    //    .disabled(requiresVersion(18))
                    Toggle("Apple Pencil", isOn: mgkeybinding(["yhHcB0iH0d1XzPO/CFd3ow"]))
                    Toggle("Boot chime", isOn: mgkeybinding(["QHxt+hGLaBPbQJbXiUJX3w"]))
                    Toggle("Camera button (18.0rc+)", isOn: mgkeybinding(["CwvKxM2cEogD3p+HYgaW0Q", "oOV1jhJbdV3AddkcCg0AEA"]))
                        .disabled(requiresVersion(18))
                    Toggle("Charge limit (17+)", isOn: mgkeybinding(["37NVydb//GP/GrhuTN+exg"]))
                    .   disabled(requiresVersion(17))
                    Toggle("Crash Detection (might not work)", isOn: mgkeybinding(["HCzWusHQwZDea6nNhaKndw"]))
                    // Toggle("Dynamic Island (17.4+, might not work)", isOn: mgkeybinding(["YlEtTtHlNesRBMal1CqRaA"]))
                    // Toggle("Disable region restrictions", isOn: bindingForRegionRestriction())
                    Toggle("Internal Storage info", isOn: mgkeybinding(["LBJfwOEzExRxzlAnSuI7eg"]))
                    // Toggle("Internal stuff", isOn: bindingForInternalStuff())
                    Toggle("Security Research Device", isOn: mgkeybinding(["XYlJKKkj2hztRP1NWWnhlw"]))
                    Toggle("Metal HUD for all apps", isOn: mgkeybinding(["EqrsVvjcYDdxHBiQmGhAWw"]))
                    Toggle("Stage Manager", isOn: mgkeybinding(["qeaj75wk3HF4DwQ8qbIi7g"]))
                        .disabled(UIDevice.current.userInterfaceIdiom != .pad)
                    if UIDevice._hasHomeButton() {
                        Toggle("Tap to Wake (iPhone SE)", isOn: mgkeybinding(["yZf3GTRMGTuwSV/lD7Cagw"]))
                    }
                } header: {
                    Text("MobileGestalt")
                } footer: {
                    Text("Note: some tweaks may not work or cause instability.")
                }
                Section {
                    let cacheExtra = mg["CacheExtra"] as? NSMutableDictionary
                    Toggle("Become iPadOS", isOn: bindingForTrollPad())
                    // validate DeviceClass
                        .disabled(cacheExtra?["+3Uf0Pm5F8Xy7Onyvko0vA"] as? String != "iPhone")
                } footer: {
                    Text("Override user interface idiom to iPadOS, so you could use all iPadOS multitasking features on iPhone. Gives you the same capabilities as TrollPad, but may cause some issues.\nPLEASE DO NOT TURN OFF SHOW DOCK IN STAGE MANAGER OTHERWISE YOUR PHONE WILL BOOTLOOP WHEN ROTATING TO LANDSCAPE.")
                }
                Section {
                    HStack {
                        Text("Status")
                        
                        Spacer()
                        
                        if valid {
                            Text("valid!")
                                .monospaced(true)
                                .foregroundColor(.green)
                        } else {
                            Text("invalid.")
                                .monospaced(true)
                                .foregroundColor(.red)
                        }
                    }
                    Button() {
                        load()
                    } label: {
                        Text("Reload from plist")
                    }
                    Button() {
                        apply()
                    } label: {
                        Text("Apply Modified MobileGestalt")
                    }
                    .disabled(!valid)
                } header: {
                    Text("Apply")
                } footer: {
                    Text("Use at your own risk. Always keep a backup of your MobileGestalt somewhere safe.")
                }
                
                HStack(alignment: .top) {
                    AsyncImage(url: URL(string: "https://github.com/jurre111.png")) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    
                    VStack(alignment: .leading) {
                        Text("Jurre")
                            .font(.headline)
                        
                        Text("The entire EditorView.")
                            .font(.subheadline)
                            .foregroundColor(Color.secondary)
                    }
                    
                    Spacer()
                }
                .onTapGesture {
                    if let url = URL(string: "https://github.com/jurre111"),
                       UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url)
                    }
                }
            }
            .navigationTitle("MobileGestalt")
            .alert("Status", isPresented: .constant(status != nil)) {
                Button("OK") { status = nil }
            } message: {
                Text(status ?? "")
            }
            .alert("Done", isPresented: .constant(alert != nil)) {
                Button("Cancel") { alert = nil }
                Button("Respring") {
                    alert = nil
                    mgr.respring()
                }
            } message: {
                Text(alert ?? "uhh...")
            }
            .onAppear(perform: load)
        }
    }
    
    private func validate(_ dict: NSMutableDictionary) -> Bool {
        guard let cacheExtra = dict["CacheExtra"] as? NSMutableDictionary else { return false }
        return !cacheExtra.allKeys.isEmpty
    }

    private func load() {
        do {
            mg = try NSMutableDictionary(contentsOf: URL(fileURLWithPath: path), error: ())
        } catch {
            status = "Failed to load mobilegestalt"
        }
    }

    private func apply() {
        do {
            if selectedSubType != -1 {
                guard let cacheExtra = mg["CacheExtra"] as? NSMutableDictionary, let oPeik = cacheExtra["oPeik/9e8lQWMszEjbPzng"] as? NSMutableDictionary else {
                    status = "Failed to get dictionaries from MobileGestalt."
                    return
                }
                oPeik["ArtworkDeviceSubType"] = selectedSubType
            } else {
                status = "Selected SubType is -1? Reload the page."
                return
            }
            let data = try PropertyListSerialization.data(
                fromPropertyList: mg,
                format: .binary,
                options: 0
            )
            
            let result = laramgr.shared.lara_overwritefile(
                target: path,
                data: data
            )
            
            if result.ok {
                mgr.logmsg("overwrote MobileGestalt at \(path)")
                alert = "Applied modified mobilegestalt, respring to see changes."
            } else {
                status = "overwrite failed: \(result.message)"
            }
            
        } catch {
            status = "serialization failed: \(error.localizedDescription)"
        }
    }
    private func bindingForTrollPad() -> Binding<Bool> {
        // We're going to overwrite DeviceClassNumber but we can't do it via CacheExtra, so we need to do it via CacheData instead
        guard let cacheData = mg["CacheData"] as? NSMutableData,
              let cacheExtra = mg["CacheExtra"] as? NSMutableDictionary else {
            return State(initialValue: false).projectedValue
        }
        let valueOffset = FindCacheDataOffset("mtrAoWJ3gsq+I90ZnQ0vQw")
        //print("Read value from \(cacheData.mutableBytes.load(fromByteOffset: valueOffset, as: Int.self))")
        
        let keys = [
            "uKc7FPnEO++lVhHWHFlGbQ", // ipad
            "mG0AnH/Vy1veoqoLRAIgTA", // MedusaFloatingLiveAppCapability
            "UCG5MkVahJxG1YULbbd5Bg", // MedusaOverlayAppCapability
            "ZYqko/XM5zD3XBfN5RmaXA", // MedusaPinnedAppCapability
            "nVh/gwNpy7Jv1NOk00CMrw", // MedusaPIPCapability,
            "qeaj75wk3HF4DwQ8qbIi7g", // DeviceSupportsEnhancedMultitasking
        ]
        return Binding(
            get: {
                if let value = cacheExtra[keys.first!] as? Int? {
                    return value == 1
                }
                return false
            },
            set: { enabled in
                if enabled {
                    status = "Become iPadOS is a risky feature so please take note of the following:\n\n1. iOS Only apps, like WhatsApp, can lose data. It's recommended to offload these apps.\n2. The homescreen layout can get fucked if you have empty space.\n3. If you have an alphabetical password, it's very hard to get into your phone after locking.\n4. Any option with Dock under Stage Manager should NOT be modified.\n\n Only continue if you're okay with this. Else click reload from plist"
                }
                cacheData.mutableBytes.storeBytes(of: enabled ? 3 : 1, toByteOffset: valueOffset, as: Int.self)
                for key in keys {
                    if enabled {
                        cacheExtra[key] = 1
                    } else {
                        // just remove the key as it will be pulled from device tree if missing
                        cacheExtra.removeObject(forKey: key)
                    }
                }
                
                valid = validate(mg)
            }
        )
    }

    private func mgkeybinding<T: Equatable>(_ keys: [String], type: T.Type = Int.self, default: T? = 0, enable: T? = 1) -> Binding<Bool> {
        guard let cachextra = mg["CacheExtra"] as? NSMutableDictionary else {
            return State(initialValue: false).projectedValue
        }
        
        return Binding(
            get: {
                if let value = cachextra[keys.first!] as? T?, let enable {
                    return value == enable
                }
                return false
            },
            set: { enabled in
                for key in keys {
                    if enabled {
                        cachextra[key] = enable
                    } else {
                        cachextra.removeObject(forKey: key)
                    }
                }
                
                valid = validate(mg)
            }
        )
    }

    private func requiresVersion(_ major : Int, _ minor: Int = 0, _ patch: Int = 0) -> Bool {
        // XXYYZZ: major XX, minor YY, patch ZZ
        let requiredVersion = major*10000 + minor*100 + patch
        let currentVersion = os.majorVersion*10000 + os.minorVersion*100 + os.patchVersion
        return currentVersion < requiredVersion
    }
}
