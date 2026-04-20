//
//  SettingsView.swift
//  lara
//
//  Created by ruter on 29.03.26.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var mgr: laramgr
    @Binding var hasoffsets: Bool
    @State private var showresetalert: Bool = false
    @State private var downloadingkernelcache = false
    @State private var showkcacheimporter: Bool = false
    @State private var importingkernelcache: Bool = false
    @State private var showkcachetips: Bool = false
    @State private var statusmsg: String?
    @AppStorage("loggernobullshit") private var loggernobullshit: Bool = true
    @AppStorage("keepalive") private var iskeepalive: Bool = true
    @AppStorage("showfmintabs") private var showfmintabs: Bool = true
    @AppStorage("selectedmethod") private var selectedmethod: method = .hybrid
    @AppStorage("rcdockunlimited") private var rcdockunlimited: Bool = false
    @AppStorage("stashkrw") private var stashkrw: Bool = false
    
    var appname: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "Unknown App"
    }
    var appversion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
    var appicon: UIImage {
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let last = files.last,
           let image = UIImage(named: last) {
            return image
        }
        
        return UIImage(named: "unknown") ?? UIImage()
    }
    private var t1szbootbind: Binding<String> {
        Binding(
            get: {
                String(format: "0x%llx", t1sz_boot)
            },
            set: { newval in
                let cleaned = newval
                    .replacingOccurrences(of: "0x", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if let value = UInt64(cleaned, radix: 16) {
                    t1sz_boot = value
                    UserDefaults.standard.set(value, forKey: "lara.t1sz_boot")
                    UserDefaults.standard.synchronize()
                }
            }
        )
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(uiImage: appicon)
                            .resizable()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        VStack(alignment: .leading) {
                            Text(appname)
                                .font(.headline)
                            
                            Text("Version \(appversion)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Lara")
                }
                
                Section {
                    Picker("", selection: $selectedmethod) {
                        ForEach(method.allCases, id: \.self) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Method")
                } footer: {
                    if selectedmethod == .vfs {
                        Text("VFS only.")
                    } else if selectedmethod == .sbx {
                        Text("SBX only.")
                    } else {
                        Text("Hybrid: SBX for read, VFS for write.\nBest method ever. (Thanks Huy)")
                    }
                }
                
                Section {
                    Toggle("Disable log dividers", isOn: $loggernobullshit)
                        .onChange(of: loggernobullshit) { _ in
                            globallogger.clear()
                        }
                    
                    Toggle("Keep Alive", isOn: $iskeepalive)
                        .onChange(of: iskeepalive) { _ in
                            if iskeepalive {
                                if !kaenabled { toggleka() }
                            } else {
                                if kaenabled { toggleka() }
                            }
                        }
                    
                    Toggle("Show File Manager in Tabs", isOn: $showfmintabs)

                } header: {
                    Text("Lara Settings")
                } footer: {
                    Text("Keep Alive keeps the app running in the background when it is minimized (not closed from app switcher).")
                }

                #if !DISABLE_REMOTECALL
                Section {
                    Toggle("Stash KRW primitives", isOn: $stashkrw)
                    Toggle("Allow >10 dock icons", isOn: $rcdockunlimited)
                } header: {
                    Text("RemoteCall")
                }
                #endif

                Section {
                    if !hasoffsets {
                        Button("Download Kernelcache") {
                            guard !downloadingkernelcache else { return }
                            downloadingkernelcache = true
                            DispatchQueue.global(qos: .userInitiated).async {
                                let ok = dlkerncache()
                                DispatchQueue.main.async {
                                    hasoffsets = ok
                                    downloadingkernelcache = false
                                }
                            }
                        }
                        .disabled(downloadingkernelcache)
                        
                        Button("Fetch Kernelcache") {
                            mgr.run()
                        }
                        
                        HStack {
                            Button("Import Kernelcache from Files") {
                                guard !importingkernelcache else { return }
                                showkcacheimporter = true
                            }
                            .disabled(importingkernelcache)
                            
                            Spacer()
                            
                            Button {
                                showkcachetips.toggle()
                            } label: {
                                Image(systemName: "lightbulb.max.fill")
                            }
                        }
                    }
                    
                    Button {
                        showresetalert = true
                    } label: {
                        Text("Delete Kernelcache Data")
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("Kernelcache")
                } footer: {
                    if !showkcachetips {
                        Text("Deleting and redownloading Kernelcache can fix a lot of issues. Try this before making a github Issue.")
                    }
                }
                
                if showkcachetips {
                    Section {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("How to obtain a kernelcache (macOS)")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.primary)
                            
                            Text("1. Download the IPSW tool for your device.")
                            Link("https://github.com/blacktop/ipsw/releases",
                                 destination: URL(string: "https://github.com/blacktop/ipsw/releases")!)
                            
                            Text("2. Extract the archive.")
                            Text("3. Open Terminal.")
                            Text("4. Navigate to the extracted folder:")
                            Text("cd /path/to/ipsw_3.1.671_something_something/")
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundColor(.primary)
                            
                            Text("5. Extract the kernel:")
                            Text("./ipsw extract --kernel [drag your ipsw here]")
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundColor(.primary)
                            
                            Text("6. Get the kernelcache file.")
                            Text("7. Transfer the kernelcache to your iCloud or iPhone.")
                            Text("8. Tap the button above and select the kernelcache, for example kernelcache.release.iPhone14,3.")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                    } footer: {
                        Text("Deleting and redownloading Kernelcache can fix a lot of issues. Try this before making a github Issue.")
                    }
                }
                
                if isdebugged() {
                    Section {
                        Button {
                            exit(0)
                        } label: {
                            Text("Detach")
                        }
                        .foregroundColor(.red)
                    } header: {
                        Text("Debugger")
                    } footer: {
                        Text("Lara does not work when a debugger is attached.")
                    }
                }
                
                Section {
                    HStack { Text("off_inpcb_inp_list_le_next"); Spacer(); Text(hex(UInt64(off_inpcb_inp_list_le_next))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_inpcb_inp_pcbinfo"); Spacer(); Text(hex(UInt64(off_inpcb_inp_pcbinfo))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_inpcb_inp_socket"); Spacer(); Text(hex(UInt64(off_inpcb_inp_socket))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_inpcbinfo_ipi_zone"); Spacer(); Text(hex(UInt64(off_inpcbinfo_ipi_zone))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_inpcb_inp_depend6_inp6_icmp6filt"); Spacer(); Text(hex(UInt64(off_inpcb_inp_depend6_inp6_icmp6filt))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_inpcb_inp_depend6_inp6_chksum"); Spacer(); Text(hex(UInt64(off_inpcb_inp_depend6_inp6_chksum))).foregroundColor(.secondary).monospaced() }
                    
                    HStack { Text("off_socket_so_usecount"); Spacer(); Text(hex(UInt64(off_socket_so_usecount))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_socket_so_proto"); Spacer(); Text(hex(UInt64(off_socket_so_proto))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_socket_so_background_thread"); Spacer(); Text(hex(UInt64(off_socket_so_background_thread))).foregroundColor(.secondary).monospaced() }
                    
                    HStack { Text("off_kalloc_type_view_kt_zv_zv_name"); Spacer(); Text(hex(UInt64(off_kalloc_type_view_kt_zv_zv_name))).foregroundColor(.secondary).monospaced() }
                    
                    HStack { Text("off_thread_t_tro"); Spacer(); Text(hex(UInt64(off_thread_t_tro))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_thread_ro_tro_proc"); Spacer(); Text(hex(UInt64(off_thread_ro_tro_proc))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_thread_ro_tro_task"); Spacer(); Text(hex(UInt64(off_thread_ro_tro_task))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_thread_machine_upcb"); Spacer(); Text(hex(UInt64(off_thread_machine_upcb))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_thread_machine_contextdata"); Spacer(); Text(hex(UInt64(off_thread_machine_contextdata))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_thread_ctid"); Spacer(); Text(hex(UInt64(off_thread_ctid))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_thread_options"); Spacer(); Text(hex(UInt64(off_thread_options))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_thread_mutex_lck_mtx_data"); Spacer(); Text(hex(UInt64(off_thread_mutex_lck_mtx_data))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_thread_machine_kstackptr"); Spacer(); Text(hex(UInt64(off_thread_machine_kstackptr))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_thread_guard_exc_info_code"); Spacer(); Text(hex(UInt64(off_thread_guard_exc_info_code))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_thread_mach_exc_info_code"); Spacer(); Text(hex(UInt64(off_thread_mach_exc_info_code))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_thread_mach_exc_info_os_reason"); Spacer(); Text(hex(UInt64(off_thread_mach_exc_info_os_reason))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_thread_mach_exc_info_exception_type"); Spacer(); Text(hex(UInt64(off_thread_mach_exc_info_exception_type))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_thread_ast"); Spacer(); Text(hex(UInt64(off_thread_ast))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_thread_task_threads_next"); Spacer(); Text(hex(UInt64(off_thread_task_threads_next))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_thread_machine_jop_pid"); Spacer(); Text(hex(UInt64(off_thread_machine_jop_pid))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_thread_machine_rop_pid"); Spacer(); Text(hex(UInt64(off_thread_machine_rop_pid))).foregroundColor(.secondary).monospaced() }
                    
                    HStack { Text("off_proc_p_list_le_next"); Spacer(); Text(hex(UInt64(off_proc_p_list_le_next))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_proc_p_list_le_prev"); Spacer(); Text(hex(UInt64(off_proc_p_list_le_prev))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_proc_p_proc_ro"); Spacer(); Text(hex(UInt64(off_proc_p_proc_ro))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_proc_p_pid"); Spacer(); Text(hex(UInt64(off_proc_p_pid))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_proc_p_fd"); Spacer(); Text(hex(UInt64(off_proc_p_fd))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_proc_p_flag"); Spacer(); Text(hex(UInt64(off_proc_p_flag))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_proc_p_textvp"); Spacer(); Text(hex(UInt64(off_proc_p_textvp))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_proc_p_name"); Spacer(); Text(hex(UInt64(off_proc_p_name))).foregroundColor(.secondary).monospaced() }
                    
                    HStack { Text("off_proc_ro_pr_task"); Spacer(); Text(hex(UInt64(off_proc_ro_pr_task))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_proc_ro_p_ucred"); Spacer(); Text(hex(UInt64(off_proc_ro_p_ucred))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_ucred_cr_label"); Spacer(); Text(hex(UInt64(off_ucred_cr_label))).foregroundColor(.secondary).monospaced() }
                    
                    HStack { Text("off_task_itk_space"); Spacer(); Text(hex(UInt64(off_task_itk_space))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_task_threads_next"); Spacer(); Text(hex(UInt64(off_task_threads_next))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_task_task_exc_guard"); Spacer(); Text(hex(UInt64(off_task_task_exc_guard))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_task_map"); Spacer(); Text(hex(UInt64(off_task_map))).foregroundColor(.secondary).monospaced() }
                    
                    HStack { Text("off_filedesc_fd_ofiles"); Spacer(); Text(hex(UInt64(off_filedesc_fd_ofiles))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_filedesc_fd_cdir"); Spacer(); Text(hex(UInt64(off_filedesc_fd_cdir))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_fileproc_fp_glob"); Spacer(); Text(hex(UInt64(off_fileproc_fp_glob))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_fileglob_fg_data"); Spacer(); Text(hex(UInt64(off_fileglob_fg_data))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_fileglob_fg_flag"); Spacer(); Text(hex(UInt64(off_fileglob_fg_flag))).foregroundColor(.secondary).monospaced() }
                    
                    HStack { Text("off_vnode_v_ncchildren_tqh_first"); Spacer(); Text(hex(UInt64(off_vnode_v_ncchildren_tqh_first))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_vnode_v_nclinks_lh_first"); Spacer(); Text(hex(UInt64(off_vnode_v_nclinks_lh_first))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_vnode_v_parent"); Spacer(); Text(hex(UInt64(off_vnode_v_parent))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_vnode_v_data"); Spacer(); Text(hex(UInt64(off_vnode_v_data))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_vnode_v_name"); Spacer(); Text(hex(UInt64(off_vnode_v_name))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_vnode_v_usecount"); Spacer(); Text(hex(UInt64(off_vnode_v_usecount))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_vnode_v_iocount"); Spacer(); Text(hex(UInt64(off_vnode_v_iocount))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_vnode_v_writecount"); Spacer(); Text(hex(UInt64(off_vnode_v_writecount))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_vnode_v_flag"); Spacer(); Text(hex(UInt64(off_vnode_v_flag))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_vnode_v_mount"); Spacer(); Text(hex(UInt64(off_vnode_v_mount))).foregroundColor(.secondary).monospaced() }
                    
                    HStack { Text("off_mount_mnt_flag"); Spacer(); Text(hex(UInt64(off_mount_mnt_flag))).foregroundColor(.secondary).monospaced() }
                    
                    HStack { Text("off_namecache_nc_vp"); Spacer(); Text(hex(UInt64(off_namecache_nc_vp))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_namecache_nc_child_tqe_next"); Spacer(); Text(hex(UInt64(off_namecache_nc_child_tqe_next))).foregroundColor(.secondary).monospaced() }
                    
                    HStack { Text("off_arm_saved_state64_lr"); Spacer(); Text(hex(UInt64(off_arm_saved_state64_lr))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_arm_saved_state64_pc"); Spacer(); Text(hex(UInt64(off_arm_saved_state64_pc))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_arm_saved_state_uss_ss_64"); Spacer(); Text(hex(UInt64(off_arm_saved_state_uss_ss_64))).foregroundColor(.secondary).monospaced() }
                    
                    HStack { Text("off_ipc_space_is_table"); Spacer(); Text(hex(UInt64(off_ipc_space_is_table))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_ipc_entry_ie_object"); Spacer(); Text(hex(UInt64(off_ipc_entry_ie_object))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_ipc_port_ip_kobject"); Spacer(); Text(hex(UInt64(off_ipc_port_ip_kobject))).foregroundColor(.secondary).monospaced() }
                    
                    HStack { Text("off_arm_kernel_saved_state_sp"); Spacer(); Text(hex(UInt64(off_arm_kernel_saved_state_sp))).foregroundColor(.secondary).monospaced() }
                    
                    HStack { Text("off_vm_map_hdr"); Spacer(); Text(hex(UInt64(off_vm_map_hdr))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_vm_map_header_nentries"); Spacer(); Text(hex(UInt64(off_vm_map_header_nentries))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_vm_map_entry_links_next"); Spacer(); Text(hex(UInt64(off_vm_map_entry_links_next))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_vm_map_entry_vme_object_or_delta"); Spacer(); Text(hex(UInt64(off_vm_map_entry_vme_object_or_delta))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_vm_map_entry_vme_alias"); Spacer(); Text(hex(UInt64(off_vm_map_entry_vme_alias))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_vm_map_header_links_next"); Spacer(); Text(hex(UInt64(off_vm_map_header_links_next))).foregroundColor(.secondary).monospaced() }
                    
                    HStack { Text("off_vm_object_vo_un1_vou_size"); Spacer(); Text(hex(UInt64(off_vm_object_vo_un1_vou_size))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_vm_object_ref_count"); Spacer(); Text(hex(UInt64(off_vm_object_ref_count))).foregroundColor(.secondary).monospaced() }
                    
                    HStack { Text("off_vm_named_entry_backing_copy"); Spacer(); Text(hex(UInt64(off_vm_named_entry_backing_copy))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_vm_named_entry_size"); Spacer(); Text(hex(UInt64(off_vm_named_entry_size))).foregroundColor(.secondary).monospaced() }
                    
                    HStack { Text("off_label_l_perpolicy_amfi"); Spacer(); Text(hex(UInt64(off_label_l_perpolicy_amfi))).foregroundColor(.secondary).monospaced() }
                    HStack { Text("off_label_l_perpolicy_sandbox"); Spacer(); Text(hex(UInt64(off_label_l_perpolicy_sandbox))).foregroundColor(.secondary).monospaced() }
                    
                    HStack { Text("sizeof_ipc_entry"); Spacer(); Text(hex(UInt64(sizeof_ipc_entry))).foregroundColor(.secondary).monospaced() }
                    
                    HStack { Text("smr_base"); Spacer(); Text(hex(smr_base)).foregroundColor(.secondary).monospaced() }
                    HStack { Text("T1SZ_BOOT"); Spacer(); TextField("0x19", text: t1szbootbind).foregroundColor(.secondary).multilineTextAlignment(.trailing).monospaced() }
                    HStack { Text("VM_MIN_KERNEL_ADDRESS"); Spacer(); Text(hex(VM_MIN_KERNEL_ADDRESS)).foregroundColor(.secondary).monospaced() }
                    HStack { Text("VM_MAX_KERNEL_ADDRESS"); Spacer(); Text(hex(VM_MAX_KERNEL_ADDRESS)).foregroundColor(.secondary).monospaced() }
                    
                    Button {
                        save()
                        statusmsg = "Offsets saved!"
                    } label: {
                        Text("Save Offsets")
                    }
                } header: {
                    Text("offsets")
                } footer: {
                    Text("Manually save offsets after modifying values like t1sz_boot")
                }
                
                Section {
                    HStack(alignment: .top) {
                        AsyncImage(url: URL(string: "https://github.com/rooootdev.png")) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        
                        VStack(alignment: .leading) {
                            Text("roooot")
                                .font(.headline)
                            
                            Text("Main Developer")
                                .font(.subheadline)
                                .foregroundColor(Color.secondary)
                        }
                        
                        Spacer()
                    }
                    .onTapGesture {
                        if let url = URL(string: "https://github.com/rooootdev"),
                           UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url)
                        }
                    }
                    
                    HStack(alignment: .top) {
                        AsyncImage(url: URL(string: "https://github.com/wh1te4ever.png")) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        
                        VStack(alignment: .leading) {
                            Text("wh1te4ever")
                                .font(.headline)
                            
                            Text("Made darksword-kexploit-fun.")
                                .font(.subheadline)
                                .foregroundColor(Color.secondary)
                        }
                        
                        Spacer()
                    }
                    .onTapGesture {
                        if let url = URL(string: "https://github.com/wh1te4ever"),
                           UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url)
                        }
                    }
                    
                    HStack(alignment: .top) {
                        AsyncImage(url: URL(string: "https://github.com/AppInstalleriOSGH.png")) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        
                        VStack(alignment: .leading) {
                            Text("AppInstaller iOS")
                                .font(.headline)
                            
                            Text("Helped me with offsets and lots of other stuff. This project wouldnt have been possible without him!")
                                .font(.subheadline)
                                .foregroundColor(Color.secondary)
                        }
                        
                        Spacer()
                    }
                    .onTapGesture {
                        if let url = URL(string: "https://github.com/AppInstalleriOSGH"),
                           UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url)
                        }
                    }
                    
                    HStack(alignment: .top) {
                        AsyncImage(url: URL(string: "https://github.com/jailbreakdotparty.png")) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        
                        VStack(alignment: .leading) {
                            Text("jailbreak.party")
                                .font(.headline)
                            
                            Text("All of the DirtyZero tweaks and emotional support.")
                                .font(.subheadline)
                                .foregroundColor(Color.secondary)
                        }
                        
                        Spacer()
                    }
                    .onTapGesture {
                        if let url = URL(string: "https://github.com/jailbreakdotparty"),
                           UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url)
                        }
                    }
                    
                    HStack(alignment: .top) {
                        AsyncImage(url: URL(string: "https://github.com/neonmodder123.png")) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        
                        VStack(alignment: .leading) {
                            Text("neon")
                                .font(.headline)
                            
                            Text("Made the respring script.")
                                .font(.subheadline)
                                .foregroundColor(Color.secondary)
                        }
                        
                        Spacer()
                    }
                    .onTapGesture {
                        if let url = URL(string: "https://github.com/neonmodder123"),
                           UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url)
                        }
                    }
                } header: {
                    Text("Credits")
                }
            }
            .navigationTitle("Settings")
        }
        .fileImporter(isPresented: $showkcacheimporter,
                      allowedContentTypes: [.data],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importingkernelcache = true
                DispatchQueue.global(qos: .userInitiated).async {
                    var ok = false
                    let shouldStopAccess = url.startAccessingSecurityScopedResource()
                    defer {
                        if shouldStopAccess {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    let fm = FileManager.default
                    if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
                        let dest = docs.appendingPathComponent("kernelcache")
                        do {
                            if fm.fileExists(atPath: dest.path) {
                                try fm.removeItem(at: dest)
                            }
                            try fm.copyItem(at: url, to: dest)
                            ok = dlkerncache()
                        } catch {
                            print("failed to import kernelcache: \(error)")
                            ok = false
                        }
                    }
                    DispatchQueue.main.async {
                        hasoffsets = ok
                        importingkernelcache = false
                    }
                }
            case .failure:
                break
            }
        }
        .alert("Clear Kernelcache Data?", isPresented: $showresetalert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                clearkerncachedata()
            }
        } message: {
            Text("This will delete the downloaded kernelcache and remove saved offsets.")
        }
        .alert("Status", isPresented: .constant(statusmsg != nil)) {
            Button("OK") { statusmsg = nil }
        } message: {
            Text(statusmsg ?? "")
        }
    }
    
    private func clearkerncachedata() {
        let fm = FileManager.default
        
        UserDefaults.standard.removeObject(forKey: "lara.kernelcache_path")
        UserDefaults.standard.removeObject(forKey: "lara.kernelcache_size")
        
        let docsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let kernelcacheDocPath = docsPath.appendingPathComponent("kernelcache")
        
        do {
            if fm.fileExists(atPath: kernelcacheDocPath.path) {
                try fm.removeItem(at: kernelcacheDocPath)
                mgr.logmsg("Deleted kernelcache from Documents")
            }
        } catch {
            mgr.logmsg("Failed to delete kernelcache: \(error.localizedDescription)")
        }
        
        let tempPath = NSTemporaryDirectory()
        let tempFiles = ["kernelcache.release.ipad", "kernelcache.release.iphone", "kernelcache.release.ipad3", "kernelcache.release.iphone14,3"]
        
        for file in tempFiles {
            let path = tempPath + file
            do {
                if fm.fileExists(atPath: path) {
                    try fm.removeItem(atPath: path)
                    mgr.logmsg("Deleted temp kernelcache: \(file)")
                }
            } catch {
                mgr.logmsg("Failed to delete \(file): \(error.localizedDescription)")
            }
        }
        
        mgr.logmsg("Kernelcache data cleared")
        hasoffsets = false
    }
    
    private func save() {
        UserDefaults.standard.set(t1sz_boot, forKey: "lara.t1sz_boot")
        UserDefaults.standard.synchronize()
        mgr.logmsg("Saved t1sz_boot: 0x\(String(t1sz_boot, radix: 16))")
    }
}

enum method: String, CaseIterable {
    case vfs = "VFS"
    case sbx = "SBX"
    case hybrid = "Hybrid"
}
