//
//  zipmgr.swift
//  lara
//
//  Created by neonmodder123 on 17/05/2026.
//

import Foundation
import zlib

private let crcTable: [UInt32] = [
    0x00000000, 0x77073096, 0xee0e612c, 0x990951ba, 0x076dc419, 0x706af48f, 0xe963a535, 0x9e6495a3, 0x0edb8832,
    0x79dcb8a4, 0xe0d5e91e, 0x97d2d988, 0x09b64c2b, 0x7eb17cbd, 0xe7b82d07, 0x90bf1d91, 0x1db71064, 0x6ab020f2,
    0xf3b97148, 0x84be41de, 0x1adad47d, 0x6ddde4eb, 0xf4d4b551, 0x83d385c7, 0x136c9856, 0x646ba8c0, 0xfd62f97a,
    0x8a65c9ec, 0x14015c4f, 0x63066cd9, 0xfa0f3d63, 0x8d080df5, 0x3b6e20c8, 0x4c69105e, 0xd56041e4, 0xa2677172,
    0x3c03e4d1, 0x4b04d447, 0xd20d85fd, 0xa50ab56b, 0x35b5a8fa, 0x42b2986c, 0xdbbbc9d6, 0xacbcf940, 0x32d86ce3,
    0x45df5c75, 0xdcd60dcf, 0xabd13d59, 0x26d930ac, 0x51de003a, 0xc8d75180, 0xbfd06116, 0x21b4f4b5, 0x56b3c423,
    0xcfba9599, 0xb8bda50f, 0x2802b89e, 0x5f058808, 0xc60cd9b2, 0xb10be924, 0x2f6f7c87, 0x58684c11, 0xc1611dab,
    0xb6662d3d, 0x76dc4190, 0x01db7106, 0x98d220bc, 0xefd5102a, 0x71b18589, 0x06b6b51f, 0x9fbfe4a5, 0xe8b8d433,
    0x7807c9a2, 0x0f00f934, 0x9609a88e, 0xe10e9818, 0x7f6a0dbb, 0x086d3d2d, 0x91646c97, 0xe6635c01, 0x6b6b51f4,
    0x1c6c6162, 0x856530d8, 0xf262004e, 0x6c0695ed, 0x1b01a57b, 0x8208f4c1, 0xf50fc457, 0x65b0d9c6, 0x12b7e950,
    0x8bbeb8ea, 0xfcb9887c, 0x62dd1ddf, 0x15da2d49, 0x8cd37cf3, 0xfbd44c65, 0x4db26158, 0x3ab551ce, 0xa3bc0074,
    0xd4bb30e2, 0x4adfa541, 0x3dd895d7, 0xa4d1c46d, 0xd3d6f4fb, 0x4369e96a, 0x346ed9fc, 0xad678846, 0xda60b8d0,
    0x44042d73, 0x33031de5, 0xaa0a4c5f, 0xdd0d7cc9, 0x5005713c, 0x270241aa, 0xbe0b1010, 0xc90c2086, 0x5768b525,
    0x206f85b3, 0xb966d409, 0xce61e49f, 0x5edef90e, 0x29d9c998, 0xb0d09822, 0xc7d7a8b4, 0x59b33d17, 0x2eb40d81,
    0xb7bd5c3b, 0xc0ba6cad, 0xedb88320, 0x9abfb3b6, 0x03b6e20c, 0x74b1d29a, 0xead54739, 0x9dd277af, 0x04db2615,
    0x73dc1683, 0xe3630b12, 0x94643b84, 0x0d6d6a3e, 0x7a6a5aa8, 0xe40ecf0b, 0x9309ff9d, 0x0a00ae27, 0x7d079eb1,
    0xf00f9344, 0x8708a3d2, 0x1e01f268, 0x6906c2fe, 0xf762575d, 0x806567cb, 0x196c3671, 0x6e6b06e7, 0xfed41b76,
    0x89d32be0, 0x10da7a5a, 0x67dd4acc, 0xf9b9df6f, 0x8ebeeff9, 0x17b7be43, 0x60b08ed5, 0xd6d6a3e8, 0xa1d1937e,
    0x38d8c2c4, 0x4fdff252, 0xd1bb67f1, 0xa6bc5767, 0x3fb506dd, 0x48b2364b, 0xd80d2bda, 0xaf0a1b4c, 0x36034af6,
    0x41047a60, 0xdf60efc3, 0xa867df55, 0x316e8eef, 0x4669be79, 0xcb61b38c, 0xbc66831a, 0x256fd2a0, 0x5268e236,
    0xcc0c7795, 0xbb0b4703, 0x220216b9, 0x5505262f, 0xc5ba3bbe, 0xb2bd0b28, 0x2bb45a92, 0x5cb36a04, 0xc2d7ffa7,
    0xb5d0cf31, 0x2cd99e8b, 0x5bdeae1d, 0x9b64c2b0, 0xec63f226, 0x756aa39c, 0x026d930a, 0x9c0906a9, 0xeb0e363f,
    0x72076785, 0x05005713, 0x95bf4a82, 0xe2b87a14, 0x7bb12bae, 0x0cb61b38, 0x92d28e9b, 0xe5d5be0d, 0x7cdcefb7,
    0x0bdbdf21, 0x86d3d2d4, 0xf1d4e242, 0x68ddb3f8, 0x1fda836e, 0x81be16cd, 0xf6b9265b, 0x6fb077e1, 0x18b74777,
    0x88085ae6, 0xff0f6a70, 0x66063bca, 0x11010b5c, 0x8f659eff, 0xf862ae69, 0x616bffd3, 0x166ccf45, 0xa00ae278,
    0xd70dd2ee, 0x4e048354, 0x3903b3c2, 0xa7672661, 0xd06016f7, 0x4969474d, 0x3e6e77db, 0xaed16a4a, 0xd9d65adc,
    0x40df0b66, 0x37d83bf0, 0xa9bcae53, 0xdebb9ec5, 0x47b2cf7f, 0x30b5ffe9, 0xbdbdf21c, 0xcabac28a, 0x53b39330,
    0x24b4a3a6, 0xbad03605, 0xcdd70693, 0x54de5729, 0x23d967bf, 0xb3667a2e, 0xc4614ab8, 0x5d681b02, 0x2a6f2b94,
    0xb40bbe37, 0xc30c8ea1, 0x5a05df1b, 0x2d02ef8d]

