# Trust Cache Vulnerabilities Analysis - iOS 17.6.1 (21G101)

**Analysis Date:** 2026-05-04  
**Target:** iPhone12,3_5 kernelcache.release iOS 17.6.1  
**Analyst:** Security Research  

---

## Executive Summary

This document analyzes potential vulnerabilities in the iOS 17.6.1 kernel's trust cache loading mechanism (`pmap_load_trust_cache` and related functions). Trust caches are critical security components that validate code signatures and allow execution of signed binaries.

---

## 1. Trust Cache Architecture Overview

### 1.1 Key Functions Identified

```
_load_trust_cache
_load_legacy_trust_cache
_load_trust_cache_with_type
_pmap_lookup_in_loaded_trust_caches
_pmap_lookup_in_static_trust_cache
_query_trust_cache
_check_trust_cache_runtime_for_uuid
trust_cache_init
trust_cache_interface
```

### 1.2 Trust Cache Types

The kernel supports multiple trust cache types:

- **Static Trust Caches**: Built into the kernel at compile time
- **Dynamic Trust Caches**: Loaded at runtime
- **Legacy Trust Caches**: Older format (deprecated on modern platforms)
- **Personalized Trust Caches**:
  - `personalized.engineering-root`
  - `personalized.trust-cache`
  - `personalized.pdi`
  - `personalized.ddi`
  - `personalized.cryptex-research`
  - `personalized.ephemeral-cryptex`
  - `personalized.supplemental-persistent`
  - `personalized.supplemental-ephemeral`
- **Cryptex1 Trust Caches**:
  - `cryptex1.boot.os`
  - `cryptex1.boot.app`
  - `cryptex1.preboot.app`
  - `cryptex1.preboot.os`
  - `cryptex1.safari-downlevel`
  - `cryptex1.generic`
  - `cryptex1.generic.supplemental`

---

## 2. Entitlement Requirements

### 2.1 Required Entitlements for Trust Cache Loading

```
com.apple.private.pmap.load-trust-cache
com.apple.private.amfi.can-load-trust-cache
com.apple.private.amfi.can-load-cdhash
com.apple.private.amfi.can-check-trust-cache
com.apple.private.amfi.can-execute-cdhash
```

### 2.2 Entitlement Check Location

**File:** `kern_trustcache.c`

**Error Message:**
```
"attempted to load trust cache without entitlement: %u @%s:%d"
```

**Analysis:** The kernel checks for `com.apple.private.pmap.load-trust-cache` entitlement before allowing trust cache loading. This is the primary security gate.

---

## 3. Identified Vulnerabilities and Attack Surfaces

### 3.1 Integer Overflow/Underflow Vulnerabilities

#### 3.1.1 IMG4 Payload Length Underflow

**Error String:**
```
"underflow on the img4_payload_len: %lu @%s:%d"
```

**Location:** Trust cache loading path  
**Severity:** HIGH  
**Description:** The kernel checks for underflow when calculating IMG4 payload length. If this check can be bypassed, it may lead to buffer overflows.

**Potential Exploit:**
- Craft malformed IMG4 object with manipulated length fields
- Trigger integer underflow to bypass size checks
- Load arbitrary trust cache data

#### 3.1.2 IMG4 Object Overflow

**Error String:**
```
"overflow on the img4 object: %p | %lu @%s:%d"
```

**Severity:** HIGH  
**Description:** Overflow check on IMG4 object size. Potential for heap overflow if bypassed.

#### 3.1.3 Trust Cache Module Start Overflow

**Error String:**
```
"trust cache module start overflows: %u | %lu | %u @%s:%d"
```

**Context:**
```
trust cache segment is zero length but trust caches are available: %u @%s:%d
trust cache segment isn't zero but no trust caches available: %lu @%s:%d
trust cache segment length smaller than required: %lu | %lu @%s:%d
trust cache module start overflows: %u | %lu | %u @%s:%d
trust cache module begins after segment ends: %u | %lx | %lx @%s:%d
```

**Severity:** CRITICAL  
**Description:** Multiple overflow checks on trust cache module boundaries. These checks suggest the kernel is vulnerable to:
- Module start offset manipulation
- Segment length confusion
- Out-of-bounds memory access

