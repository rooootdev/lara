//
//  fetchkcache.swift
//  lara
//
//  Created by ruter on 12.05.26.
//

import Foundation

func syskcpath() -> String? {
    guard let hash = getbmhash() else { return nil }
    return "/private/preboot/\(hash)/System/Library/Caches/com.apple.kernelcaches/kernelcache"
}

func larakcpath() -> String? {
    guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
    return docs.appendingPathComponent("kernelcache").path
}

func fetchkcache() -> Bool {
    guard ds_is_ready(),
          ds_get_our_proc() != 0,
          ds_get_our_task() != 0,
          off_proc_p_fd != 0,
          off_filedesc_fd_ofiles != 0,
          off_fileproc_fp_glob != 0,
          off_fileglob_fg_data != 0,
          off_vnode_v_data != 0,
          off_namecache_nc_vp != 0,
          off_namecache_nc_child_tqe_next != 0 else {
        globallogger.log("(fetchkcache) exploit, self proc/task, or offsets not ready")
        return false
    }

    guard let kcpath = syskcpath() else {
        globallogger.log("(fetchkcache) failed to get kernelcache path")
        return false
    }

    guard let outpath = larakcpath() else {
        globallogger.log("(fetchkcache) failed to get output path")
        return false
    }

    let fakeread = "/private/preboot/Cryptexes/OS/System/Library/CoreServices/RestoreVersion.plist"

    unlink(outpath)

    var ogvn: UInt64 = 0
    var ogvd: UInt64 = 0

    let redirect = kcpath.withCString { kcCString in
        vn_fileredirect(fakeread, kcCString, &ogvn, &ogvd)
    }
    if !redirect {
        globallogger.log("(fetchkcache) failed to redirect vnode")
        return false
    }

    let src = open(fakeread, O_RDONLY)
    if src < 0 {
        vn_fileunredirect(ogvn, ogvd)
        return false
    }

    let dst = open(outpath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    if dst < 0 {
        close(src)
        vn_fileunredirect(ogvn, ogvd)
        return false
    }

    defer {
        close(src)
        close(dst)
        vn_fileunredirect(ogvn, ogvd)
    }

    var buffer = [UInt8](repeating: 0, count: 0x4000)
    let bufferSize = buffer.count
    var totalBytes = 0

    while true {
        let n = buffer.withUnsafeMutableBytes { rawBuffer in
            read(src, rawBuffer.baseAddress!, bufferSize)
        }

        if n < 0 {
            globallogger.log("(fetchkcache) failed to read kernelcache")
            return false
        }

        if n == 0 {
            break
        }

        var written = 0
        while written < n {
            let w = buffer.withUnsafeBytes { rawBuffer in
                write(dst, rawBuffer.baseAddress!.advanced(by: written), n - written)
            }

            if w <= 0 {
                globallogger.log("(fetchkcache) failed to write kernelcache")
                return false
            }

            written += w
        }

        totalBytes += n
    }

    if !FileManager.default.fileExists(atPath: outpath) || totalBytes == 0 {
        globallogger.log("(fetchkcache) kernelcache output missing")
        return false
    }

    guard let handle = FileHandle(forReadingAtPath: outpath) else {
        globallogger.log("(fetchkcache) kernelcache output missing")
        return false
    }

    let magic = handle.readData(ofLength: 2)
    handle.closeFile()

    guard magic.count == 2, magic[magic.startIndex] == 0x30, magic[magic.index(after: magic.startIndex)] == 0x84 else {
        unlink(outpath)
        globallogger.log("(fetchkcache) invalid kernelcache output")
        return false
    }

    globallogger.log("(fetchkcache) kernelcache fetch success!")
    return true
}