extension Data {
    var zipCRC32: UInt32 {
        let mask: UInt32 = 0xffffffff
        var result = mask
        crcTable.withUnsafeBufferPointer { table in
            self.withUnsafeBytes { buf in
                for i in 0..<self.count {
                    let byte = buf[i]
                    let idx = Int((result ^ UInt32(byte)) & 0xff)
                    result = (result >> 8) ^ table[idx]
                }
            }
        }
        return result ^ mask
    }
}

extension Data {
    func scan<T>(at offset: Int) -> T {
        self.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
    }
}

private let cp437Table: [UInt8: String] = [
    0x80: "Ç", 0x81: "ü", 0x82: "é", 0x83: "â", 0x84: "ä", 0x85: "à", 0x86: "å", 0x87: "ç",
    0x88: "ê", 0x89: "ë", 0x8a: "è", 0x8b: "ï", 0x8c: "î", 0x8d: "ì", 0x8e: "Ä", 0x8f: "Å",
    0x90: "É", 0x91: "æ", 0x92: "Æ", 0x93: "ô", 0x94: "ö", 0x95: "ò", 0x96: "û", 0x97: "ù",
    0x98: "ÿ", 0x99: "Ö", 0x9a: "Ü", 0x9b: "ø", 0x9c: "£", 0x9d: "Ø", 0x9e: "₧", 0x9f: "ƒ",
    0xa0: "á", 0xa1: "í", 0xa2: "ó", 0xa3: "ú", 0xa4: "ñ", 0xa5: "Ñ", 0xa6: "ª", 0xa7: "º",
    0xa8: "¿", 0xa9: "⌐", 0xaa: "¬", 0xab: "½", 0xac: "¼", 0xad: "¡", 0xae: "«", 0xaf: "»",
    0xb0: "░", 0xb1: "▒", 0xb2: "▓", 0xb3: "│", 0xb4: "┤", 0xb5: "╡", 0xb6: "╢", 0xb7: "╖",
    0xb8: "╕", 0xb9: "╣", 0xba: "║", 0xbb: "╗", 0xbc: "╝", 0xbd: "╜", 0xbe: "╛", 0xbf: "┐",
    0xc0: "└", 0xc1: "┴", 0xc2: "┬", 0xc3: "├", 0xc4: "─", 0xc5: "┼", 0xc6: "╞", 0xc7: "╟",
    0xc8: "╚", 0xc9: "╔", 0xca: "╩", 0xcb: "╦", 0xcc: "╠", 0xcd: "═", 0xce: "╬", 0xcf: "╧",
    0xd0: "╨", 0xd1: "╤", 0xd2: "╥", 0xd3: "╙", 0xd4: "╘", 0xd5: "╒", 0xd6: "╓", 0xd7: "╫",
    0xd8: "╪", 0xd9: "┘", 0xda: "┌", 0xdb: "█", 0xdc: "▄", 0xdd: "▌", 0xde: "▐", 0xdf: "▀",
    0xe0: "α", 0xe1: "ß", 0xe2: "Γ", 0xe3: "π", 0xe4: "Σ", 0xe5: "σ", 0xe6: "µ", 0xe7: "τ",
    0xe8: "Φ", 0xe9: "Θ", 0xea: "Ω", 0xeb: "δ", 0xec: "∞", 0xed: "φ", 0xee: "ε", 0xef: "∩",
    0xf0: "≡", 0xf1: "±", 0xf2: "≥", 0xf3: "≤", 0xf4: "⌠", 0xf5: "⌡", 0xf6: "÷", 0xf7: "≈",
    0xf8: "°", 0xf9: "∙", 0xfa: "·", 0xfb: "√", 0xfc: "ⁿ", 0xfd: "²", 0xfe: "■", 0xff: " "
]

