//
//  LGView.swift
//  lara
//
//  Created by jurre111 on 24.04.26.
//

// Credits to leminlimez and Duy Tran for most of the code

import SwiftUI

struct LGView: View {
    @ObservedObject private var mgr = laramgr.shared
    @State private var gp: NSMutableDictionary
    @State private var status: String?
    @State private var valid: Bool = true
    
    private let path = "/var/Managed Preferences/mobile/.GlobalPreferences.plist"
    private let oggpurl: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        oggpurl = docs.appendingPathComponent("ogGlobalPreferences.plist")
        let sysurl = URL(fileURLWithPath: path)
        do {
            if !FileManager.default.fileExists(atPath: oggpurl.path) {
                try FileManager.default.copyItem(at: sysurl, to: oggpurl)
            }
            chmod(oggpurl.path, 0o644)
            
            _gp = State(initialValue: try NSMutableDictionary(contentsOf: URL(fileURLWithPath: path), error: ()))
        } catch {
            _gp = State(initialValue: [:])
            _status = State(initialValue: "Failed to copy GlobalPreferences: \(error)")
        }

    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Force Solarium Fallback", isOn: gpkeybinding("SolariumForceFallback"))
                    Toggle("Disable Liquid Glass", isOn: gpkeybinding("com.apple.SwiftUI.DisableSolarium"))
                    Toggle("Ignore Liquid Glass App Build Check", isOn: gpkeybinding("com.apple.SwiftUI.IgnoreSolariumLinkedOnCheck"))
                    Toggle("Disable Liquid Glass on LS Clock", isOn: gpkeybinding("SBDisallowGlassTime"))
                    Toggle("Disable Liquid Glass on Dock", isOn: gpkeybinding("SBDisableGlassDock"))
                    Toggle("Disable Specular Motion", isOn: gpkeybinding("SBDisableSpecularEverywhereUsingLSSAssertion"))
                    Toggle("Disable Outer Refraction", isOn: gpkeybinding("SolariumDisableOuterRefraction"))
                    Toggle("Disable Solarium HDR", isOn: gpkeybinding("SolariumAllowHDR", default: true, enable: false))
                } header: {
                    Text("Liquid Glass")
                } footer: {
                    Text("Note: some tweaks may not work or cause instability.")
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
                        Text("Refresh plist")
                    }
                    Button() {
                        apply()
                    } label: {
                        Text("Apply")
                    }
                    .disabled(!valid)
                } header: {
                    Text("Actions")
                } footer: {
                    Text("Use at your own risk. Always keep a backup of \"/var/Managed Preferences/mobile/.GlobalPreferences.plist\" somewhere safe.")
                }
            }
            .navigationTitle("Liquid Glass")
            .alert("Status", isPresented: .constant(status != nil)) {
                Button("OK") { status = nil }
            } message: {
                Text(status ?? "")
            }
            .onAppear(perform: load)
        }
    }
    
    private func validate(_ dict: NSMutableDictionary) -> Bool {
        return !dict.allKeys.isEmpty
    }

    private func load() {
        do {
            gp = try NSMutableDictionary(contentsOf: URL(fileURLWithPath: path), error: ())
        } catch {
            status = "Failed to load GlobalPreferences"
        }

        valid = validate(gp)
    }

    private func apply() {
        if !validate(gp) {
            status = "Plist is invalid."
            return
        }
        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: gp,
                format: .binary,
                options: 0
            )
            
            let result = laramgr.shared.lara_overwritefile(
                target: path,
                data: data
            )
            if result.ok {
                load()
                if valid {
                    mgr.logmsg("overwrote GlobalPreferences.plist at \(path)")
                    status = "Applied plist, reboot to see changes."
                } else {
                    status = "Applied plist but it's invalid. Don't respring and copy backup (lara/Documents/ogGlobalPreferences.plist) to orignal location."
                }
            } else {
                status = "overwrite failed: \(result.message)"
            }
            
        } catch {
            status = "serialization failed: \(error.localizedDescription)"
        }
    }
    
    private func gpkeybinding<T: Equatable>(_ key: String, type: T.Type = Bool.self, default: T? = false, enable: T? = true) -> Binding<Bool> {
        return Binding(
            get: {
                if let value = gp[key] as? T?, let enable {
                    return value == enable
                }
                return false
            },
            set: { enabled in
                if enabled {
                    gp[key] = enable
                } else {
                    gp.removeObject(forKey: key)
                }
                
                valid = validate(gp)
            }
        )
    }
}
