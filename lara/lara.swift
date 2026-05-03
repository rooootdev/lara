//
//  lara.swift
//  lara
//
//  Created by ruter on 23.03.26.
//

import SwiftUI
import UniformTypeIdentifiers

let g_isunsupported: Bool = isunsupported()

extension UIDocumentPickerViewController {
    @objc func fix_init(forOpeningContentTypes contentTypes: [UTType], asCopy: Bool) -> UIDocumentPickerViewController {
        return fix_init(forOpeningContentTypes: contentTypes, asCopy: true)
    }
}

@main
struct lara: App {
    @ObservedObject private var mgr = laramgr.shared
    @Environment(\.scenePhase) private var scenePhase
    @State var showunsupported: Bool = false
    @State private var selectedtab: Int = 0
    private let keepalivekey = "keepalive"
    @AppStorage("showfmintabs") private var showfmintabs: Bool = true
    @AppStorage("selectedmethod") private var selectedmethod: method = .hybrid

    init() {
        // fix file picker
        let fixMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.fix_init(forOpeningContentTypes:asCopy:)))!
        let origMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.init(forOpeningContentTypes:asCopy:)))!
        method_exchangeImplementations(origMethod, fixMethod)
        
        if UserDefaults.standard.string(forKey: "selectedmethod") == nil {
            UserDefaults.standard.set(method.sbx.rawValue, forKey: "selectedmethod")
        }
        
        if g_isunsupported {
            showunsupported = true
        }
        
        if UserDefaults.standard.bool(forKey: keepalivekey) {
            if !kaenabled {
                toggleka()
            }
        }
        
        if g_isunsupported {
            print("device may be unsupported")
        } else {
            print("device should be supported")
        }
        
        globallogger.capture()
    }

    // i want to figure out a way to have the logs button be in some permanant toolbar type situation. i haven't figured it out yet though.
    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedtab) {
                /*
                SantanderView(startPath: "/")
                    .tabItem {
                        Image(systemName: "folder.fill")
                    }
                    .tag(0)
                
                ContentView()
                    .tabItem {
                        Image(systemName: "ant.fill")
                    }
                    .tag(1)
                
                LogsView(logger: globallogger)
                    .tabItem {
                        Image(systemName: "doc.text.fill")
                    }
                    .tag(2)
                */
                ContentView()
                    .tabItem {
                        Image(systemName: "wrench.and.screwdriver.fill")
                    }
                    .tag(0)
                
                TweaksView(mgr: mgr)
                    .tabItem {
                        Image(systemName: "ant.fill")
                    }
                    .tag(1)
                
                SantanderView(startPath: "/")
                    .tabItem {
                        Image(systemName: "folder.fill")
                    }
                    .tag(2)
            }
            .sheet(isPresented: $mgr.showLogs) {
                LogsView(logger: globallogger)
            }
            .onAppear {
                if g_isunsupported {
                    showunsupported = true
                }
                
                init_offsets()
                offsets_init()
            }
            .onChange(of: scenePhase) { phase in
                if phase == .inactive || phase == .background {
                    if mgr.rcready {
                        var bgTask: UIBackgroundTaskIdentifier = .invalid
                        bgTask = UIApplication.shared.beginBackgroundTask(withName: "RemoteCallCleanup") {
                            if bgTask != .invalid {
                                UIApplication.shared.endBackgroundTask(bgTask)
                                bgTask = .invalid
                            }
                        }
                        
                        mgr.rcdestroy {
                            if bgTask != .invalid {
                                UIApplication.shared.endBackgroundTask(bgTask)
                                bgTask = .invalid
                            }
                        }
                    }
                    
                    globallogger.stopcapture()
                } else if phase == .active {
                    globallogger.capture()
                }
            }
            .alert(isPresented: $showunsupported) {
                .init(title: Text("Unsupported"), message: Text("Lara is currently not supported on this device. Possible reasons:\nYour device is newer than iOS 26.0.1\nYour device is older than iOS 17.0\nYour device has MIE\n\nLara will probably not work."))
            }
        }
    }
}