extension String {
    init(cp437 data: Data) {
        var result = ""
        result.reserveCapacity(data.count)
        for byte in data {
            if byte < 0x80 {
                result.append(Character(UnicodeScalar(byte)))
            } else {
                result.append(cp437Table[byte] ?? "?")
            }
        }
        self = result
    }
}

private let eocdSignature: UInt32 = 0x06054b50
private let cdSignature: UInt32 = 0x02014b50
private let lfhSignature: UInt32 = 0x04034b50
private let zip64EOCDLocatorSignature: UInt32 = 0x07064b50
private let zip64EOCDRecordSignature: UInt32 = 0x06064b50

public struct ZipEntry {
    public let path: String
    public let compressionMethod: UInt16
    public let compressedSize: UInt64
    public let uncompressedSize: UInt64
    public let crc32: UInt32
    public let dataOffset: UInt64
    public let isDirectory: Bool
}

public enum ZipError: Error {
    case notFound(String)
    case corruptArchive(String)
    case unsupportedCompression
    case crcMismatch
}

public class ZipArchive {
    private let data: Data
    public private(set) var entries: [ZipEntry] = []
    private var entryMap: [String: ZipEntry]
    private let mgr = laramgr.shared
    private var error = ""

    public init(data: Data) throws {
        self.data = data
        self.entryMap = [:]
        try scanEntries()
        var map: [String: ZipEntry] = [:]
        for entry in entries {
            map[entry.path] = entry
        }
        self.entryMap = map
    }

    public subscript(path: String) -> ZipEntry? { entryMap[path] }

