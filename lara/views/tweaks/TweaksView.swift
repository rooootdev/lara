//
//  TweaksView.swift
//  lara
//
//  Created by lunginspector on 5/3/26.
//

import SwiftUI

struct TweaksView: View {
    @AppStorage("logsdisplaymode") private var selectedlogsdisplaymode: logsdisplaymode = .toolbar
    @ObservedObject var mgr: laramgr
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: HeaderLabel(text: "SpringBoard", icon: "house")) {
                    NavigationLink("RemoteCall Customizer", destination: RemoteView(mgr: mgr))
                        .disabled(!mgr.rcready)
                    NavigationLink("Liquid Glass", destination: LiquidGlassView())
                        .disabled(!mgr.vfsready)
                    NavigationLink("SpringBoard Customizer", destination: SpringBoardView(mgr: mgr))
                        .disabled(!mgr.vfsready)
                }
                
                Section(header: HeaderLabel(text: "Lock Screen", icon: "lock")) {
                    NavigationLink("Passcode Theme", destination: PasscodeView(mgr: mgr))
                        .disabled(!mgr.sbxready)
                }
                
                Section(header: HeaderLabel(text: "Apps", icon: "app")) {
                    NavigationLink("Card Overwrite", destination: CardView())
                        .disabled(!mgr.vfsready)
                    NavigationLink("App Decrypt", destination: DecryptView())
                        .disabled(!mgr.sbxready)
                    NavigationLink("3 App Bypass", destination: AppsView())
                        .disabled(!mgr.sbxready)
                    NavigationLink("Unblacklist", destination: WhitelistView())
                        .disabled(!mgr.sbxready)
                    NavigationLink("JIT Enabler", destination: JitView())
                        .disabled(!mgr.sbxready)
                }
                
                Section(header: HeaderLabel(text: "User Interface", icon: "eye")) {
                    NavigationLink("dirtyZero", destination: dirtyZeroView())
                        .disabled(!mgr.vfsready)
                    NavigationLink("MobileGestalt", destination: GestaltView(mgr: mgr))
                        .disabled(!mgr.sbxready)
                    NavigationLink("Font Overwrite", destination: FontPicker(mgr: mgr))
                        .disabled(!mgr.vfsready)
                    NavigationLink("SystemColor Patcher", destination: SystemColor(mgr: mgr))
                        .disabled(!mgr.sbxready || !mgr.vfsready)
                }
                
                Section(header: HeaderLabel(text: "System", icon: "gear")) {
                    NavigationLink("VarClean", destination: VarCleanView())
                        .disabled(!mgr.sbxready)
                    NavigationLink("Custom Overwrite", destination: CustomView(mgr: mgr))
                        .disabled(!mgr.vfsready)
                }
                
                Section(header: HeaderLabel(text: "Broken", icon: "exclamationmark.triangle.fill")) {
                    NavigationLink("DarkBoard", destination: DarkBoardView())
                        .disabled(true)
                }
                
                NavigationLink("Extra Tools", destination: ToolsView())
            }
            .disabled(!mgr.dsready)
            .navigationTitle("Tweaks")
            .toolbar {
                if selectedlogsdisplaymode == .toolbar {
                    Button(action: {
                        mgr.showLogs.toggle()
                    }) {
                        Image(systemName: "terminal")
                    }
                }
            }
        }
    }
}