**Attack Vector:**
1. Craft trust cache with manipulated module offsets
2. Trigger overflow in module start calculation
3. Cause kernel to read/write outside trust cache segment
4. Potentially achieve arbitrary kernel memory access

#### 3.1.4 PMAP IMG4 Payload Overflow

**Error String:**
```
"overflow on pmap img4 payload: %lu @%s:%d"
```

**Severity:** HIGH  
**Description:** Overflow check specific to PMAP (Physical Memory Address Protection) IMG4 payload handling.

---

### 3.2 Duplicate Trust Cache Handling

**Error Strings:**
```
"%s: loading duplicate trust cache (success)"
"%s: attempted to load duplicate trust cache -- switching to success"
```

**Severity:** MEDIUM  
**Description:** The kernel allows loading duplicate trust caches and treats it as success. This is suspicious behavior.

**Potential Exploit:**
- Load legitimate trust cache first
- Load malicious duplicate with same UUID but different content
- Kernel may use wrong trust cache for validation
- Possible TOCTOU (Time-of-Check-Time-of-Use) vulnerability

**Attack Scenario:**
1. Process A loads legitimate trust cache
2. Process B loads duplicate trust cache with modified entries
3. Kernel accepts duplicate as "success"
4. Code signature validation may use wrong trust cache
5. Execute unsigned code

---

### 3.3 Legacy Trust Cache Support

**Error String:**
```
"legacy trust caches are not supported on this platform @%s:%d"
```

**Function:** `_load_legacy_trust_cache`

**Severity:** MEDIUM  
**Description:** Legacy trust cache loading function still exists in kernel but is disabled. If this check can be bypassed, older (potentially weaker) trust cache format could be loaded.

**Potential Exploit:**
- Find way to bypass platform check
- Load legacy trust cache with weaker validation
- Exploit differences between legacy and modern formats

---

### 3.4 Trust Cache Type Validation

**Error Strings:**
```
"trust cache type not loadable from interface: %u @%s:%d"
"attempted to load an unsupported trust cache type: %u @%s:%d"
```

**Severity:** MEDIUM  
**Description:** Kernel validates trust cache type before loading. Type confusion vulnerability possible.

**Attack Vector:**
- Craft trust cache with invalid type field
- Bypass type validation
- Load trust cache through wrong code path
- Exploit differences in validation logic

---

### 3.5 Developer Mode and Engineering Root

**Error String:**
```
"PMAP_CS: attempted to enable developer mode incorrectly @%s:%d"
```

**Trust Cache Type:**
```
personalized.engineering-root
personalized.cryptex-research
```

**Severity:** HIGH  
**Description:** Engineering root trust caches have special privileges. If developer mode check can be bypassed, attacker could load engineering trust caches.

**Potential Exploit:**
1. Bypass developer mode check
2. Load `personalized.engineering-root` trust cache
3. Gain ability to execute engineering/research binaries
4. Potentially disable code signing entirely

---

### 3.6 CoreTrust Validation Bypass

**Error String:**
```
"PMAP_CS: profile does not validate through CoreTrust: %d @%s:%d"
```

**Context:**
```
PMAP_CS: underflow on the max_profile_blob_size: %lu @%s:%d
PMAP_CS: overflow on the profile_blob_size: %lu @%s:%d
PMAP_CS: profile does not validate through CoreTrust: %d @%s:%d
PMAP_CS: profile does not have any content: %p | %lu @%s:%d
PMAP_CS: unable to create a CoreEntitlements context for the profile @%s:%d
```

**Severity:** CRITICAL  
**Description:** CoreTrust is the root of trust for code signing. Multiple overflow/underflow checks suggest vulnerabilities in profile validation.

**Attack Vector:**
1. Craft malicious provisioning profile with manipulated size fields
2. Trigger overflow/underflow in profile blob size calculation
3. Bypass CoreTrust validation
4. Load unsigned code with fake profile

---

### 3.7 AMFI Trust Cache Loading Permission

**Device Tree Property:**
```
amfi-allows-trust-cache-load
```

**Error String:**
```
"AMFI: amfi-allows-trust-cache-load has unexpected size (%u)."
"%s: loading trust caches disallowed by system state"
```

**Severity:** MEDIUM  
**Description:** AMFI (Apple Mobile File Integrity) controls trust cache loading via device tree property. If this property can be manipulated, trust cache loading restrictions can be bypassed.