    public func extract(_ entry: ZipEntry) throws -> Data {
        let end = entry.dataOffset + entry.compressedSize
        guard entry.dataOffset < UInt64(data.count),
              end <= data.count else {
            error = "(zip) entry data out of bounds"
            mgr.logmsg("\(error)")
            throw ZipError.corruptArchive("\(error)")
        }

        switch entry.compressionMethod {
        case 0:
            let raw = data.subdata(in: Int(entry.dataOffset)..<Int(end))
            guard raw.zipCRC32 == entry.crc32 else {
                error = "(zip) crc mismatch"
                mgr.logmsg("\(error)")
                throw ZipError.crcMismatch
            }
            return raw
        case 8:
            let raw = data.subdata(in: Int(entry.dataOffset)..<Int(end))
            let decompressed = try decompressDeflate(raw, decompressedSize: Int(entry.uncompressedSize))
            guard decompressed.zipCRC32 == entry.crc32 else {
                error = "(zip) crc mismatch"
                mgr.logmsg("\(error)")
                throw ZipError.crcMismatch
            }
            return decompressed
        default:
            error = "(zip) unsupported compression, not a valid .zip"
            mgr.logmsg("\(error)")
            throw ZipError.unsupportedCompression
        }
    }

    private func scanEntries() throws {
        guard data.count >= 22 else {
            error = "(zip) too small"
            mgr.logmsg("\(error)")
            throw ZipError.corruptArchive("\(error)")
        }

        let (eocdOffset, _) = try locateEOCD()
        let cdOffset: UInt64
        let cdSize: UInt64
        let totalEntries: UInt64

        let cdOffset32: UInt32 = data.scan(at: eocdOffset + 16)
        let cdSize32: UInt32 = data.scan(at: eocdOffset + 12)
        let totalEntries16: UInt16 = data.scan(at: eocdOffset + 10)

        if cdOffset32 == UInt32.max || cdSize32 == UInt32.max || totalEntries16 == UInt16.max {
            let (z64off, z64rec) = try locateZIP64EOCD(eocdOffset: eocdOffset)
            cdOffset = z64rec.isEmpty ? UInt64(cdOffset32) : z64rec.scan(at: 48) as UInt64
            cdSize = z64rec.isEmpty ? UInt64(cdSize32) : z64rec.scan(at: 40) as UInt64
            totalEntries = z64rec.isEmpty ? UInt64(totalEntries16) : z64rec.scan(at: 32) as UInt64
        } else {
            cdOffset = UInt64(cdOffset32)
            cdSize = UInt64(cdSize32)
            totalEntries = UInt64(totalEntries16)
        }

        guard cdOffset + cdSize <= UInt64(data.count) else {
            error = "(zip) cd out of bounds"
            mgr.logmsg("\(error)")
            throw ZipError.corruptArchive("\(error)")
        }

        var pos = Int(cdOffset)
        for _ in 0..<totalEntries {
            guard pos + 46 <= data.count else {
                error = "(zip) cd entry truncated"
                mgr.logmsg("\(error)")
                throw ZipError.corruptArchive("\(error)")
            }
            let sig: UInt32 = data.scan(at: pos)
            guard sig == cdSignature else {
                error = "(zip) bad cd sig"
                mgr.logmsg("\(error)")
                throw ZipError.corruptArchive("\(error)")
            }

            let compMethod: UInt16 = data.scan(at: pos + 10)
            let crc: UInt32 = data.scan(at: pos + 16)
            let csize32: UInt32 = data.scan(at: pos + 20)
            let usize32: UInt32 = data.scan(at: pos + 24)
            let nameLen: UInt16 = data.scan(at: pos + 28)
            let extraLen: UInt16 = data.scan(at: pos + 30)
            let commentLen: UInt16 = data.scan(at: pos + 32)
            let lfhOffset32: UInt32 = data.scan(at: pos + 42)

            let nameData = data.subdata(in: pos + 46..<pos + 46 + Int(nameLen))
            let extraData = data.subdata(in: pos + 46 + Int(nameLen)..<pos + 46 + Int(nameLen) + Int(extraLen))
            let flags: UInt16 = data.scan(at: pos + 8)

            let usesUTF8 = (flags & (1 << 11)) != 0
            let path: String = usesUTF8 ? (String(data: nameData, encoding: .utf8) ?? String(cp437: nameData)) : String(cp437: nameData)

            let csize: UInt64
            let usize: UInt64
            let lfhOff: UInt64

            if csize32 == UInt32.max || usize32 == UInt32.max || lfhOffset32 == UInt32.max {
                let fields = parseZIP64Extra(extraData)
                csize = fields.compressedSize ?? UInt64(csize32)
                usize = fields.uncompressedSize ?? UInt64(usize32)
                lfhOff = fields.relativeOffset ?? UInt64(lfhOffset32)
            } else {
                csize = UInt64(csize32)
                usize = UInt64(usize32)
                lfhOff = UInt64(lfhOffset32)
            }

            let isDir = path.hasSuffix("/") || ((data.scan(at: pos + 38) as UInt32 >> 4) & 1) != 0
            let dataOff = try computeDataOffset(lfhOffset: lfhOff)

            entries.append(ZipEntry(
                path: path,
                compressionMethod: compMethod,
                compressedSize: csize,
                uncompressedSize: usize,
                crc32: crc,
                dataOffset: dataOff,
                isDirectory: isDir
            ))

            pos += 46 + Int(nameLen) + Int(extraLen) + Int(commentLen)
        }
    }

