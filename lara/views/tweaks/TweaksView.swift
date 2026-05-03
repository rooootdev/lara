//
//  TweaksView.swift
//  lara
//
//  Created by lunginspector on 5/3/26.
//

import SwiftUI
import PartyUI

struct TweaksView: View {
    @ObservedObject var mgr: laramgr
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: HeaderLabel(text: "SpringBoard", icon: "house")) {
                    NavigationLink("DarkBoard", destination: DarkBoardView())
                    NavigationLink("Liquid Glass", destination: LGView())
                    NavigationLink("RemoteCall Customizer", destination: RemoteView(mgr: mgr))
                        .disabled(!mgr.rcready)
                }
                
                Section(header: HeaderLabel(text: "User Interface", icon: "eye")) {
                    NavigationLink("dirtyZero", destination: ZeroView(mgr: mgr))
                        .disabled(!mgr.vfsready)
                    NavigationLink("MobileGestalt", destination: EditorView())
                        .disabled(!mgr.sbxready)
                    NavigationLink("Card Overwrite", destination: CardView())
                    NavigationLink("Font Overwrite", destination: FontPicker(mgr: mgr))
                        .disabled(!mgr.vfsready)
                    NavigationLink("Passcode Theme", destination: PasscodeView(mgr: mgr))
                        .disabled(!mgr.sbxready)
                }
                
                Section(header: HeaderLabel(text: "System", icon: "gear")) {
                    NavigationLink("3 App Bypass", destination: AppsView(mgr: mgr))
                        .disabled(!mgr.sbxready)
                    NavigationLink("Unblacklist", destination: WhitelistView())
                        .disabled(!mgr.sbxready)
                    NavigationLink("VarClean", destination: VarCleanView())
                        .disabled(!mgr.sbxready)
                    NavigationLink("JIT Enabler", destination: JitView())
                        .disabled(!mgr.sbxready)
                    NavigationLink("Custom Overwrite", destination: CustomView(mgr: mgr))
                        .disabled(!mgr.vfsready)
                }
                
                NavigationLink("Extra Tools", destination: ToolsView())
            }
            .navigationTitle("Tweaks")
            //.disabled(!mgr.sbxready || !mgr.vfsready || !mgr.rcready)
        }
    }
}
