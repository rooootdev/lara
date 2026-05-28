//
//  offsets.m
//  lara
//
//  Created by ruter on 04.04.26.
//  shoutout: appinstallerios
//  shoutout: wh1te4ever
//

#import <Foundation/Foundation.h>
#import <xpc/xpc.h>
#import <UIKit/UIKit.h>
#import <sys/sysctl.h>

#import "xpf.h"
#import "libgrabkernel2.h"
#import "utils.h"
#import "vnode.h"
#import "darksword.h"

#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)

static NSString *const kkernprockey   = @"lara.kernprocoff";
static NSString *const kallprockey    = @"lara.allprocoff";
static NSString *const krootvnodekey  = @"lara.rootvnodeoff";
static NSString *const kkerncachekey  = @"lara.kernelcache_path";
static NSString *const kkernprocsize  = @"lara.kernproc_size";
static NSString *const kmacprocenforcekey = @"lara.mac_proc_enforce_off";

uint32_t off_inpcb_inp_list_le_next = 0;
uint32_t off_inpcb_inp_pcbinfo = 0;
uint32_t off_inpcb_inp_socket = 0;
uint32_t off_inpcb_inp_depend6_inp6_icmp6filt = 0;
uint32_t off_inpcb_inp_depend6_inp6_chksum = 0;
uint32_t off_inpcbinfo_ipi_zone = 0;
uint32_t off_socket_so_usecount = 0;
uint32_t off_socket_so_proto = 0;
uint32_t off_socket_so_background_thread = 0;
uint32_t off_protosw_pr_input = 0;
uint32_t off_kalloc_type_view_kt_zv_zv_name = 0;
uint32_t off_thread_t_tro = 0;
uint32_t off_thread_ro_tro_proc = 0;
uint32_t off_thread_ro_tro_task = 0;
uint32_t off_thread_machine_upcb = 0;
uint32_t off_thread_machine_contextdata = 0;
uint32_t off_thread_ctid = 0;
uint32_t off_thread_options = 0;
uint32_t off_thread_mutex_lck_mtx_data = 0;
uint32_t off_thread_machine_kstackptr = 0;
uint32_t off_thread_machine_jop_pid = 0;
uint32_t off_thread_machine_rop_pid = 0;
uint32_t off_thread_guard_exc_info_code = 0;
uint32_t off_thread_mach_exc_info_code = 0;
uint32_t off_thread_mach_exc_info_os_reason = 0;
uint32_t off_thread_mach_exc_info_exception_type = 0;
uint32_t off_thread_ast = 0;
uint32_t off_thread_task_threads_next = 0;
uint32_t off_proc_p_list_le_next = 0;
uint32_t off_proc_p_list_le_prev = 0;
uint32_t off_proc_p_proc_ro = 0;
uint32_t off_proc_p_pid = 0;
uint32_t off_proc_p_fd = 0;
uint32_t off_proc_p_flag = 0;
uint32_t off_proc_p_textvp = 0;
uint32_t off_proc_p_name = 0;
uint32_t off_proc_ro_pr_task = 0;
uint32_t off_proc_ro_p_ucred = 0;
uint32_t off_ucred_cr_label = 0;
uint32_t off_task_itk_space = 0;
uint32_t off_task_threads_next = 0;
uint32_t off_task_task_exc_guard = 0;
uint32_t off_task_map = 0;
uint32_t off_filedesc_fd_ofiles = 0;
uint32_t off_filedesc_fd_cdir = 0;
uint32_t off_fileproc_fp_glob = 0;
uint32_t off_fileglob_fg_data = 0;
uint32_t off_fileglob_fg_flag = 0;
uint32_t off_vnode_v_ncchildren_tqh_first = 0;
uint32_t off_vnode_v_nclinks_lh_first = 0;
uint32_t off_vnode_v_parent = 0;
uint32_t off_vnode_v_data = 0;
uint32_t off_vnode_v_name = 0;
uint32_t off_vnode_v_usecount = 0;
uint32_t off_vnode_v_iocount = 0;
uint32_t off_vnode_v_writecount = 0;
uint32_t off_vnode_v_flag = 0;
uint32_t off_vnode_v_mount = 0;
uint32_t off_mount_mnt_flag = 0;
uint32_t off_namecache_nc_vp = 0;
uint32_t off_namecache_nc_child_tqe_next = 0;
uint32_t off_arm_saved_state64_lr = 0;
uint32_t off_arm_saved_state64_pc = 0;
uint32_t off_arm_saved_state_uss_ss_64 = 0;
uint32_t off_ipc_space_is_table = 0;
uint32_t off_ipc_entry_ie_object = 0;
uint32_t off_ipc_port_ip_kobject = 0;
uint32_t off_arm_kernel_saved_state_sp = 0;
uint32_t off_vm_map_hdr = 0;
uint32_t off_vm_map_header_nentries = 0;
uint32_t off_vm_map_entry_links_next = 0;
uint32_t off_vm_map_entry_vme_object_or_delta = 0;
uint32_t off_vm_map_entry_vme_alias = 0;
uint32_t off_vm_map_header_links_next = 0;
uint32_t off_vm_object_vo_un1_vou_size = 0;
uint32_t off_vm_object_ref_count = 0;
uint32_t off_vm_named_entry_backing_copy = 0;
uint32_t off_vm_named_entry_size = 0;
uint32_t off_label_l_perpolicy_amfi = 0;
uint32_t off_label_l_perpolicy_sandbox = 0;
uint32_t sizeof_ipc_entry = 0;
uint64_t smr_base = 0;
uint64_t t1sz_boot = 0;
uint64_t VM_MIN_KERNEL_ADDRESS = 0;
uint64_t VM_MAX_KERNEL_ADDRESS = 0;
uint64_t pac_mask = 0;

typedef struct {
    const char *name;
    uint32_t *value;
} off32entry;

typedef struct {
    const char *name;
    uint64_t *value;
} off64entry;

#define OFFSET32(var) { #var, &var }
#define OFFSET64(var) { #var, &var }