    private func computeDataOffset(lfhOffset: UInt64) throws -> UInt64 {
        let off = Int(lfhOffset)
        guard off + 30 <= data.count else {
            error = "(zip) lfh truncated"
            mgr.logmsg("\(error)")
            throw ZipError.corruptArchive("\(error)")
        }
        let sig: UInt32 = data.scan(at: off)
        guard sig == lfhSignature else {
            error = "(zip) bad lfh sig"
            mgr.logmsg("\(error)")
            throw ZipError.corruptArchive("\(error)")
        }
        let nameLen: UInt16 = data.scan(at: off + 26)
        let extraLen: UInt16 = data.scan(at: off + 28)
        return lfhOffset + 30 + UInt64(nameLen) + UInt64(extraLen)
    }

    private func decompressDeflate(_ compressed: Data, decompressedSize: Int) throws -> Data {
        var result = Data(count: decompressedSize)
        var actualSize: Int = 0

        let status: Int32 = result.withUnsafeMutableBytes { destBuf in
            compressed.withUnsafeBytes { srcBuf in
                guard let dest = destBuf.baseAddress,
                      let src  = srcBuf.baseAddress else { return Z_BUF_ERROR }

                var stream = z_stream()
                stream.next_in   = UnsafeMutablePointer<Bytef>(mutating: src.assumingMemoryBound(to: Bytef.self))
                stream.avail_in  = uInt(compressed.count)
                stream.next_out  = dest.assumingMemoryBound(to: Bytef.self)
                stream.avail_out = uInt(decompressedSize)

                var ret = inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
                guard ret == Z_OK else { return ret }
                ret = inflate(&stream, Z_FINISH)
                actualSize = decompressedSize - Int(stream.avail_out)
                inflateEnd(&stream)
                return ret
            }
        }

        guard status == Z_STREAM_END else {
            error = "(zip) raw deflate failed with zlib status \(status)"
            mgr.logmsg("\(error)")
            throw ZipError.corruptArchive("\(error)")
        }
        return result.prefix(actualSize)
    }

    private func locateEOCD() throws -> (offset: Int, commentLen: Int) {
        let searchStart = max(0, data.count - 65557)
        for i in (searchStart..<data.count - 3).reversed() {
            let sig: UInt32 = data.scan(at: i)
            if sig == eocdSignature {
                let commentLen: UInt16 = data.scan(at: i + 20)
                return (i, Int(commentLen))
            }
        }
        error = "(zip) no eocd"
        mgr.logmsg("\(error)")
        throw ZipError.corruptArchive("\(error)")
    }

