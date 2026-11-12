import Foundation

public struct JSONParseError: Sendable, Equatable {
    public let message: String
    public let utf16Offset: Int
    public let line: Int
    public let column: Int

    public init(message: String, utf16Offset: Int, line: Int, column: Int) {
        self.message = message
        self.utf16Offset = utf16Offset
        self.line = line
        self.column = column
    }
}

public struct JSONParseResult {
    public let root: JSONNode?
    public let error: JSONParseError?
    public let nodeCount: Int
    public let lineStarts: [Int]

    public var isValid: Bool { error == nil }
}

public enum JSONParser {
    public static func parse(_ text: String) -> JSONParseResult {
        let units = Array(text.utf16)
        let starts = computeLineStarts(text)
        let parser = Parser(units)
        do {
            let root = try parser.parseDocument()
            return JSONParseResult(root: root, error: nil, nodeCount: parser.nodeCount, lineStarts: starts)
        } catch let failure as ParseFailure {
            let (line, column) = lineColumn(at: failure.offset, lineStarts: starts)
            let error = JSONParseError(
                message: failure.message,
                utf16Offset: failure.offset,
                line: line,
                column: column
            )
            return JSONParseResult(root: nil, error: error, nodeCount: parser.nodeCount, lineStarts: starts)
        } catch {
            let error = JSONParseError(message: "解析失败", utf16Offset: 0, line: 1, column: 1)
            return JSONParseResult(root: nil, error: error, nodeCount: parser.nodeCount, lineStarts: starts)
        }
    }

    /// 校验一个纯数字文本是否为合法的 JSON 数字字面量。
    public static func isValidNumberLiteral(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let result = parse(trimmed)
        guard result.error == nil, let root = result.root, root.kind == .number else { return false }
        return root.range.location == 0 && root.range.length == (trimmed as NSString).length
    }
}

private struct ParseFailure: Error {
    let message: String
    let offset: Int
}

private final class Parser {
    private let u: [UInt16]
    private var i = 0
    private let n: Int
    private var depth = 0
    private let maxDepth = 512
    private var keyPool: [String: String] = [:]
    private(set) var nodeCount = 0

    init(_ units: [UInt16]) {
        u = units
        n = units.count
    }

    func parseDocument() throws -> JSONNode {
        skipWhitespace()
        if i >= n { throw fail("内容为空，无法解析 JSON") }
        let value = try parseValue()
        skipWhitespace()
        if i < n { throw fail("根值之后存在多余内容") }
        return value
    }

    // MARK: - Values

    private func parseValue() throws -> JSONNode {
        guard i < n else { throw fail("意外的输入结束，缺少值") }
        switch u[i] {
        case 0x7B: return try parseObject()
        case 0x5B: return try parseArray()
        case 0x22: return try parseStringValue()
        case 0x74:
            try expectWord("true")
            nodeCount += 1
            return JSONNode(kind: .bool, range: NSRange(location: i - 4, length: 4), boolValue: true)
        case 0x66:
            try expectWord("false")
            nodeCount += 1
            return JSONNode(kind: .bool, range: NSRange(location: i - 5, length: 5), boolValue: false)
        case 0x6E:
            try expectWord("null")
            nodeCount += 1
            return JSONNode(kind: .null, range: NSRange(location: i - 4, length: 4))
        default:
            if u[i] == 0x2D || (u[i] >= 0x30 && u[i] <= 0x39) {
                return try parseNumber()
            }
            throw fail("意外的字符 \(describe(u[i]))")
        }
    }

    private func parseStringValue() throws -> JSONNode {
        let start = i
        let value = try scanStringToken()
        nodeCount += 1
        return JSONNode(
            kind: .string,
            range: NSRange(location: start, length: i - start),
            stringValue: value
        )
    }