static off32entry const koff32entries[] = {
    OFFSET32(off_inpcb_inp_list_le_next),
    OFFSET32(off_inpcb_inp_pcbinfo),
    OFFSET32(off_inpcb_inp_socket),
    OFFSET32(off_inpcb_inp_depend6_inp6_icmp6filt),
    OFFSET32(off_inpcb_inp_depend6_inp6_chksum),
    OFFSET32(off_inpcbinfo_ipi_zone),
    OFFSET32(off_socket_so_usecount),
    OFFSET32(off_socket_so_proto),
    OFFSET32(off_socket_so_background_thread),
    OFFSET32(off_protosw_pr_input),
    OFFSET32(off_kalloc_type_view_kt_zv_zv_name),
    OFFSET32(off_thread_t_tro),
    OFFSET32(off_thread_ro_tro_proc),
    OFFSET32(off_thread_ro_tro_task),
    OFFSET32(off_thread_machine_upcb),
    OFFSET32(off_thread_machine_contextdata),
    OFFSET32(off_thread_ctid),
    OFFSET32(off_thread_options),
    OFFSET32(off_thread_mutex_lck_mtx_data),
    OFFSET32(off_thread_machine_kstackptr),
    OFFSET32(off_thread_machine_jop_pid),
    OFFSET32(off_thread_machine_rop_pid),
    OFFSET32(off_thread_guard_exc_info_code),
    OFFSET32(off_thread_mach_exc_info_code),
    OFFSET32(off_thread_mach_exc_info_os_reason),
    OFFSET32(off_thread_mach_exc_info_exception_type),
    OFFSET32(off_thread_ast),
    OFFSET32(off_thread_task_threads_next),
    OFFSET32(off_proc_p_list_le_next),
    OFFSET32(off_proc_p_list_le_prev),
    OFFSET32(off_proc_p_proc_ro),
    OFFSET32(off_proc_p_pid),
    OFFSET32(off_proc_p_fd),
    OFFSET32(off_proc_p_flag),
    OFFSET32(off_proc_p_textvp),
    OFFSET32(off_proc_p_name),
    OFFSET32(off_proc_ro_pr_task),
    OFFSET32(off_proc_ro_p_ucred),
    OFFSET32(off_ucred_cr_label),
    OFFSET32(off_task_itk_space),
    OFFSET32(off_task_threads_next),
    OFFSET32(off_task_task_exc_guard),
    OFFSET32(off_task_map),
    OFFSET32(off_filedesc_fd_ofiles),
    OFFSET32(off_filedesc_fd_cdir),
    OFFSET32(off_fileproc_fp_glob),
    OFFSET32(off_fileglob_fg_data),
    OFFSET32(off_fileglob_fg_flag),
    OFFSET32(off_vnode_v_ncchildren_tqh_first),
    OFFSET32(off_vnode_v_nclinks_lh_first),
    OFFSET32(off_vnode_v_parent),
    OFFSET32(off_vnode_v_data),
    OFFSET32(off_vnode_v_name),
    OFFSET32(off_vnode_v_usecount),
    OFFSET32(off_vnode_v_iocount),
    OFFSET32(off_vnode_v_writecount),
    OFFSET32(off_vnode_v_flag),
    OFFSET32(off_vnode_v_mount),
    OFFSET32(off_mount_mnt_flag),
    OFFSET32(off_namecache_nc_vp),
    OFFSET32(off_namecache_nc_child_tqe_next),
    OFFSET32(off_arm_saved_state64_lr),
    OFFSET32(off_arm_saved_state64_pc),
    OFFSET32(off_arm_saved_state_uss_ss_64),
    OFFSET32(off_ipc_space_is_table),
    OFFSET32(off_ipc_entry_ie_object),
    OFFSET32(off_ipc_port_ip_kobject),
    OFFSET32(off_arm_kernel_saved_state_sp),
    OFFSET32(off_vm_map_hdr),
    OFFSET32(off_vm_map_header_nentries),
    OFFSET32(off_vm_map_entry_links_next),
    OFFSET32(off_vm_map_entry_vme_object_or_delta),
    OFFSET32(off_vm_map_entry_vme_alias),
    OFFSET32(off_vm_map_header_links_next),
    OFFSET32(off_vm_object_vo_un1_vou_size),
    OFFSET32(off_vm_object_ref_count),
    OFFSET32(off_vm_named_entry_backing_copy),
    OFFSET32(off_vm_named_entry_size),
    OFFSET32(off_label_l_perpolicy_amfi),
    OFFSET32(off_label_l_perpolicy_sandbox),
    OFFSET32(sizeof_ipc_entry),
};

static off64entry const koff64entries[] = {
    OFFSET64(smr_base),
    OFFSET64(VM_MIN_KERNEL_ADDRESS),
    OFFSET64(VM_MAX_KERNEL_ADDRESS),
};

static NSString *offkey(const char *name) {
    return [NSString stringWithFormat:@"lara.offset.%s", name];
}

static bool loadoff32(NSUserDefaults *defaults, off32entry const *entry) {
    NSNumber *saved = [defaults objectForKey:offkey(entry->name)];
    if (!saved) return false;

    uint32_t oldval = *entry->value;
    uint32_t savedval = [saved unsignedIntValue];
    if (savedval != oldval) {
        printf("(offs) (user-set) %s = 0x%x (default: 0x%x)\n", entry->name, savedval, oldval);
    }
    *entry->value = savedval;
    return savedval != oldval;
}

static bool loadoff64(NSUserDefaults *defaults, off64entry const *entry) {
    NSNumber *saved = [defaults objectForKey:offkey(entry->name)];
    if (!saved) return false;

    uint64_t oldval = *entry->value;
    uint64_t savedval = [saved unsignedLongLongValue];
    if (savedval != oldval) {
        printf("(offs) (user-set) %s = 0x%llx (default: 0x%llx)\n", entry->name, savedval, oldval);
    }
    *entry->value = savedval;
    return savedval != oldval;
}

static bool loadt1szboot(NSUserDefaults *defaults) {
    NSNumber *saved = [defaults objectForKey:@"lara.t1sz_boot"];
    if (!saved) {
        saved = [defaults objectForKey:offkey("t1sz_boot")];
    }
    if (!saved) return false;

    uint64_t oldval = t1sz_boot;
    uint64_t savedval = [saved unsignedLongLongValue];
    if (savedval != oldval) {
        printf("(offs) (user-set) %s = 0x%llx (default: 0x%llx)\n", "t1sz_boot", savedval, oldval);
    }
    t1sz_boot = savedval;
    return savedval != oldval;
}

static void saveoff32(NSUserDefaults *defaults, off32entry const *entry) {
    [defaults setObject:@(*entry->value) forKey:offkey(entry->name)];
}

static void saveoff64(NSUserDefaults *defaults, off64entry const *entry) {
    [defaults setObject:@(*entry->value) forKey:offkey(entry->name)];
}

static void refreshpacmask(void) {
    if (t1sz_boot == 0) {
        printf("(offs) alright, t1sz_boot is still 0x0, every man for himself!");
        pac_mask = 0;
        return;
    }

    if (t1sz_boot >= 64) {
        printf("(offs) invalid t1sz_boot: 0x%llx\n", t1sz_boot);
        pac_mask = 0;
        return;
    }

    pac_mask = ~((1ULL << (64 - t1sz_boot)) - 1ULL);
}

static void loadalloffsets(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    bool hadsaved = false;

    for (size_t i = 0; i < sizeof(koff32entries) / sizeof(koff32entries[0]); i++) {
        hadsaved |= loadoff32(defaults, &koff32entries[i]);
    }

    for (size_t i = 0; i < sizeof(koff64entries) / sizeof(koff64entries[0]); i++) {
        hadsaved |= loadoff64(defaults, &koff64entries[i]);
    }

    hadsaved |= loadt1szboot(defaults);
    
    if (hadsaved) {
        printf("(offs) loaded user-saved offsets above\n");
    }
}

void savealloffsets(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    for (size_t i = 0; i < sizeof(koff32entries) / sizeof(koff32entries[0]); i++) {
        saveoff32(defaults, &koff32entries[i]);
    }

    for (size_t i = 0; i < sizeof(koff64entries) / sizeof(koff64entries[0]); i++) {
        saveoff64(defaults, &koff64entries[i]);
    }

    [defaults setObject:@(t1sz_boot) forKey:offkey("t1sz_boot")];
    [defaults setObject:@(t1sz_boot) forKey:@"lara.t1sz_boot"];

    [defaults synchronize];
    printf("(offs) saved all offsets\n");
}

bool gIsPACSupported = false;
bool gIsA18Above = false;

NSDictionary *alloffs(void) {
    return @{
        @"t1sz_boot": @(t1sz_boot),
        @"smr_base": @(smr_base),
        @"sizeof_ipc_entry": @(sizeof_ipc_entry),
        @"pac_mask": @(pac_mask),
        @"off_thread_t_tro": @(off_thread_t_tro),
        @"off_thread_ro_tro_proc": @(off_thread_ro_tro_proc),
        @"off_thread_ro_tro_task": @(off_thread_ro_tro_task),
        @"off_thread_ctid": @(off_thread_ctid),
        @"off_thread_options": @(off_thread_options),
        @"off_thread_mutex_lck_mtx_data": @(off_thread_mutex_lck_mtx_data),
        @"off_thread_machine_kstackptr": @(off_thread_machine_kstackptr),
        @"off_thread_machine_jop_pid": @(off_thread_machine_jop_pid),
        @"off_thread_machine_rop_pid": @(off_thread_machine_rop_pid),
        @"off_thread_guard_exc_info_code": @(off_thread_guard_exc_info_code),
        @"off_thread_ast": @(off_thread_ast),
        @"off_thread_task_threads_next": @(off_thread_task_threads_next),
        @"off_proc_p_proc_ro": @(off_proc_p_proc_ro),
        @"off_proc_p_pid": @(off_proc_p_pid),
        @"off_proc_p_fd": @(off_proc_p_fd),
        @"off_proc_p_flag": @(off_proc_p_flag),
        @"off_proc_p_textvp": @(off_proc_p_textvp),
        @"off_proc_p_name": @(off_proc_p_name),
        @"off_proc_ro_pr_task": @(off_proc_ro_pr_task),
        @"off_ucred_cr_label": @(off_ucred_cr_label),
        @"off_task_itk_space": @(off_task_itk_space),
        @"off_task_threads_next": @(off_task_threads_next),
        @"off_task_task_exc_guard": @(off_task_task_exc_guard),
        @"off_vm_object_ref_count": @(off_vm_object_ref_count),
        @"VM_MIN_KERNEL_ADDRESS": @(VM_MIN_KERNEL_ADDRESS),
        @"VM_MAX_KERNEL_ADDRESS": @(VM_MAX_KERNEL_ADDRESS),
    };
}