    private func locateZIP64EOCD(eocdOffset: Int) throws -> (offset: Int, recordData: Data) {
        let locatorOff = eocdOffset - 20
        guard locatorOff >= 0 else { return (0, Data()) }
        let sig: UInt32 = data.scan(at: locatorOff)
        guard sig == zip64EOCDLocatorSignature else { return (0, Data()) }
        let z64Off: UInt64 = data.scan(at: locatorOff + 8)

        guard z64Off < UInt64(data.count) - 56 else { return (0, Data()) }
        let recSig: UInt32 = data.scan(at: Int(z64Off))
        guard recSig == zip64EOCDRecordSignature else { return (0, Data()) }
        let recSize: UInt64 = data.scan(at: Int(z64Off) + 4)
        let totalSize = Int(recSize) + 12
        guard Int(z64Off) + totalSize <= data.count else { return (0, Data()) }
        let recData = data.subdata(in: Int(z64Off)..<Int(z64Off) + totalSize)
        return (Int(z64Off), recData)
    }

    private struct ZIP64Fields {
        var uncompressedSize: UInt64?
        var compressedSize: UInt64?
        var relativeOffset: UInt64?
    }

    private func parseZIP64Extra(_ extra: Data) -> ZIP64Fields {
        var offset = 0
        while offset + 4 <= extra.count {
            let id: UInt16 = extra.scan(at: offset)
            let size: UInt16 = extra.scan(at: offset + 2)
            let fieldEnd = offset + 4 + Int(size)
            guard fieldEnd <= extra.count else { break }
            if id == 0x0001 {
                var fields = ZIP64Fields()
                var readOff = offset + 4
                if readOff + 8 <= fieldEnd {
                    fields.uncompressedSize = extra.scan(at: readOff)
                    readOff += 8
                }
                if readOff + 8 <= fieldEnd {
                    fields.compressedSize = extra.scan(at: readOff)
                    readOff += 8
                }
                if readOff + 8 <= fieldEnd {
                    fields.relativeOffset = extra.scan(at: readOff)
                    readOff += 8
                }
                return fields
            }
            offset = fieldEnd
        }
        return ZIP64Fields()
    }

    private static let lfhSize = 30
}

private func writeLE16(_ value: UInt16, to data: inout Data) {
    withUnsafeBytes(of: value) { data.append(contentsOf: $0) }
}

private func writeLE32(_ value: UInt32, to data: inout Data) {
    withUnsafeBytes(of: value) { data.append(contentsOf: $0) }
}

private func crc32OfFile(at url: URL) -> (crc: UInt32, data: Data) {
    let data = (try? Data(contentsOf: url)) ?? Data()
    return (data.zipCRC32, data)
}