    private func parseNumber() throws -> JSONNode {
        let start = i
        if u[i] == 0x2D { i += 1 }
        guard i < n else { throw fail("数字格式不完整") }
        if u[i] == 0x30 {
            i += 1
        } else if u[i] >= 0x31 && u[i] <= 0x39 {
            while i < n, isDigit(u[i]) { i += 1 }
        } else {
            throw fail("数字格式错误：整数部分不合法")
        }
        if i < n, u[i] == 0x2E {
            i += 1
            guard i < n, isDigit(u[i]) else { throw fail("数字格式错误：小数部分不完整") }
            while i < n, isDigit(u[i]) { i += 1 }
        }
        if i < n, u[i] == 0x65 || u[i] == 0x45 {
            i += 1
            if i < n, u[i] == 0x2B || u[i] == 0x2D { i += 1 }
            guard i < n, isDigit(u[i]) else { throw fail("数字格式错误：指数部分不完整") }
            while i < n, isDigit(u[i]) { i += 1 }
        }
        let raw = String(decoding: u[start..<i], as: UTF16.self)
        nodeCount += 1
        return JSONNode(
            kind: .number,
            range: NSRange(location: start, length: i - start),
            numberText: raw
        )
    }

    private func parseObject() throws -> JSONNode {
        depth += 1
        if depth > maxDepth { throw fail("嵌套层级过深（超过 \(maxDepth) 层）") }
        defer { depth -= 1 }

        let start = i
        i += 1 // {
        var members: [JSONNode] = []
        skipWhitespace()
        if i < n, u[i] == 0x7D {
            i += 1
            nodeCount += 1
            return JSONNode(kind: .object, range: NSRange(location: start, length: i - start))
        }
        while true {
            skipWhitespace()
            guard i < n else { throw fail("对象未闭合，缺少 “}”") }
            guard u[i] == 0x22 else { throw fail("对象成员名必须是双引号字符串") }
            let keyStart = i
            let parsedKey = try scanStringToken()
            let key: String
            if let pooled = keyPool[parsedKey] {
                key = pooled
            } else {
                keyPool[parsedKey] = parsedKey
                key = parsedKey
            }
            let keyRange = NSRange(location: keyStart, length: i - keyStart)
            skipWhitespace()
            guard i < n, u[i] == 0x3A else { throw fail("对象键之后缺少 “:”") }
            i += 1
            skipWhitespace()
            let value = try parseValue()
            value.assignKey(key, range: keyRange)
            members.append(value)
            skipWhitespace()
            guard i < n else { throw fail("对象未闭合，缺少 “}”") }
            if u[i] == 0x2C {
                i += 1
                skipWhitespace()
                if i < n, u[i] == 0x7D { throw fail("对象最后一个成员后存在多余的逗号") }
                continue
            }
            if u[i] == 0x7D {
                i += 1
                break
            }
            throw fail("对象成员之间缺少 “,” 或对象未闭合")
        }
        nodeCount += 1
        return JSONNode(kind: .object, range: NSRange(location: start, length: i - start), children: members)
    }

    private func parseArray() throws -> JSONNode {
        depth += 1
        if depth > maxDepth { throw fail("嵌套层级过深（超过 \(maxDepth) 层）") }
        defer { depth -= 1 }

        let start = i
        i += 1 // [
        var elements: [JSONNode] = []
        skipWhitespace()
        if i < n, u[i] == 0x5D {
            i += 1
            nodeCount += 1
            return JSONNode(kind: .array, range: NSRange(location: start, length: i - start))
        }
        while true {
            skipWhitespace()
            guard i < n else { throw fail("数组未闭合，缺少 “]”") }
            elements.append(try parseValue())
            skipWhitespace()
            guard i < n else { throw fail("数组未闭合，缺少 “]”") }
            if u[i] == 0x2C {
                i += 1
                skipWhitespace()
                if i < n, u[i] == 0x5D { throw fail("数组最后一个元素后存在多余的逗号") }
                continue
            }
            if u[i] == 0x5D {
                i += 1
                break
            }
            throw fail("数组元素之间缺少 “,” 或数组未闭合")
        }
        nodeCount += 1
        return JSONNode(kind: .array, range: NSRange(location: start, length: i - start), children: elements)
    }

    // MARK: - Scanning