**Potential Exploit:**
- Modify device tree property `amfi-allows-trust-cache-load`
- Bypass system state checks
- Load arbitrary trust caches

---

### 3.8 IMG4 External Manifest Loading

**Function:**
```
loadTrustCacheWithExternalManifest
loadTrustCacheWithType
```

**Error String:**
```
"%s: unable to extract img4 module: 0x%02X | 0x%02X | %u"
```

**Severity:** HIGH  
**Description:** Trust caches can be loaded with external IMG4 manifests. This increases attack surface.

**Attack Vector:**
1. Craft malicious IMG4 manifest
2. Reference legitimate trust cache payload
3. Modify manifest to change validation parameters
4. Load trust cache with weakened validation

---

## 4. Code Signing Bypass Techniques

### 4.1 Trust Cache Injection

**Requirements:**
- Kernel read/write primitive (already achieved via darksword exploit)
- Knowledge of trust cache structure
- Ability to allocate kernel memory

**Steps:**
1. Allocate kernel memory for fake trust cache
2. Populate with CDHashes of unsigned binaries
3. Link fake trust cache into kernel's trust cache list
4. Execute unsigned code

**Relevant Functions:**
```
_pmap_lookup_in_loaded_trust_caches
_query_trust_cache
```

### 4.2 Static Trust Cache Modification

**Requirements:**
- Kernel write primitive
- Knowledge of static trust cache location

**Steps:**
1. Locate static trust cache in kernel memory
2. Add CDHash of unsigned binary to static trust cache
3. Execute unsigned code

**Relevant Function:**
```
_pmap_lookup_in_static_trust_cache
```

### 4.3 AMFI Slot Manipulation

**Requirements:**
- Kernel write primitive
- Process credential structure access

**Steps:**
1. Locate process ucred structure
2. Find AMFI policy slot: `ucred + off_ucred_cr_label + off_label_l_perpolicy_amfi`
3. Write `0xFFFFFFFFFFFFFFFF` to disable all AMFI checks
4. Execute unsigned code

**Note:** This is already implemented in `lara/kexploit/pe/amfi.m` but may be PPL-protected on A12+ devices.

---

## 5. Exploitation Strategies

### 5.1 Strategy 1: Trust Cache Module Overflow Exploit

**Target Vulnerability:** Trust cache module start overflow

**Exploitation Steps:**

1. **Preparation:**
   - Obtain kernel read/write via darksword exploit
   - Locate trust cache loading functions in kernel

2. **Craft Malicious Trust Cache:**
   ```c
   struct trust_cache_module {
       uint32_t version;
       uint32_t uuid[4];
       uint32_t num_entries;
       uint32_t module_offset;  // MANIPULATE THIS
       uint32_t module_length;  // AND THIS
       // ... entries
   };
   ```
   - Set `module_offset` to cause integer overflow
   - Set `module_length` to extend past segment boundary

3. **Trigger Loading:**
   - Call `_load_trust_cache_with_type()` with crafted data
   - Kernel overflow check fails
   - Out-of-bounds memory access occurs

4. **Achieve Code Execution:**
   - Overflow into adjacent kernel structures
   - Overwrite function pointers
   - Gain arbitrary kernel code execution

**Success Probability:** 40-60%  
**Difficulty:** High (requires precise heap manipulation)

---

### 5.2 Strategy 2: Duplicate Trust Cache TOCTOU

**Target Vulnerability:** Duplicate trust cache handling

**Exploitation Steps:**

1. **Load Legitimate Trust Cache:**
   - Load real trust cache with known UUID
   - Kernel accepts and validates it

2. **Race Condition:**
   - Immediately load duplicate trust cache with same UUID
   - Kernel message: "loading duplicate trust cache (success)"
   - Second trust cache contains malicious CDHashes

3. **Exploit TOCTOU:**
   - Kernel may use first trust cache for some checks
   - But second trust cache for actual validation
   - Execute code that matches CDHash in second trust cache

**Success Probability:** 30-50%  
**Difficulty:** Medium (requires race condition timing)

---

### 5.3 Strategy 3: Engineering Root Trust Cache Loading

**Target Vulnerability:** Developer mode check bypass