static NSString *kcpath(void) {
    NSString *docs =
        NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                            NSUserDomainMask,
                                            YES).firstObject;

    return [docs stringByAppendingPathComponent:@"kernelcache"];
}

bool verifykernoffsets(void) {
    NSString *kc = kcpath();
    if (!kc || ![[NSFileManager defaultManager] fileExistsAtPath:kc]) {
        printf("(offs) no kernelcache file\n");
        return false;
    }
    
    if (xpf_start_with_kernel_path(kc.UTF8String) != 0) {
        printf("(offs) xpf start error: %s\n", xpf_get_error());
        return false;
    }
    
    const char *sets[] = { "base", "translation", "struct", NULL };
    xpc_object_t dict = xpf_construct_offset_dictionary(sets);
    
    xpf_stop();
    
    if (!dict) {
        printf("(offs) xpf dictionary failed: %s\n", xpf_get_error());
        return false;
    }
    
    return true;
}

bool resolvekernoffsets(NSString *kcpath) {
    if (xpf_start_with_kernel_path(kcpath.UTF8String) != 0) {
        printf("xpf start error: %s\n", xpf_get_error());
        return false;
    }
    
    const char *sets[] = { "base", "translation", "struct", NULL };
    xpc_object_t dict = xpf_construct_offset_dictionary(sets);

    if (!dict) {
        printf("xpf dict failed, continuing without offsets: %s\n", xpf_get_error());
    }

    printf("(offs) kernel: %s\n", gXPF.kernelVersionString);
    printf("(offs) kernbase: 0x%llx\n", gXPF.kernelBase);
    printf("(offs) kernentry: 0x%llx\n", gXPF.kernelEntry);

    uint64_t kernproc = xpf_item_resolve("kernelSymbol.kernproc");
    if (!kernproc) kernproc = xpf_item_resolve("kernproc");
    uint64_t allproc = xpf_item_resolve("kernelSymbol.allproc");
    uint64_t rootvnode = xpf_item_resolve("kernelSymbol.rootvnode");
    uint64_t procsize  = xpf_item_resolve("kernelStruct.proc.struct_size");
    uint64_t resolvedt1szboot = xpf_gett1szboot();

    if (!kernproc || !rootvnode) {
        printf("failed to resolve important kernel symbols\n");
        xpf_stop();
        return false;
    }

    if (kernproc < gXPF.kernelBase || rootvnode < gXPF.kernelBase) {
        printf("invalid kernel symbol addresses\n");
        xpf_stop();
        return false;
    }

    uint64_t allprocoff = allproc ? allproc - gXPF.kernelBase : 0;
    uint64_t kernprocoff = kernproc - gXPF.kernelBase;
    uint64_t rootvnodeoff = rootvnode - gXPF.kernelBase;

    printf("(offs) allproc: 0x%llx\n", allprocoff);
    printf("(offs) kernproc: 0x%llx\n", kernprocoff);
    printf("(offs) rootvnode: 0x%llx\n", rootvnodeoff);
    printf("(offs) procsize: 0x%llx\n", procsize);
    printf("(offs) t1szboot: 0x%llx\n", resolvedt1szboot);

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    [defaults setObject:@(kernprocoff) forKey:kkernprockey];
    if (allprocoff) {
        [defaults setObject:@(allprocoff) forKey:kallprockey];
    }
    [defaults setObject:@(rootvnodeoff) forKey:krootvnodekey];
    [defaults setObject:@(procsize) forKey:kkernprocsize];
    [defaults setObject:kcpath forKey:kkerncachekey];

    if (resolvedt1szboot != 0) {
        t1sz_boot = resolvedt1szboot;
        refreshpacmask();
        [defaults setObject:@(resolvedt1szboot) forKey:offkey("t1sz_boot")];
        [defaults setObject:@(resolvedt1szboot) forKey:@"lara.t1sz_boot"];
    }

    [defaults synchronize];

    xpf_stop();

    return true;
}

bool iskcachevalid(NSString* kc) {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:kc];
    NSData *data = [handle readDataOfLength:2];
    [handle closeFile];

    if (data.length == 2) {
        const uint8_t *bytes = data.bytes;
        if (bytes[0] == 0x30 && bytes[1] == 0x84) {
            return true;
        }
    }
    return false;
}

bool dlkcache(void) {
    NSString *outpath = kcpath();

    if (!outpath) {
        printf("(offs) documents path failure\n");
        return false;
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:outpath]) {
        printf("(offs) downloading kernelcache -> %s\n", outpath.UTF8String);

        if (!grab_kernelcache(outpath)) {
            printf("(offs) kernelcache download failed.\n");
            return false;
        }
    } else {
        printf("(offs) using cached kernelcache\n");
    }

    return resolvekernoffsets(outpath);
}

bool emergencyfixfunctiontobereplacedlateronquestionmark(void) {
    NSString *outpath = kcpath();

    if (!outpath) {
        printf("(offs) documents path failure\n");
        return false;
    }
    
    return resolvekernoffsets(outpath);
}

cpu_subtype_t get_hw_cpufamily(void) {
    cpu_subtype_t cpuFamily = 0;
    size_t cpuFamilySize = sizeof(cpuFamily);
    sysctlbyname("hw.cpufamily", &cpuFamily, &cpuFamilySize, NULL, 0);
    return cpuFamily;
}

bool is_pac_supported(void) {
    cpu_subtype_t cpusubtype = 0;
    size_t sz = sizeof(cpusubtype);
    if (sysctlbyname("hw.cpusubtype", &cpusubtype, &sz, NULL, 0) != 0) return false;
    if (cpusubtype == CPU_SUBTYPE_ARM64E) return true;
    return false;
}

static bool is_ipad_device(void) {
    char machine[64] = {0};
    size_t sz = sizeof(machine);
    sysctlbyname("hw.machine", machine, &sz, NULL, 0);
    return strncmp(machine, "iPad", 4) == 0;
}

static bool is_known_a_series_ipad_identifier(void) {
    char machine[64] = {0};
    size_t sz = sizeof(machine);
    if (sysctlbyname("hw.machine", machine, &sz, NULL, 0) != 0) return false;
    return strcmp(machine, "iPad13,1") == 0 ||
           strcmp(machine, "iPad13,2") == 0 ||
           strcmp(machine, "iPad13,18") == 0 ||
           strcmp(machine, "iPad13,19") == 0 ||
           strcmp(machine, "iPad14,1") == 0 ||
           strcmp(machine, "iPad14,2") == 0;
}