    private func scanStringToken() throws -> String {
        let start = i
        i += 1 // "
        var scalars = String.UnicodeScalarView()
        while i < n {
            let unit = u[i]
            if unit == 0x22 {
                i += 1
                return String(scalars)
            }
            if unit < 0x20 {
                throw fail("字符串中包含未转义的控制字符", offset: i)
            }
            if unit == 0x5C {
                i += 1
                guard i < n else { throw fail("字符串转义序列不完整", offset: start) }
                let escape = u[i]
                switch escape {
                case 0x22: scalars.append("\""); i += 1
                case 0x5C: scalars.append("\\"); i += 1
                case 0x2F: scalars.append("/"); i += 1
                case 0x62: scalars.append("\u{08}"); i += 1
                case 0x66: scalars.append("\u{0C}"); i += 1
                case 0x6E: scalars.append("\n"); i += 1
                case 0x72: scalars.append("\r"); i += 1
                case 0x74: scalars.append("\t"); i += 1
                case 0x75:
                    i += 1
                    let value = try readHex4()
                    if value >= 0xD800, value <= 0xDBFF {
                        if let low = peekLowSurrogateEscape() {
                            let combined = 0x10000 + ((value - 0xD800) << 10) + (low - 0xDC00)
                            if let scalar = Unicode.Scalar(combined) { scalars.append(scalar) }
                            i += 6
                        } else {
                            scalars.append("\u{FFFD}")
                        }
                    } else if value >= 0xDC00, value <= 0xDFFF {
                        scalars.append("\u{FFFD}")
                    } else if let scalar = Unicode.Scalar(value) {
                        scalars.append(scalar)
                    }
                default:
                    throw fail("无效的转义序列 \\\(describe(escape))", offset: i - 1)
                }
            } else if unit >= 0xD800, unit <= 0xDBFF {
                if i + 1 < n, u[i + 1] >= 0xDC00, u[i + 1] <= 0xDFFF {
                    let combined = 0x10000 + ((UInt32(unit) - 0xD800) << 10) + (UInt32(u[i + 1]) - 0xDC00)
                    if let scalar = Unicode.Scalar(combined) { scalars.append(scalar) }
                    i += 2
                } else {
                    scalars.append("\u{FFFD}")
                    i += 1
                }
            } else if unit >= 0xDC00, unit <= 0xDFFF {
                scalars.append("\u{FFFD}")
                i += 1
            } else if let scalar = Unicode.Scalar(UInt32(unit)) {
                scalars.append(scalar)
                i += 1
            } else {
                i += 1
            }
        }
        throw fail("字符串未闭合，缺少结尾的双引号", offset: start)
    }

    private func readHex4() throws -> UInt32 {
        guard i + 4 <= n else { throw fail("Unicode 转义需要 4 位十六进制数字", offset: i) }
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let digit = hexValue(u[i]) else {
                throw fail("Unicode 转义包含非法十六进制字符", offset: i)
            }
            value = value * 16 + digit
            i += 1
        }
        return value
    }

    private func peekLowSurrogateEscape() -> UInt32? {
        guard i + 6 <= n, u[i] == 0x5C, u[i + 1] == 0x75 else { return nil }
        var value: UInt32 = 0
        for offset in 2..<6 {
            guard let digit = hexValue(u[offset == 2 ? i + offset : i + offset]) else { return nil }
            value = value * 16 + digit
        }
        return (value >= 0xDC00 && value <= 0xDFFF) ? value : nil
    }

    private func skipWhitespace() {
        while i < n {
            switch u[i] {
            case 0x20, 0x09, 0x0A, 0x0D: i += 1
            default: return
            }
        }
    }

    private func expectWord(_ word: String) throws {
        let expected = Array(word.utf16)
        let start = i
        guard i + expected.count <= n else { throw fail("意外的输入结束") }
        for unit in expected {
            if u[i] != unit { throw fail("非法的字面量，期待 “\(word)”", offset: start) }
            i += 1
        }
    }

    private func isDigit(_ unit: UInt16) -> Bool { unit >= 0x30 && unit <= 0x39 }

    private func hexValue(_ unit: UInt16) -> UInt32? {
        switch unit {
        case 0x30...0x39: return UInt32(unit - 0x30)
        case 0x41...0x46: return UInt32(unit - 0x41 + 10)
        case 0x61...0x66: return UInt32(unit - 0x61 + 10)
        default: return nil
        }
    }

    private func describe(_ unit: UInt16) -> String {
        if let scalar = Unicode.Scalar(UInt32(unit)), !scalar.properties.isWhitespace {
            return "“\(Character(scalar))”"
        }
        return String(format: "U+%04X", unit)
    }

    private func fail(_ message: String, offset: Int? = nil) -> ParseFailure {
        ParseFailure(message: message, offset: min(offset ?? i, n))
    }
}