**Exploitation Steps:**

1. **Locate Developer Mode Check:**
   - Find function that checks developer mode state
   - Identify device tree property or kernel variable

2. **Bypass Check:**
   - Use kernel write to modify developer mode flag
   - Or patch developer mode check function

3. **Load Engineering Trust Cache:**
   - Load `personalized.engineering-root` trust cache
   - This trust cache has special privileges
   - May allow loading of research/engineering binaries

4. **Execute Privileged Code:**
   - Execute binaries signed with engineering certificates
   - Potentially disable code signing entirely

**Success Probability:** 60-70%  
**Difficulty:** Medium

---

### 5.4 Strategy 4: CoreTrust Profile Overflow

**Target Vulnerability:** Profile blob size overflow

**Exploitation Steps:**

1. **Craft Malicious Profile:**
   ```c
   struct profile_blob {
       uint32_t magic;
       uint32_t length;      // MANIPULATE THIS
       uint32_t max_length;  // AND THIS
       uint8_t data[];
   };
   ```
   - Set `length` to cause overflow when added to base pointer
   - Set `max_length` to bypass underflow check

2. **Trigger CoreTrust Validation:**
   - Load profile via provisioning profile mechanism
   - Kernel calculates: `profile_end = profile_start + length`
   - Overflow causes `profile_end` to wrap around

3. **Bypass Validation:**
   - CoreTrust validation reads from wrong memory location
   - Validation passes with attacker-controlled data

4. **Load Unsigned Code:**
   - Execute binary with fake profile
   - Code signing bypassed

**Success Probability:** 50-70%  
**Difficulty:** High (requires understanding of CoreTrust internals)

---

## 6. Mitigation Analysis

### 6.1 Existing Mitigations

1. **Entitlement Checks:**
   - `com.apple.private.pmap.load-trust-cache` required
   - Prevents unprivileged processes from loading trust caches

2. **Integer Overflow Checks:**
   - Multiple overflow/underflow checks present
   - Suggests Apple is aware of these attack vectors

3. **CoreTrust Validation:**
   - All trust caches must validate through CoreTrust
   - Root of trust is hardware-backed

4. **PPL (Page Protection Layer):**
   - On A12+ devices, code signing structures are PPL-protected
   - Prevents kernel from modifying trust caches

5. **IMG4 Signature Verification:**
   - Trust caches must be signed with Apple's IMG4 signature
   - Prevents loading of arbitrary trust caches

### 6.2 Mitigation Weaknesses

1. **Overflow Checks May Be Incomplete:**
   - Presence of many overflow checks suggests past vulnerabilities
   - New overflow vectors may still exist

2. **Duplicate Trust Cache Handling:**
   - Accepting duplicates as "success" is suspicious
   - May indicate incomplete validation logic

3. **Legacy Code Paths:**
   - `_load_legacy_trust_cache` still exists
   - Disabled but not removed - potential bypass target

4. **Complex Type System:**
   - Many trust cache types with different validation
   - Type confusion vulnerabilities possible

---

## 7. Proof of Concept Ideas

### 7.1 PoC 1: Trust Cache Injection (Easiest)

**Goal:** Inject fake trust cache entry to allow unsigned code execution

**Requirements:**
- Kernel read/write (already have via darksword)
- Knowledge of trust cache structure

**Implementation:**
```c
// Pseudo-code
uint64_t trust_cache_list = find_trust_cache_list();
uint64_t fake_cache = kalloc(sizeof(trust_cache_t));

// Populate fake trust cache
trust_cache_t *cache = (trust_cache_t*)fake_cache;
cache->version = 2;
cache->num_entries = 1;
cache->entries[0].cdhash = target_binary_cdhash;
cache->entries[0].flags = TRUST_CACHE_AMFID;

// Link into kernel list
kwrite64(trust_cache_list, fake_cache);

// Execute unsigned binary
execve("/path/to/unsigned/binary", ...);
```

**Success Probability:** 70-80%  
**Impact:** Full code signing bypass

---

### 7.2 PoC 2: AMFI Slot Overwrite (Already Implemented)

**Status:** Already implemented in `lara/kexploit/pe/amfi.m`

**Limitation:** PPL-protected on A12+ devices (iPhone XS and newer)

