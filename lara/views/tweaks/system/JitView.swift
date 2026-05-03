//
//  JitView.swift
//  lara
//
//  Created by ruter on 06.04.26.
//

import SwiftUI

struct proc: Identifiable {
    let id = UUID()
    let name: String
    let bundle: String
    let path: String
    let icon: UIImage?
}

struct JitView: View {
    @ObservedObject private var mgr = laramgr.shared
    @State private var query = ""
    @State private var allprocs: [proc] = []
    @State private var enablingbid: String? = nil

    private var filteredprocs: [proc] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return allprocs }

        let q = trimmed.lowercased()
        return allprocs.filter { process in
            process.name.lowercased().contains(q) || process.bundle.lowercased().contains(q)
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if !mgr.sbxready {
                    Section {
                        Text("Sandbox escape not ready. Run the sandbox escape first.")
                            .foregroundColor(.secondary)
                    } header: {
                        Text("Status")
                    }
                }

                HStack {
                    TextField("Search", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        loadprocs()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(!mgr.sbxready)
                }

                Section {
                    if filteredprocs.isEmpty {
                        Text(query.isEmpty ? "No apps found." : "No matches.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(filteredprocs) { proc in
                            HStack {
                                if let icon = proc.icon {
                                    Image(uiImage: icon)
                                        .resizable()
                                        .frame(width: 40, height: 40)
                                        .clipShape(RoundedRectangle(cornerRadius: 9))
                                } else {
                                    Image("unknown")
                                        .resizable()
                                        .frame(width: 40, height: 40)
                                        .clipShape(RoundedRectangle(cornerRadius: 9))
                                }

                                VStack(alignment: .leading) {
                                    Text(proc.name)
                                        .font(.headline)
                                    Text(proc.bundle)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }

                                Spacer()

                                Button {
                                    enablejit(bundleID: proc.bundle)
                                } label: {
                                    if enablingbid == proc.bundle {
                                        ProgressView()
                                    } else {
                                        Text("Enable")
                                    }
                                }
                                .disabled(enablingbid != nil || !mgr.dsready)
                            }
                        }
                    }
                } footer: {
                    Text("Only works on apps with the `get-task-allow` entitlement.")
                }
            }
            .navigationTitle("LaraJIT")
        }
        .onAppear {
            if mgr.sbxready {
                loadprocs()
            } else {
                allprocs.removeAll()
            }
        }
        .onChange(of: mgr.sbxready) { ready in
            if ready {
                loadprocs()
            } else {
                allprocs.removeAll()
            }
        }
    }

    func loadprocs() {
        guard mgr.sbxready else {
            DispatchQueue.main.async {
                allprocs.removeAll()
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var apps: [proc] = []
            let paths = ["/Applications", "/var/containers/Bundle/Application"]

            for path in paths {
                guard let items = try? FileManager.default.contentsOfDirectory(atPath: path) else { continue }

                for item in items {
                    let itempath = path + "/" + item
                    var isdir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: itempath, isDirectory: &isdir), isdir.boolValue {
                        if path == "/var/containers/Bundle/Application" {
                            guard let uuiditems = try? FileManager.default.contentsOfDirectory(atPath: itempath) else { continue }

                            for uuidItem in uuiditems {
                                let appbundlepath = itempath + "/" + uuidItem
                                if appbundlepath.hasSuffix(".app") {
                                    addapp(atPath: appbundlepath, to: &apps)
                                }
                            }
                        } else {
                            if itempath.hasSuffix(".app") {
                                addapp(atPath: itempath, to: &apps)
                            }
                        }
                    }
                }
            }

            apps.sort { $0.name.lowercased() < $1.name.lowercased() }

            DispatchQueue.main.async {
                allprocs = apps
            }
        }
    }

    private func enablejit(bundleID: String) {
        guard enablingbid == nil else { return }
        guard mgr.dsready else {
	            globallogger.log("kernel r/w not ready")
	            return
	        }

	        enablingbid = bundleID
	        globallogger.log("(jit) enabling for \(bundleID)...")

	        let runenable: () -> Void = {
				guard let sbProc = mgr.sbProc else {
					globallogger.log("(jit) error: sbProc is nil")
					DispatchQueue.main.async { enablingbid = nil }
					return
				}

				DispatchQueue.global(qos: .userInitiated).async {
					let err: Int32 = bundleID.withCString { (cStr: UnsafePointer<Int8>) -> Int32 in
						return enable_jit(sbProc, cStr)
					}

					DispatchQueue.main.async {
						if err == 0 {
							globallogger.log("(jit) enabled for \(bundleID)")
						} else {
							globallogger.log("(jit) error enabling for \(bundleID)!")
						}
						enablingbid = nil
					}
				}
			}

	        if mgr.rcrunning {
	            runenable()
	        } else {
	            mgr.rcinit(process: "SpringBoard", migbypass: false) { success in
	                if success {
	                    runenable()
	                } else {
	                    globallogger.log("(jit) rcinit failed")
	                    enablingbid = nil
	                }
	            }
        }
    }
        
    func addapp(atPath apppath: String, to apps: inout [proc]) {
        let infopath = apppath + "/Info.plist"
        var name = (apppath as NSString).lastPathComponent
        var bundle = "unknown"
        var icon: UIImage? = nil
        
        if let info = NSDictionary(contentsOfFile: infopath) {
            
            if let displayname = info["CFBundleDisplayName"] as? String {
                name = displayname
            } else if let bundlename = info["CFBundleName"] as? String {
                name = bundlename
            }
            
            if let bid = info["CFBundleIdentifier"] as? String {
                bundle = bid
            }
            
            if let icons = info["CFBundleIcons"] as? [String: Any],
               let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
               let iconfiles = primary["CFBundleIconFiles"] as? [String],
               let iconname = iconfiles.last {
                
                let iconpath = apppath + "/" + iconname
                
                if let image = UIImage(contentsOfFile: iconpath) {
                    icon = image
                } else if let image = UIImage(contentsOfFile: iconpath + "@2x.png") {
                    icon = image
                } else if let image = UIImage(contentsOfFile: iconpath + ".png") {
                    icon = image
                }
            }
        }
        
        let finalicon = icon ?? UIImage(named: "unknown")
        apps.append(proc(name: name, bundle: bundle, path: apppath, icon: finalicon))
    }
}