void offsets_init(void) {
    if (!(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"16.0") && SYSTEM_VERSION_LESS_THAN(@"26.1"))) {
        printf("(offs) only supported offset for iOS 16.0 - 26.0.x\n");
        exit(EXIT_FAILURE);
    }
    
    cpu_subtype_t cpuFamily = get_hw_cpufamily();
    
    bool isA10      =   (cpuFamily == CPUFAMILY_ARM_HURRICANE);
    
    bool isA13Above =   (cpuFamily == CPUFAMILY_ARM_LIGHTNING_THUNDER ||
                         cpuFamily == CPUFAMILY_ARM_FIRESTORM_ICESTORM ||
                         cpuFamily == CPUFAMILY_ARM_BLIZZARD_AVALANCHE ||
                         cpuFamily == CPUFAMILY_ARM_EVEREST_SAWTOOTH ||
                         cpuFamily == CPUFAMILY_ARM_COLL ||
                         cpuFamily == CPUFAMILY_ARM_IBIZA ||
                         cpuFamily == CPUFAMILY_ARM_TUPAI ||
                         cpuFamily == CPUFAMILY_ARM_TAHITI ||
                         cpuFamily == CPUFAMILY_ARM_DONAN);
    
    bool isA15Above =   (cpuFamily == CPUFAMILY_ARM_BLIZZARD_AVALANCHE ||
                         cpuFamily == CPUFAMILY_ARM_EVEREST_SAWTOOTH ||
                         cpuFamily == CPUFAMILY_ARM_COLL ||
                         cpuFamily == CPUFAMILY_ARM_IBIZA ||
                         cpuFamily == CPUFAMILY_ARM_TUPAI ||
                         cpuFamily == CPUFAMILY_ARM_TAHITI ||
                         cpuFamily == CPUFAMILY_ARM_DONAN);
    
    bool isA16Above =   (cpuFamily == CPUFAMILY_ARM_EVEREST_SAWTOOTH ||
                         cpuFamily == CPUFAMILY_ARM_COLL ||
                         cpuFamily == CPUFAMILY_ARM_IBIZA ||
                         cpuFamily == CPUFAMILY_ARM_TUPAI ||
                         cpuFamily == CPUFAMILY_ARM_TAHITI ||
                         cpuFamily == CPUFAMILY_ARM_DONAN);
    
    bool isA17Above =   (cpuFamily == CPUFAMILY_ARM_COLL ||
                         cpuFamily == CPUFAMILY_ARM_IBIZA ||
                         cpuFamily == CPUFAMILY_ARM_TUPAI ||
                         cpuFamily == CPUFAMILY_ARM_TAHITI ||
                         cpuFamily == CPUFAMILY_ARM_DONAN);
    
    gIsA18Above =   (cpuFamily == CPUFAMILY_ARM_TUPAI ||
                     cpuFamily == CPUFAMILY_ARM_TAHITI ||
                     cpuFamily == CPUFAMILY_ARM_DONAN);
    
    bool isMSeriesIpad = is_ipad_device() && !is_known_a_series_ipad_identifier() && (
                                              cpuFamily == CPUFAMILY_ARM_FIRESTORM_ICESTORM ||
                                              cpuFamily == CPUFAMILY_ARM_BLIZZARD_AVALANCHE ||
                                              cpuFamily == CPUFAMILY_ARM_IBIZA ||
                                              cpuFamily == CPUFAMILY_ARM_DONAN);
    
    
    gIsPACSupported = is_pac_supported();
    
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"16.0")) {
        bool isIOS16 = SYSTEM_VERSION_LESS_THAN(@"17.0");
        off_inpcb_inp_list_le_next = 0x20;
        off_inpcb_inp_pcbinfo = 0x38;
        off_inpcb_inp_socket = 0x40;
        off_inpcb_inp_depend6_inp6_icmp6filt = 0x150;
        off_inpcb_inp_depend6_inp6_chksum = 0x158;
        off_inpcbinfo_ipi_zone = 0x68;
        off_socket_so_usecount = 0x22c;
        off_socket_so_proto = 0x18;
        off_socket_so_background_thread = 0x288;
        off_protosw_pr_input = 0x28;
        off_kalloc_type_view_kt_zv_zv_name = 0x10;
        off_thread_ro_tro_proc = isIOS16 ? 0x18 : 0x10;
        off_thread_ro_tro_task = isIOS16 ? 0x28 : 0x20;
        off_thread_machine_upcb = 0xb0;
        off_thread_machine_contextdata = 0xb0-8;
        off_thread_t_tro = 0x358;
        off_thread_ctid = 0x408;
        off_thread_options = 0x70;
        off_thread_mutex_lck_mtx_data = 0x380+8;
        off_thread_machine_kstackptr = 0xe8;
        off_thread_machine_jop_pid = 0x158;
        off_thread_machine_rop_pid = 0x158-8;
        off_thread_guard_exc_info_code = 0x308;
        off_thread_ast = 0x37c;
        off_thread_task_threads_next = 0x348;
        if (isIOS16) {
            off_thread_ro_tro_proc = 0x10;
            off_thread_ro_tro_task = 0x20;
            off_thread_t_tro = 0x360;
            off_thread_mutex_lck_mtx_data = 0x390;
            off_thread_ast = 0x334;
            off_thread_task_threads_next = 0x350;
        }
        off_proc_p_list_le_next = 0x0;
        off_proc_p_list_le_prev = 0x8;
        off_proc_p_proc_ro = 0x18;
        off_proc_p_pid = 0x60;
        off_proc_p_fd = isIOS16 ? 0xd8 : 0xd0;
        if (!isIOS16 || SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"16.4")) {
            off_proc_p_flag = 0x454;
            off_proc_p_textvp = 0x548;
        } else {
            off_proc_p_flag = 0x25c;
            off_proc_p_textvp = 0x350;
        }
        off_proc_p_name = 0x579;
        off_proc_ro_pr_task = 0x8;
        off_proc_ro_p_ucred = 0x20;
        off_ucred_cr_label = 0x78;
        off_task_itk_space = 0x300;
        off_task_threads_next = 0x58;
        off_task_task_exc_guard = 0x5bc;
        off_task_map = 0x28;
        off_filedesc_fd_ofiles = 0x28;
        off_filedesc_fd_cdir = 0x48;
        off_fileproc_fp_glob = 0x10;
        off_fileglob_fg_data = 0x38;
        off_fileglob_fg_flag = 0x10;
        off_vnode_v_ncchildren_tqh_first = 0x30;
        off_vnode_v_nclinks_lh_first = 0x40;
        off_vnode_v_parent = 0xc0;
        off_vnode_v_data = 0xe0;
        off_vnode_v_name = 0xb8;
        off_vnode_v_usecount = 0x60;
        off_vnode_v_iocount = 0x64;
        off_vnode_v_writecount = 0xb0;
        off_vnode_v_flag = 0x54;
        off_vnode_v_mount = 0xd8;
        off_mount_mnt_flag = 0x70;
        off_namecache_nc_vp = 0x50;
        off_namecache_nc_child_tqe_next = 0x10;
        off_arm_saved_state64_lr = 0xf0;
        off_arm_saved_state64_pc = 0x100;
        off_arm_saved_state_uss_ss_64 = 0x8;
        off_ipc_space_is_table = 0x20;
        off_ipc_entry_ie_object = 0;
        off_ipc_port_ip_kobject = 0x48;
        off_arm_kernel_saved_state_sp = 0x60;
        off_vm_map_hdr = 0x10;
        off_vm_map_header_nentries = 0x20;
        off_vm_map_entry_links_next = 0x8;
        off_vm_map_entry_vme_object_or_delta = 0x3c;
        off_vm_map_entry_vme_alias = 0x40;
        off_vm_map_header_links_next = 0x8;
        off_vm_object_vo_un1_vou_size = 0x18;
        off_vm_object_ref_count = 0x28;
        off_vm_named_entry_backing_copy = 0x10;
        off_vm_named_entry_size = 0x20;
        off_label_l_perpolicy_amfi = 0x8;
        off_label_l_perpolicy_sandbox = 0x10;
        
        smr_base = 2;
        sizeof_ipc_entry = 0x18;
        VM_MIN_KERNEL_ADDRESS = 0xFFFFFFDC00000000;
        VM_MAX_KERNEL_ADDRESS = 0xFFFFFFFBFFFFFFFF;
        
        if(isA13Above) {
            off_thread_t_tro = 0x368;
            off_thread_ctid = 0x418;
            off_thread_mutex_lck_mtx_data = 0x390+8;
            off_thread_machine_kstackptr = 0xf0;
            off_thread_machine_jop_pid = 0x160;
            off_thread_machine_rop_pid = 0x160-8;
            off_thread_guard_exc_info_code = 0x318;
            off_thread_ast = 0x38c;
            off_thread_task_threads_next = 0x358;
        }
        
        if(isA15Above) {
            off_thread_t_tro = 0x370;
            off_thread_ctid = 0x420;
            off_thread_mutex_lck_mtx_data = 0x398+8;
            off_thread_machine_jop_pid = 0x168;
            off_thread_machine_rop_pid = 0x168-8;
            off_thread_guard_exc_info_code = 0x320;
            off_thread_ast = 0x394;
            off_thread_task_threads_next = 0x360;
            off_task_task_exc_guard = 0x5d4;
        }
        
        if(isA16Above || isMSeriesIpad) {
            if (t1sz_boot == 0) {
                t1sz_boot = 0x11;
            }
        }
        
        if(isA17Above) {
            off_thread_machine_upcb = 0x100;
            off_thread_machine_contextdata = 0x100-8;
            off_thread_t_tro = 0x3c0;
            off_thread_ctid = 0x470;
            off_thread_options = 0xc0;
            off_thread_mutex_lck_mtx_data = 0x3e8+8;
            off_thread_machine_kstackptr = 0x140;
            off_thread_machine_jop_pid = 0x1B8;
            off_thread_machine_rop_pid = 0x1B8-8;
            off_thread_guard_exc_info_code = 0x370;
            off_thread_ast = 0x3e4;
            off_thread_task_threads_next = 0x3b0;
        }
        
        if(isA10) {
            off_thread_machine_upcb = 0xf8;
            off_thread_machine_contextdata = 0xf8-8;
            off_thread_t_tro = 0x388;
            off_thread_ctid = 0x438;
            off_thread_options = 0xb8;
            off_thread_mutex_lck_mtx_data = 0x3b0+8;
            off_thread_machine_kstackptr = 0x130;
            off_thread_machine_jop_pid = 0xdeaddead;
            off_thread_machine_rop_pid = 0xdeaddead;
            off_thread_guard_exc_info_code = 0x338;
            off_thread_ast = 0x3ac;
            off_thread_task_threads_next = 0x378;
            off_task_task_exc_guard = 0x59c;
        }
        
        if(isMSeriesIpad) {
            VM_MIN_KERNEL_ADDRESS = 0xFFFFFE0000000000;
            VM_MAX_KERNEL_ADDRESS = 0xFFFFFE8FFFFFFFFF;
        }
    }
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"17.1")) {
        off_inpcb_inp_depend6_inp6_icmp6filt = 0x148;
        off_inpcb_inp_depend6_inp6_chksum = 0x150;
        off_socket_so_usecount = 0x24c;
        off_socket_so_background_thread = 0x2a8;
        off_thread_t_tro = 0x368;
        off_thread_ctid = 0x418;
        off_thread_mutex_lck_mtx_data = 0x390+8;
        off_thread_guard_exc_info_code = 0x318;
        off_thread_ast = 0x38C;
        off_thread_task_threads_next = 0x358;
        
        if(isA13Above) {
            off_thread_t_tro = 0x378;
            off_thread_ctid = 0x428;
            off_thread_mutex_lck_mtx_data = 0x3a0+8;
            off_thread_guard_exc_info_code = 0x328;
            off_thread_ast = 0x39c;
            off_thread_task_threads_next = 0x368;
        }
        
        if(isA15Above) {
            off_thread_t_tro = 0x380;
            off_thread_ctid = 0x430;
            off_thread_mutex_lck_mtx_data = 0x3a8+8;
            off_thread_guard_exc_info_code = 0x330;
            off_thread_ast = 0x3A4;
            off_thread_task_threads_next = 0x370;
        }
        
        if(isA17Above) {
            off_thread_t_tro = 0x3d0;
            off_thread_ctid = 0x480;
            off_thread_mutex_lck_mtx_data = 0x3f8+8;
            off_thread_guard_exc_info_code = 0x380;
            off_thread_ast = 0x3F4;
            off_thread_task_threads_next = 0x3c0;
        }
        
        if(isA10) {
            off_thread_t_tro = 0x398;
            off_thread_ctid = 0x448;
            off_thread_mutex_lck_mtx_data = 0x3c0+8;
            off_thread_guard_exc_info_code = 0x348;
            off_thread_ast = 0x3BC;
            off_thread_task_threads_next = 0x388;
        }
    }
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"17.4")) {
        off_socket_so_usecount = 0x254;
        off_socket_so_proto = 0x20;
        off_socket_so_background_thread = 0x2b0;
        off_thread_ro_tro_proc = 0x18;
        off_thread_ro_tro_task = 0x28;
        off_proc_p_name = 0x57d;
        off_thread_t_tro = 0x370;
        off_thread_ctid = 0x420;
        off_thread_mutex_lck_mtx_data = 0x398+8;
        off_thread_guard_exc_info_code = 0x320;
        off_thread_ast = 0x394;
        off_thread_task_threads_next = 0x360;
        
        if(isA13Above) {
            off_thread_t_tro = 0x380;
            off_thread_ctid = 0x430;
            off_thread_mutex_lck_mtx_data = 0x3a8+8;
            off_thread_guard_exc_info_code = 0x330;
            off_thread_ast = 0x3a4;
            off_thread_task_threads_next = 0x370;
        }
        
        if(isA15Above) {
            off_thread_t_tro = 0x388;
            off_thread_ctid = 0x438;
            off_thread_mutex_lck_mtx_data = 0x3b0+8;
            off_thread_guard_exc_info_code = 0x338;
            off_thread_ast = 0x3ac;
            off_thread_task_threads_next = 0x378;
        }
        
        if(isA17Above) {
            off_thread_t_tro = 0x3d8;
            off_thread_ctid = 0x488;
            off_thread_mutex_lck_mtx_data = 0x400+8;
            off_thread_guard_exc_info_code = 0x388;
            off_thread_ast = 0x3fc;
            off_thread_task_threads_next = 0x3c8;
        }
        
        if(gIsA18Above) {
            off_thread_t_tro = 0x3E0;
            off_thread_ctid = 0x4a0;
            off_thread_mutex_lck_mtx_data = 0x408+8;
            off_thread_guard_exc_info_code = 0x390;
            off_thread_ast = 0x404;
            off_thread_task_threads_next = 0x3D0;
            off_task_task_exc_guard = 0x5DC;
        }
        
        if(isA10) {
            off_thread_t_tro = 0x3a0;
            off_thread_ctid = 0x450;
            off_thread_mutex_lck_mtx_data = 0x3c8+8;
            off_thread_guard_exc_info_code = 0x350;
            off_thread_ast = 0x3c4;
            off_thread_task_threads_next = 0x390;
        }
    }
    
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"18.0")) {
        off_inpcb_inp_list_le_next = 0x20;
        off_inpcb_inp_pcbinfo = 0x38;
        off_inpcb_inp_socket = 0x40;
        off_inpcb_inp_depend6_inp6_icmp6filt = 0x148;
        off_inpcb_inp_depend6_inp6_chksum = 0x150;
        off_inpcbinfo_ipi_zone = 0x68;
        off_socket_so_usecount = 0x254;
        off_socket_so_proto = 0x20;
        off_socket_so_background_thread = 0x2b0;
        off_kalloc_type_view_kt_zv_zv_name = 0x10;
        off_thread_ro_tro_proc = 0x18;
        off_thread_ro_tro_task = 0x28;
        off_thread_machine_upcb = 0xb8;
        off_thread_machine_contextdata = 0xb8-8;
        off_thread_t_tro = 0x378;
        off_thread_ctid = 0x428;
        off_thread_options = 0x70;
        off_thread_mutex_lck_mtx_data = 0x3a0+8;
        off_thread_machine_kstackptr = 0xF0;
        off_thread_machine_jop_pid = 0x160;
        off_thread_machine_rop_pid = 0x160-8;
        off_thread_guard_exc_info_code = 0x320;
        off_thread_ast = 0x39C;
        off_thread_task_threads_next = 0x368;
        off_proc_p_list_le_next = 0x0;
        off_proc_p_list_le_prev = 0x8;
        off_proc_p_proc_ro = 0x18;
        off_proc_p_pid = 0x60;
        off_proc_p_fd = 0xd0;
        off_proc_p_flag = 0x454;
        off_proc_p_textvp = 0x548;
        off_proc_p_name = 0x57d;
        off_proc_ro_pr_task = 0x8;
        off_proc_ro_p_ucred = 0x20;
        off_ucred_cr_label = 0x78;
        off_task_itk_space = 0x318;
        off_task_threads_next = 0x50;
        off_task_task_exc_guard = 0x5dc;
        off_task_map = 0x28;
        off_filedesc_fd_ofiles = 0x28;
        off_filedesc_fd_cdir = 0x48;
        off_fileproc_fp_glob = 0x10;
        off_fileglob_fg_data = 0x38;
        off_fileglob_fg_flag = 0x10;
        off_vnode_v_ncchildren_tqh_first = 0x30;
        off_vnode_v_nclinks_lh_first = 0x40;
        off_vnode_v_parent = 0xc0;
        off_vnode_v_data = 0xe0;
        off_vnode_v_name = 0xb8;
        off_vnode_v_usecount = 0x60;
        off_vnode_v_iocount = 0x64;
        off_vnode_v_writecount = 0xb0;
        off_vnode_v_flag = 0x54;
        off_vnode_v_mount = 0xd8;
        off_mount_mnt_flag = 0x70;
        off_namecache_nc_vp = 0x50;
        off_namecache_nc_child_tqe_next = 0x10;
        off_arm_saved_state64_lr = 0xf0;
        off_arm_saved_state64_pc = 0x100;
        off_arm_saved_state_uss_ss_64 = 0x8;
        off_ipc_space_is_table = 0x20;
        off_ipc_entry_ie_object = 0;
        off_ipc_port_ip_kobject = 0x48;
        off_arm_kernel_saved_state_sp = 0x60;
        off_vm_map_hdr = 0x10;
        off_vm_map_header_nentries = 0x20;
        off_vm_map_entry_links_next = 0x8;
        off_vm_map_entry_vme_object_or_delta = 0x3c;
        off_vm_map_entry_vme_alias = 0x40;
        off_vm_map_header_links_next = 0x8;
        off_vm_object_vo_un1_vou_size = 0x18;
        off_vm_object_ref_count = 0x28;
        off_vm_named_entry_backing_copy = 0x10;
        off_vm_named_entry_size = 0x20;
        off_label_l_perpolicy_amfi = 0x8;
        off_label_l_perpolicy_sandbox = 0x10;
        
        if(isA13Above) {
            off_thread_t_tro = 0x388;
            off_thread_ctid = 0x438;
            off_thread_mutex_lck_mtx_data = 0x3B0+8;
            off_thread_machine_kstackptr = 0xF8;
            off_thread_machine_jop_pid = 0x168;
            off_thread_machine_rop_pid = 0x168-8;
            off_thread_guard_exc_info_code = 0x330;
            off_thread_ast = 0x3ac;
            off_thread_task_threads_next = 0x378;
        }
        
        if(isA15Above) {
            if (t1sz_boot == 0) {
                t1sz_boot = 0x19;
            }
            
            off_thread_t_tro = 0x390;
            off_thread_ctid = 0x440;
            off_thread_mutex_lck_mtx_data = 0x3B8+8;
            off_thread_machine_jop_pid = 0x170;
            off_thread_machine_rop_pid = 0x170-8;
            off_thread_guard_exc_info_code = 0x338;
            off_thread_ast = 0x3b4;
            off_thread_task_threads_next = 0x380;
            off_task_task_exc_guard = 0x5f4;
        }
        
        if(isA17Above) {
            off_thread_machine_upcb = 0x108;
            off_thread_machine_contextdata = 0x108-8;
            off_thread_t_tro = 0x3E0;
            off_thread_ctid = 0x490;
            off_thread_options = 0xC0;
            off_thread_mutex_lck_mtx_data = 0x408+8;
            off_thread_machine_jop_pid = 0x1c0;
            off_thread_machine_rop_pid = 0x1c0-8;
            off_thread_machine_kstackptr = 0x148;
            off_thread_guard_exc_info_code = 0x388;
            off_thread_ast = 0x404;
            off_thread_task_threads_next = 0x3d0;
        }
        
        if(gIsA18Above) {
            off_thread_t_tro = 0x3E8;
            off_thread_ctid = 0x4A8;
            off_thread_mutex_lck_mtx_data = 0x410+8;
            off_thread_guard_exc_info_code = 0x390;
            off_thread_ast = 0x40C;
            off_thread_task_threads_next = 0x3d8;
            off_task_task_exc_guard = 0x5fc;
        }
        
        if(isA10) {
            off_thread_machine_upcb = 0x100;
            off_thread_machine_contextdata = 0x100-8;
            off_thread_t_tro = 0x3A8;
            off_thread_ctid = 0x458;
            off_thread_options = 0xb8;
            off_thread_mutex_lck_mtx_data = 0x3d0+8;
            off_thread_machine_kstackptr = 0x138;
            off_thread_guard_exc_info_code = 0x350;
            off_thread_ast = 0x3cc;
            off_thread_task_threads_next = 0x398;
            off_task_task_exc_guard = 0x5c4;
        }
    }
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"18.1")) {
        off_thread_t_tro = 0x370;
        off_thread_ctid = 0x420;
        off_thread_mutex_lck_mtx_data = 0x398+8;
        off_thread_ast = 0x394;
        off_thread_task_threads_next = 0x360;
        
        if(isA13Above) {
            off_thread_t_tro = 0x380;
            off_thread_ctid = 0x430;
            off_thread_mutex_lck_mtx_data = 0x3A8+8;
            off_thread_ast = 0x3A4;
            off_thread_task_threads_next = 0x370;
        }
        
        if(isA15Above) {
            off_thread_t_tro = 0x388;
            off_thread_ctid = 0x438;
            off_thread_mutex_lck_mtx_data = 0x3B0+8;
            off_thread_ast = 0x3AC;
            off_thread_task_threads_next = 0x378;
        }
        
        if(isA17Above) {
            off_thread_t_tro = 0x3D8;
            off_thread_ctid = 0x488;
            off_thread_mutex_lck_mtx_data = 0x400+8;
            off_thread_ast = 0x3FC;
            off_thread_task_threads_next = 0x3C8;
        }
        
        if(gIsA18Above) {
            off_thread_t_tro = 0x3E0;
            off_thread_ctid = 0x4A0;
            off_thread_mutex_lck_mtx_data = 0x408+8;
            off_thread_ast = 0x404;
            off_thread_task_threads_next = 0x3D0;
        }
        
        if(isA10) {
            off_thread_t_tro = 0x3A0;
            off_thread_ctid = 0x450;
            off_thread_mutex_lck_mtx_data = 0x3C8+8;
            off_thread_ast = 0x3C4;
            off_thread_task_threads_next = 0x390;
        }
    }
    
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"18.4")) {
        off_thread_guard_exc_info_code = 0xdeaddead;
        
        off_thread_t_tro = 0x378;
        off_thread_ctid = 0x428;
        off_thread_mutex_lck_mtx_data = 0x3A0+8;
        off_thread_mach_exc_info_code = 0x328;
        off_thread_mach_exc_info_os_reason = 0x328-8;
        off_thread_mach_exc_info_exception_type = 0x328-4;
        off_thread_ast = 0x39C;
        off_thread_task_threads_next = 0x368;
        off_proc_ro_p_ucred = 0x28;
        off_task_task_exc_guard = 0x5FC;
        
        if(isA13Above) {
            off_thread_t_tro = 0x388;
            off_thread_ctid = 0x438;
            off_thread_mutex_lck_mtx_data = 0x3B0+8;
            off_thread_mach_exc_info_code = 0x338;
            off_thread_mach_exc_info_os_reason = 0x338-8;
            off_thread_mach_exc_info_exception_type = 0x338-4;
            off_thread_ast = 0x3AC;
            off_thread_task_threads_next = 0x378;
        }
        
        if(isA15Above) {
            off_thread_t_tro = 0x390;
            off_thread_ctid = 0x448;
            off_thread_mutex_lck_mtx_data = 0x3B8+8;
            off_thread_mach_exc_info_code = 0x340;
            off_thread_mach_exc_info_os_reason = 0x340-8;
            off_thread_mach_exc_info_exception_type = 0x340-4;
            off_thread_ast = 0x3B4;
            off_thread_task_threads_next = 0x380;
            off_task_task_exc_guard = 0x624;
        }
        
        if(isA17Above) {
            off_thread_t_tro = 0x3E0;
            off_thread_ctid = 0x498;
            off_thread_mutex_lck_mtx_data = 0x408+8;
            off_thread_mach_exc_info_code = 0x390;
            off_thread_mach_exc_info_os_reason = 0x390-8;
            off_thread_mach_exc_info_exception_type = 0x390-4;
            off_thread_ast = 0x404;
            off_thread_task_threads_next = 0x3D0;
        }
        
        if(gIsA18Above) {
            off_thread_t_tro = 0x3E8;
            off_thread_ctid = 0x4A8;
            off_thread_mutex_lck_mtx_data = 0x410+8;
            off_thread_mach_exc_info_code = 0x398;
            off_thread_mach_exc_info_os_reason = 0x398-8;
            off_thread_mach_exc_info_exception_type = 0x398-4;
            off_thread_ast = 0x40C;
            off_thread_task_threads_next = 0x3D8;
        }
        
        if(isA10) {
            off_thread_t_tro = 0x3A8;
            off_thread_ctid = 0x458;
            off_thread_mutex_lck_mtx_data = 0x3D0+8;
            off_thread_mach_exc_info_code = 0x358;
            off_thread_ast = 0x3CC;
            off_thread_task_threads_next = 0x398;
            off_task_task_exc_guard = 0x5E4;
        }
    }
    
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"18.6")) {
        off_thread_t_tro = 0x380;
        off_thread_ctid = 0x430;
        off_thread_mutex_lck_mtx_data = 0x3a8+8;
        off_thread_mach_exc_info_code = 0x330;
        off_thread_mach_exc_info_os_reason = 0x330-8;
        off_thread_mach_exc_info_exception_type = 0x330-4;
        off_thread_ast = 0x3A4;
        off_thread_task_threads_next = 0x370;
        
        if(isA13Above) {
            off_thread_t_tro = 0x390;
            off_thread_ctid = 0x440;
            off_thread_mutex_lck_mtx_data = 0x3B8+8;
            off_thread_mach_exc_info_code = 0x340;
            off_thread_mach_exc_info_os_reason = 0x340-8;
            off_thread_mach_exc_info_exception_type = 0x340-4;
            off_thread_ast = 0x3B4;
            off_thread_task_threads_next = 0x380;
        }
        
        if(isA15Above) {
            off_thread_t_tro = 0x398;
            off_thread_ctid = 0x450;
            off_thread_mutex_lck_mtx_data = 0x3c0+8;
            off_thread_mach_exc_info_code = 0x348;
            off_thread_mach_exc_info_os_reason = 0x348-8;
            off_thread_mach_exc_info_exception_type = 0x348-4;
            off_thread_ast = 0x3bc;
            off_thread_task_threads_next = 0x388;
        }
        
        if(isA17Above) {
            off_thread_t_tro = 0x3E8;
            off_thread_ctid = 0x4a0;
            off_thread_mutex_lck_mtx_data = 0x410+8;
            off_thread_mach_exc_info_code = 0x398;
            off_thread_mach_exc_info_os_reason = 0x398-8;
            off_thread_mach_exc_info_exception_type = 0x398-4;
            off_thread_ast = 0x40C;
            off_thread_task_threads_next = 0x3D8;
        }
        
        if(gIsA18Above) {
            off_thread_t_tro = 0x3F0;
            off_thread_ctid = 0x4b0;
            off_thread_mutex_lck_mtx_data = 0x418+8;
            off_thread_mach_exc_info_code = 0x3a0;
            off_thread_mach_exc_info_os_reason = 0x3a0-8;
            off_thread_mach_exc_info_exception_type = 0x3a0-4;
            off_thread_ast = 0x414;
            off_thread_task_threads_next = 0x3E0;
        }
        
        if(isA10) {
        }
    }
    
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"26.0")) {
        off_inpcb_inp_list_le_next = 0x20;
        off_inpcb_inp_pcbinfo = 0x38;
        off_inpcb_inp_socket = 0x40;
        off_inpcb_inp_depend6_inp6_icmp6filt = 0x148;
        off_inpcb_inp_depend6_inp6_chksum = 0x150;
        off_inpcbinfo_ipi_zone = 0x68;
        off_socket_so_usecount = 0x23c;
        off_socket_so_proto = 0x20;
        off_socket_so_background_thread = 0x298;
        off_kalloc_type_view_kt_zv_zv_name = 0x10;
        off_thread_ro_tro_proc = 0x18;
        off_thread_ro_tro_task = 0x28;
        off_thread_machine_upcb = 0xb8;
        off_thread_machine_contextdata = 0xb8-8;
        off_thread_t_tro = 0x390;
        off_thread_ctid = 0x430;
        off_thread_options = 0x70;
        off_thread_mutex_lck_mtx_data = 0x3A8+8;
        off_thread_machine_kstackptr = 0xf0;
        off_thread_machine_jop_pid = 0x160;
        off_thread_machine_rop_pid = 0x160-8;
        off_thread_guard_exc_info_code = 0xdeaddead;
        off_thread_mach_exc_info_code = 0x330;
        off_thread_mach_exc_info_os_reason = 0x330-8;
        off_thread_mach_exc_info_exception_type = 0x330-4;
        off_thread_ast = 0x3A4;
        off_thread_task_threads_next = 0x370;
        off_proc_p_list_le_next = 0x0;
        off_proc_p_list_le_prev = 0x8;
        off_proc_p_proc_ro = 0x18;
        off_proc_p_pid = 0x60;
        off_proc_p_fd = 0xd0;
        off_proc_p_flag = 0x454;
        off_proc_p_textvp = 0x548;
        off_proc_p_name = 0x57D;
        off_proc_ro_pr_task = 0x8;
        off_proc_ro_p_ucred = 0x28;
        off_ucred_cr_label = 0x78;
        off_task_itk_space = 0x310;
        off_task_threads_next = 0x50;
        off_task_task_exc_guard = 0x5d4;
        off_task_map = 0x28;
        off_filedesc_fd_ofiles = 0x28;
        off_filedesc_fd_cdir = 0x48;
        off_fileproc_fp_glob = 0x10;
        off_fileglob_fg_data = 0x38;
        off_fileglob_fg_flag = 0x10;
        off_vnode_v_ncchildren_tqh_first = 0x30;
        off_vnode_v_nclinks_lh_first = 0x40;
        off_vnode_v_parent = 0xc0;
        off_vnode_v_data = 0xe0;
        off_vnode_v_name = 0xb8;
        off_vnode_v_usecount = 0x60;
        off_vnode_v_iocount = 0x64;
        off_vnode_v_writecount = 0xb0;
        off_vnode_v_flag = 0x54;
        off_vnode_v_mount = 0xd8;
        off_mount_mnt_flag = 0x70;
        off_namecache_nc_vp = 0x50;
        off_namecache_nc_child_tqe_next = 0x10;
        off_arm_saved_state64_lr = 0xf0;
        off_arm_saved_state64_pc = 0x100;
        off_arm_saved_state_uss_ss_64 = 0x8;
        off_ipc_space_is_table = 0x48;
        off_ipc_entry_ie_object = 0;
        off_ipc_port_ip_kobject = 0x50;
        off_arm_kernel_saved_state_sp = 0x60;
        off_vm_map_hdr = 0x10;
        off_vm_map_header_nentries = 0x20;
        off_vm_map_entry_links_next = 0x8;
        off_vm_map_entry_vme_object_or_delta = 0x3c;
        off_vm_map_entry_vme_alias = 0x40;
        off_vm_map_header_links_next = 0x8;
        off_vm_object_vo_un1_vou_size = 0x18;
        off_vm_object_ref_count = 0x28;
        off_vm_named_entry_backing_copy = 0x10;
        off_vm_named_entry_size = 0x20;
        off_label_l_perpolicy_amfi = 0x8;
        off_label_l_perpolicy_sandbox = 0x10;
        
        if(isA13Above) {
            off_thread_t_tro = 0x390;
            off_thread_ctid = 0x440;
            off_thread_mutex_lck_mtx_data = 0x3B8+8;
            off_thread_machine_kstackptr = 0xf8;
            off_thread_machine_jop_pid = 0x168;
            off_thread_machine_rop_pid = 0x168-8;
            off_thread_mach_exc_info_code = 0x340;
            off_thread_mach_exc_info_os_reason = 0x340-8;
            off_thread_mach_exc_info_exception_type = 0x340-4;
            off_thread_ast = 0x3b4;
            off_thread_task_threads_next = 0x380;
        }
        
        if(isA15Above) {
            off_thread_t_tro = 0x398;
            off_thread_ctid = 0x450;
            off_thread_mutex_lck_mtx_data = 0x3C0+8;
            off_thread_machine_jop_pid = 0x170;
            off_thread_machine_rop_pid = 0x170-8;
            off_thread_mach_exc_info_code = 0x348;
            off_thread_mach_exc_info_os_reason = 0x348-8;
            off_thread_mach_exc_info_exception_type = 0x348-4;
            off_thread_ast = 0x3BC;
            off_thread_task_threads_next = 0x388;
            off_task_task_exc_guard = 0x5fc;
        }
        
        if(isA17Above) {
            off_thread_machine_upcb = 0x108;
            off_thread_machine_contextdata = 0x108-8;
            off_thread_t_tro = 0x3e8;
            off_thread_ctid = 0x4a0;
            off_thread_options = 0xc0;
            off_thread_mutex_lck_mtx_data = 0x410+8;
            off_thread_machine_kstackptr = 0x148;
            off_thread_machine_jop_pid = 0x1c0;
            off_thread_machine_rop_pid = 0x1c0-8;
            off_thread_mach_exc_info_code = 0x398;
            off_thread_mach_exc_info_os_reason = 0x398-8;
            off_thread_mach_exc_info_exception_type = 0x398-4;
            off_thread_ast = 0x40c;
            off_thread_task_threads_next = 0x3d8;
        }
        
        if(gIsA18Above) {
            off_thread_t_tro = 0x3f0;
            off_thread_ctid = 0x4b0;
            off_thread_mutex_lck_mtx_data = 0x418+8;
            off_thread_mach_exc_info_code = 0x3a0;
            off_thread_mach_exc_info_os_reason = 0x3a0-8;
            off_thread_mach_exc_info_exception_type = 0x3a0-4;
            off_thread_ast = 0x414;
            off_thread_task_threads_next = 0x3e0;
            off_task_task_exc_guard = 0x604;
        }
    }
    
    loadalloffsets();
    refreshpacmask();
    printf("(offs) initialized offsets\n");
}