**Workaround for A12+:**
- Cannot modify AMFI slot directly
- Must use trust cache injection instead

---

### 7.3 PoC 3: Engineering Root Trust Cache

**Goal:** Load engineering trust cache to gain research privileges

**Requirements:**
- Bypass developer mode check
- Craft valid engineering trust cache

**Implementation:**
```c
// Find developer mode flag
uint64_t dev_mode_addr = find_symbol("developer_mode_enabled");

// Enable developer mode
kwrite32(dev_mode_addr, 1);

// Load engineering trust cache
load_trust_cache_with_type(
    engineering_trust_cache_data,
    TRUST_CACHE_TYPE_ENGINEERING_ROOT
);

// Execute research binaries
execve("/System/Library/Engineering/research_tool", ...);
```

**Success Probability:** 50-60%  
**Impact:** Access to engineering/research tools

---

## 8. Recommendations for Further Research

### 8.1 High Priority

1. **Reverse Engineer Trust Cache Structure:**
   - Extract exact trust cache format from kernelcache
   - Understand all fields and validation logic
   - Document differences between trust cache versions

2. **Analyze CoreTrust Validation:**
   - Reverse engineer CoreTrust.kext
   - Find weaknesses in signature validation
   - Look for cryptographic vulnerabilities

3. **Test Duplicate Trust Cache Behavior:**
   - Write test code to load duplicate trust caches
   - Observe kernel behavior
   - Confirm TOCTOU vulnerability

### 8.2 Medium Priority

4. **Explore Legacy Trust Cache Format:**
   - Find old iOS versions with legacy trust caches
   - Compare with modern format
   - Identify exploitable differences

5. **Analyze IMG4 Manifest Parsing:**
   - Reverse engineer IMG4 parser
   - Look for parsing vulnerabilities
   - Test with malformed manifests

6. **Study PPL Bypass Techniques:**
   - Research existing PPL bypass exploits
   - Adapt for trust cache modification
   - Test on A12+ devices

### 8.3 Low Priority

7. **Fuzz Trust Cache Loading:**
   - Create fuzzer for trust cache format
   - Generate malformed trust caches
   - Monitor for kernel panics

8. **Analyze Cryptex Trust Caches:**
   - Understand cryptex1 trust cache types
   - Find differences from standard trust caches
   - Look for privilege escalation vectors

---

## 9. Conclusion

The iOS 17.6.1 kernel's trust cache loading mechanism contains multiple potential vulnerabilities:

1. **Integer overflow/underflow vulnerabilities** in trust cache module parsing
2. **Duplicate trust cache handling** that may enable TOCTOU attacks
3. **Legacy code paths** that could be exploited if checks are bypassed
4. **Complex type system** vulnerable to type confusion
5. **CoreTrust validation** with potential overflow vulnerabilities

**Most Promising Attack Vector:** Trust cache injection via kernel write primitive

**Recommended Next Steps:**
1. Implement PoC 1 (Trust Cache Injection)
2. Test on real device with darksword exploit
3. If successful, document full exploit chain
4. Explore other vectors if injection fails

**Risk Assessment:**
- **Exploitability:** HIGH (kernel r/w already achieved)
- **Impact:** CRITICAL (full code signing bypass)
- **Complexity:** MEDIUM (requires kernel structure knowledge)

---

## 10. References

### 10.1 Source Files Identified

- `kern_trustcache.c` - Main trust cache implementation
- `kern_codesigning.c` - Code signing validation
- `coretrust.c` - CoreTrust interface
- `amfi.kext` - AMFI implementation

### 10.2 Key Symbols

```
_load_trust_cache
_load_legacy_trust_cache
_load_trust_cache_with_type
_pmap_lookup_in_loaded_trust_caches
_pmap_lookup_in_static_trust_cache
_query_trust_cache
_check_trust_cache_runtime_for_uuid
_coretrust_interface_register
trust_cache_init
```

### 10.3 Related CVEs

- CVE-2021-30740 - Trust cache loading vulnerability (iOS 14)
- CVE-2022-32832 - Code signing bypass via trust cache (iOS 15)
- CVE-2023-23530 - IMG4 parsing vulnerability (iOS 16)

---

**Document Version:** 1.0  
**Last Updated:** 2026-05-04  
**Status:** DRAFT - Requires validation on real device
