//
//  respringcc.swift
//  lara
//
//  Ported from straight-tamago/RespringCC (MagnifierModule -> CCUIAppLauncherModule).
//

import Foundation

enum respringcc {
    static let moduleBasePath = "/System/Library/ControlCenter/Bundles/MagnifierModule.bundle"
    static let moduleInfoPlistPath = "\(moduleBasePath)/Info.plist"

    static func makeInfoPlist(bundleIdentifier: String, targetSize: Int? = nil) -> Data? {
        guard var dict = decodePlistDictionary(b64: defaultPlistB64) else {
            return nil
        }
        dict["CCLaunchApplicationIdentifier"] = bundleIdentifier

        if let targetSize, targetSize > 0 {
            dict.removeValue(forKey: "0")
            for i in 0...4096 {
                if i > 0 {
                    dict["0"] = String(repeating: "0", count: i)
                }

                guard let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0) else {
                    continue
                }

                if data.count == targetSize {
                    return data
                }

                if data.count > targetSize {
                    break
                }
            }
            return nil
        }

        return try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
    }

    private static func decodePlistDictionary(b64: String) -> [String: Any]? {
        guard let data = decodeBase64(b64) else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return nil }
        return plist as? [String: Any]
    }

    private static func decodeBase64(_ b64: String) -> Data? {
        let cleaned = b64
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        return Data(base64Encoded: cleaned)
    }

    private static let defaultPlistB64 = """
    YnBsaXN0MDDfEBQBAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4fIRUiIyUmJyorXENGQnVu
    ZGxlTmFtZVdEVFhjb2RlWURUU0RLTmFtZV8QHUNDTGF1bmNoQXBwbGljYXRpb25JZGVudGlmaWVy
    WkRUU0RLQnVpbGRfEBNCdWlsZE1hY2hpbmVPU0J1aWxkXxAQTlNQcmluY2lwYWxDbGFzc15EVFBs
    YXRmb3JtTmFtZV8QE0NGQnVuZGxlUGFja2FnZVR5cGVfEBpDRkJ1bmRsZVNob3J0VmVyc2lvblN0
    cmluZ18QGkNGQnVuZGxlU3VwcG9ydGVkUGxhdGZvcm1zXxAdQ0ZCdW5kbGVJbmZvRGljdGlvbmFy
    eVZlcnNpb25fEBJDRkJ1bmRsZUV4ZWN1dGFibGVaRFRDb21waWxlcl8QHFVJUmVxdWlyZWREZXZp
    Y2VDYXBhYmlsaXRpZXNfEBBNaW5pbXVtT1NWZXJzaW9uXxASQ0ZCdW5kbGVJZGVudGlmaWVyXlVJ
    RGV2aWNlRmFtaWx5XxATQ0ZCdW5kbGVEaXNwbGF5TmFtZV8QD0RUUGxhdGZvcm1CdWlsZF8QD01h
    Z25pZmllck1vZHVsZVQxMzMwXxAVaXBob25lb3MxNS41LmludGVybmFsXxATY29tLmFwcGxlLk1h
    Z25pZmllclUxOUY2MVkyMEEyNDExMzNfEBVDQ1VJQXBwTGF1bmNoZXJNb2R1bGVYaXBob25lb3NU
    Qk5ETFMxLjChIFhpUGhvbmVPU1M2LjBfECJjb20uYXBwbGUuY29tcGlsZXJzLmxsdm0uY2xhbmcu
    MV8woSRVYXJtNjRUMTUuNV8QKGNvbS5hcHBsZS5jb250cm9sLWNlbnRlci5NYWduaWZpZXJNb2R1
    bGWiKCkQARACWFJlc3ByaW5nWDEzRTYwNDlhAAgAMwBAAEgAUgByAH0AkwCmALUAywDoAQUBJQE6
    AUUBZAF3AYwBmwGxAcMB1QHaAfICCAIOAhgCMAI5Aj4CQgJEAk0CUQJ2AngCfgKDAq4CsQKzArUC
    vgAAAAAAAAIBAAAAAAAAACwAAAAAAAAAAAAAAAAAAALH
    """
}
