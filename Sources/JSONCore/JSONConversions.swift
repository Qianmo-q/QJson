import Foundation

public struct JSONConversionError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum JSONConversions {
    // H1 转义
    public static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count + 16)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }

    // H1 去除转义
    public static func unescape(_ text: String) throws -> String {
        let characters = Array(text)
        var index = 0
        var out = ""
        while index < characters.count {
            let character = characters[index]
            guard character == "\\" else {
                out.append(character)
                index += 1
                continue
            }
            guard index + 1 < characters.count else {
                throw JSONConversionError("文本以单个反斜杠结尾，无法去除转义")
            }
            let escape = characters[index + 1]
            switch escape {
            case "n": out += "\n"; index += 2
            case "r": out += "\r"; index += 2
            case "t": out += "\t"; index += 2
            case "b": out += "\u{08}"; index += 2
            case "f": out += "\u{0C}"; index += 2
            case "\"": out += "\""; index += 2
            case "\\": out += "\\"; index += 2
            case "/": out += "/"; index += 2
            case "'": out += "'"; index += 2
            case "u":
                guard index + 6 <= characters.count else {
                    throw JSONConversionError("Unicode 转义不完整（需要 4 位十六进制数字）")
                }
                var hex = String(characters[(index + 2)..<(index + 6)])
                guard let value = UInt32(hex, radix: 16) else {
                    throw JSONConversionError("Unicode 转义包含非法字符：\(hex)")
                }
                index += 6
                if value >= 0xD800, value <= 0xDBFF,
                   index + 6 <= characters.count,
                   characters[index] == "\\",
                   characters[index + 1] == "u" {
                    hex = String(characters[(index + 2)..<(index + 6)])
                    if let low = UInt32(hex, radix: 16), low >= 0xDC00, low <= 0xDFFF {
                        let combined = 0x10000 + ((value - 0xD800) << 10) + (low - 0xDC00)
                        if let scalar = Unicode.Scalar(combined) {
                            out.unicodeScalars.append(scalar)
                        }
                        index += 6
                        continue
                    }
                }
                if let scalar = Unicode.Scalar(value) {
                    out.unicodeScalars.append(scalar)
                } else {
                    out += "\\u" + String(format: "%04X", value)
                }
            default:
                throw JSONConversionError("无效的转义序列：\\\(escape)")
            }
        }
        return out
    }

    // H2 中文转 Unicode
    public static func chineseToUnicode(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count + 16)
        for scalar in text.unicodeScalars {
            guard isHan(scalar.value) else {
                out.unicodeScalars.append(scalar)
                continue
            }
            if scalar.value <= 0xFFFF {
                out += String(format: "\\u%04X", scalar.value)
            } else {
                let value = scalar.value - 0x10000
                let high = 0xD800 + (value >> 10)
                let low = 0xDC00 + (value & 0x3FF)
                out += String(format: "\\u%04X\\u%04X", high, low)
            }
        }
        return out
    }

    // H2 Unicode 转中文
    public static func unicodeToChinese(_ text: String) -> String {
        let characters = Array(text)
        var index = 0
        var out = ""
        while index < characters.count {
            if index + 5 < characters.count,
               characters[index] == "\\",
               characters[index + 1] == "u",
               let value = UInt32(String(characters[(index + 2)..<(index + 6)]), radix: 16) {
                var scalarValue = value
                var consumed = 6
                if value >= 0xD800, value <= 0xDBFF,
                   index + 11 < characters.count,
                   characters[index + 6] == "\\",
                   characters[index + 7] == "u",
                   let low = UInt32(String(characters[(index + 8)..<(index + 12)]), radix: 16),
                   low >= 0xDC00, low <= 0xDFFF {
                    scalarValue = 0x10000 + ((value - 0xD800) << 10) + (low - 0xDC00)
                    consumed = 12
                }
                if let scalar = Unicode.Scalar(scalarValue) {
                    out.unicodeScalars.append(scalar)
                    index += consumed
                    continue
                }
            }
            out.append(characters[index])
            index += 1
        }
        return out
    }

    // H3 JSON 对象 → URL Query
    public static func jsonToQuery(_ text: String) throws -> String {
        let result = JSONParser.parse(text)
        if let error = result.error {
            throw JSONConversionError("JSON 解析失败：第 \(error.line) 行第 \(error.column) 列 \(error.message)")
        }
        guard let root = result.root, root.kind == .object else {
            throw JSONConversionError("顶层必须是 JSON 对象才能转换为 Get 参数")
        }
        var parts: [String] = []
        for child in root.children {
            let value: String
            switch child.kind {
            case .string: value = child.stringValue ?? ""
            case .number: value = child.numberText ?? ""
            case .bool: value = (child.boolValue ?? false) ? "true" : "false"
            case .null: value = ""
            case .object, .array: value = JSONFormatter.minified(child)
            }
            parts.append("\(encodeQueryComponent(child.key ?? ""))=\(encodeQueryComponent(value))")
        }
        return parts.joined(separator: "&")
    }

    // H3 URL Query → JSON 对象
    public static func queryToJSON(_ text: String) -> String {
        var query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.hasPrefix("?") { query.removeFirst() }
        var orderedKeys: [String] = []
        var values: [String: String] = [:]
        for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
            let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let rawKey = String(pieces.first ?? "")
            let rawValue = pieces.count > 1 ? String(pieces[1]) : ""
            let key = decodeQueryComponent(rawKey)
            let value = decodeQueryComponent(rawValue)
            if values[key] == nil { orderedKeys.append(key) }
            values[key] = value
        }
        guard !orderedKeys.isEmpty else { return "{}" }
        let body = orderedKeys.map { key in
            "  \(jsonStringLiteral(from: key)): \(jsonStringLiteral(from: values[key] ?? ""))"
        }.joined(separator: ",\n")
        return "{\n\(body)\n}"
    }

    private static func isHan(_ value: UInt32) -> Bool {
        (value >= 0x4E00 && value <= 0x9FFF)
            || (value >= 0x3400 && value <= 0x4DBF)
            || (value >= 0xF900 && value <= 0xFAFF)
            || (value >= 0x20000 && value <= 0x2FA1F)
    }

    private static func encodeQueryComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func decodeQueryComponent(_ value: String) -> String {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? value
    }
}