public func createZipArchive(fromDirectory sourceURL: URL, to destinationURL: URL, compressionMethod: UInt16 = 0) throws {
    let mgr = laramgr.shared
    var error = ""
    let fm = FileManager.default
    var fileEntries: [(name: String, data: Data, crc32: UInt32)] = []
    var dirEntries: [String] = []

    let resolvedSource = sourceURL.resolvingSymlinksInPath()

    guard let enumerator = fm.enumerator(at: sourceURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
        error = "(zip) cannot enumerate source directory"
        mgr.logmsg("\(error)")
        throw ZipError.corruptArchive("\(error)")
    }

    for case let fileURL as URL in enumerator {
        let resolvedFile = fileURL.resolvingSymlinksInPath()
        guard let relRange = resolvedFile.path.range(of: resolvedSource.path + "/") else { continue }
        let relPath = String(resolvedFile.path[relRange.upperBound...])
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: fileURL.path, isDirectory: &isDir) else { continue }

        if isDir.boolValue {
            dirEntries.append(relPath + "/")
        } else {
            let (crc, data) = crc32OfFile(at: fileURL)
            fileEntries.append((relPath, data, crc))
        }
    }

    guard fm.createFile(atPath: destinationURL.path, contents: nil, attributes: nil) else {
        error = "(zip) cannot create output file"
        mgr.logmsg("\(error)")
        throw ZipError.corruptArchive("\(error)")
    }
    let fh = try FileHandle(forWritingTo: destinationURL)
    defer { try? fh.close() }

    var localOffsets: [UInt32] = []
    var cdEntries: [Data] = []

    for entry in fileEntries {
        let nameData = entry.name.data(using: .utf8)!
        let nameLen = UInt16(nameData.count)
        let offset = UInt32(try fh.offset())

        var lfh = Data()
        writeLE32(lfhSignature, to: &lfh)
        writeLE16(20, to: &lfh)
        writeLE16(0, to: &lfh)
        writeLE16(0, to: &lfh)
        writeLE16(0, to: &lfh)
        writeLE16(0, to: &lfh)
        writeLE32(entry.crc32, to: &lfh)
        writeLE32(UInt32(entry.data.count), to: &lfh)
        writeLE32(UInt32(entry.data.count), to: &lfh)
        writeLE16(nameLen, to: &lfh)
        writeLE16(0, to: &lfh)
        try fh.write(contentsOf: lfh)
        try fh.write(contentsOf: nameData)
        try fh.write(contentsOf: entry.data)

        var cd = Data()
        writeLE32(cdSignature, to: &cd)
        writeLE16(20, to: &cd)
        writeLE16(20, to: &cd)
        writeLE16(0, to: &cd)
        writeLE16(0, to: &cd)
        writeLE16(0, to: &cd)
        writeLE16(0, to: &cd)
        writeLE32(entry.crc32, to: &cd)
        writeLE32(UInt32(entry.data.count), to: &cd)
        writeLE32(UInt32(entry.data.count), to: &cd)
        writeLE16(nameLen, to: &cd)
        writeLE16(0, to: &cd)
        writeLE16(0, to: &cd)
        writeLE16(0, to: &cd)
        writeLE16(0, to: &cd)
        writeLE32(0x81A40000, to: &cd)
        writeLE32(offset, to: &cd)
        cd.append(nameData)

        localOffsets.append(offset)
        cdEntries.append(cd)
    }

    for dirName in dirEntries {
        let nameData = dirName.data(using: .utf8)!
        let nameLen = UInt16(nameData.count)
        let offset = UInt32(try fh.offset())

        var lfh = Data()
        writeLE32(lfhSignature, to: &lfh)
        writeLE16(20, to: &lfh)
        writeLE16(0, to: &lfh)
        writeLE16(0, to: &lfh)
        writeLE16(0, to: &lfh)
        writeLE16(0, to: &lfh)
        writeLE32(0, to: &lfh)
        writeLE32(0, to: &lfh)
        writeLE32(0, to: &lfh)
        writeLE16(nameLen, to: &lfh)
        writeLE16(0, to: &lfh)
        try fh.write(contentsOf: lfh)
        try fh.write(contentsOf: nameData)

        var cd = Data()
        writeLE32(cdSignature, to: &cd)
        writeLE16(20, to: &cd)
        writeLE16(20, to: &cd)
        writeLE16(0, to: &cd)
        writeLE16(0, to: &cd)
        writeLE16(0, to: &cd)
        writeLE16(0, to: &cd)
        writeLE32(0, to: &cd)
        writeLE32(0, to: &cd)
        writeLE32(0, to: &cd)
        writeLE16(nameLen, to: &cd)
        writeLE16(0, to: &cd)
        writeLE16(0, to: &cd)
        writeLE16(0, to: &cd)
        writeLE16(0, to: &cd)
        writeLE32(0x41ED0000, to: &cd)
        writeLE32(offset, to: &cd)
        cd.append(nameData)

        cdEntries.append(cd)
    }

    let cdOffset = UInt32(try fh.offset())
    var cdSize: UInt32 = 0
    for cd in cdEntries {
        try fh.write(contentsOf: cd)
        cdSize += UInt32(cd.count)
    }

    let totalEntries = UInt16(fileEntries.count + dirEntries.count)
    var eocd = Data()
    writeLE32(eocdSignature, to: &eocd)
    writeLE16(0, to: &eocd)
    writeLE16(0, to: &eocd)
    writeLE16(totalEntries, to: &eocd)
    writeLE16(totalEntries, to: &eocd)
    writeLE32(cdSize, to: &eocd)
    writeLE32(cdOffset, to: &eocd)
    writeLE16(0, to: &eocd)
    try fh.write(contentsOf: eocd)
}