uint64_t getmacprocenforceoff(void) {
    NSNumber *n = [[NSUserDefaults standardUserDefaults] objectForKey:kmacprocenforcekey];
    if (n && n.unsignedLongLongValue != 0) {
        return n.unsignedLongLongValue;
    }

    NSString *kc = kcpath();
    if (!kc || ![[NSFileManager defaultManager] fileExistsAtPath:kc]) {
        printf("(offsets) no kernelcache for mac_proc_enforce resolution\n");
        return 0;
    }

    printf("(offsets) resolving mac_proc_enforce via patchfinder...\n");
    if (xpf_start_with_kernel_path(kc.UTF8String) != 0) {
        printf("(offsets) xpf start error: %s\n", xpf_get_error());
        return 0;
    }

    const char *sets[] = { "base", "translation", NULL };
    xpf_construct_offset_dictionary(sets);

    uint64_t off = 0;
    
    PFStringMetric *strMetric = pfmetric_string_init("proc_enforce");
    __block uint64_t strAddr = 0;
    pfmetric_run(gXPF.kernelStringSection, strMetric, ^(uint64_t vmaddr, bool *stop) {
        strAddr = vmaddr;
        *stop = true;
    });
    pfmetric_free(strMetric);

    if (!strAddr) {
        printf("(offsets) \"proc_enforce\" string not found in kernel\n");
        xpf_stop();
        return 0;
    }
    printf("(offsets) \"proc_enforce\" string at 0x%llx\n", strAddr);

    PFXrefMetric *xrefMetric = pfmetric_xref_init(strAddr, XREF_TYPE_MASK_REFERENCE);
    __block uint64_t xrefAddr = 0;
    pfmetric_run(gXPF.kernelTextSection, xrefMetric, ^(uint64_t vmaddr, bool *stop) {
        xrefAddr = vmaddr;
        *stop = true;
    });
    pfmetric_free(xrefMetric);

    if (!xrefAddr) {
        printf("(offsets) no code xref to \"proc_enforce\" found\n");
        xpf_stop();
        return 0;
    }
    printf("(offsets) code xref at 0x%llx\n", xrefAddr);
    
    uint64_t candidate = 0;

    for (int delta = -10; delta <= 10; delta++) {
        uint64_t addr = xrefAddr + (delta * 4);
        uint64_t resolved = pfsec_arm64_resolve_adrp_ldr_str_add_reference_auto(
            gXPF.kernelTextSection, addr);
        if (resolved && resolved != strAddr) {
            if (pfsec_contains_vmaddr(gXPF.kernelDataSection, resolved) ||
                pfsec_contains_vmaddr(gXPF.kernelDataConstSection, resolved)) {
                candidate = resolved;
                printf("(offsets) candidate variable at 0x%llx (from delta=%d)\n",
                       resolved, delta);
                break;
            }
        }
    }

    if (candidate && candidate >= gXPF.kernelBase) {
        off = candidate - gXPF.kernelBase;
        printf("(offsets) mac_proc_enforce: 0x%llx\n", off);
        [[NSUserDefaults standardUserDefaults] setObject:@(off) forKey:kmacprocenforcekey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    } else {
        printf("(offsets) mac_proc_enforce variable not found via patchfinder\n");
    }

    xpf_stop();
    return off;
}

NSString *getkerncache(void) {
    return [[NSUserDefaults standardUserDefaults] objectForKey:kkerncachekey];
}

void clearkerncachedata(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *path = [defaults objectForKey:kkerncachekey];

    if (path.length) {
        NSError *err = nil;
        [[NSFileManager defaultManager] removeItemAtPath:path error:&err];
        if (err) {
            printf("delete failed: %s\n", err.localizedDescription.UTF8String);
        } else {
            printf("kernelcache removed\n");
        }
    }

    [defaults removeObjectForKey:kkerncachekey];
    [defaults removeObjectForKey:kkernprockey];
    [defaults removeObjectForKey:kallprockey];
    [defaults removeObjectForKey:krootvnodekey];
    [defaults removeObjectForKey:kkernprocsize];
    [defaults synchronize];
}
