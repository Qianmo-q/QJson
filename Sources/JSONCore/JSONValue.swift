import Foundation

public enum JSONKind: UInt8, Sendable {
    case object
    case array
    case string
    case number
    case bool
    case null

    public var isContainer: Bool { self == .object || self == .array }

    public var displayName: String {
        switch self {
        case .object: return "Object"
        case .array: return "Array"
        case .string: return "String"
        case .number: return "Number"
        case .bool: return "Boolean"
        case .null: return "Null"
        }
    }
}

/// 解析后的 JSON 节点。保留对象键顺序，并记录每个节点在源文本中的 UTF-16 区间。
public final class JSONNode {
    public let kind: JSONKind
    public private(set) var key: String?
    public private(set) var keyRange: NSRange?
    public let range: NSRange
    public let stringValue: String?
    public let numberText: String?
    public let boolValue: Bool?
    public let children: [JSONNode]
    public private(set) weak var parent: JSONNode?
    public private(set) var indexInParent: Int?
    /// 树展开状态键缓存（仅容器节点使用，随一次解析结果存活）。
    public var cachedExpansionKey: String?

    public init(
        kind: JSONKind,
        key: String? = nil,
        keyRange: NSRange? = nil,
        range: NSRange,
        stringValue: String? = nil,
        numberText: String? = nil,
        boolValue: Bool? = nil,
        children: [JSONNode] = []
    ) {
        self.kind = kind
        self.key = key
        self.keyRange = keyRange
        self.range = range
        self.stringValue = stringValue
        self.numberText = numberText
        self.boolValue = boolValue
        self.children = children
        for (index, child) in children.enumerated() {
            child.parent = self
            child.indexInParent = index
        }
    }

    func assignKey(_ key: String, range: NSRange) {
        self.key = key
        self.keyRange = range
    }

    public var isContainer: Bool { kind.isContainer }

    /// 标量值的展示文本（字符串为解码后的内容）。
    public var displayValue: String {
        switch kind {
        case .string: return stringValue ?? ""
        case .number: return numberText ?? ""
        case .bool: return (boolValue ?? false) ? "true" : "false"
        case .null: return "null"
        case .object: return "{\(children.count)}"
        case .array: return "[\(children.count)]"
        }
    }

    /// 搜索时参与匹配的标量文本，容器返回 nil。
    public var searchableText: String? {
        kind.isContainer ? nil : displayValue
    }

    public var typeBadge: String {
        switch kind {
        case .object: return "{}"
        case .array: return "[]"
        case .string: return "str"
        case .number: return "num"
        case .bool: return "bool"
        case .null: return "null"
        }
    }
}

public func jsonStringLiteral(from value: String) -> String {
    var out = "\""
    out.reserveCapacity(value.utf8.count + 2)
    for scalar in value.unicodeScalars {
        switch scalar {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
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
    out += "\""
    return out
}

public func computeLineStarts(_ text: String) -> [Int] {
    var starts: [Int] = [0]
    var offset = 0
    for unit in text.utf16 {
        offset += 1
        if unit == 0x0A { starts.append(offset) }
    }
    return starts
}

/// 返回 1 基的行号与列号（列按 UTF-16 码元计算）。
public func lineColumn(at offset: Int, lineStarts: [Int]) -> (line: Int, column: Int) {
    guard !lineStarts.isEmpty else { return (1, max(1, offset + 1)) }
    var low = 0
    var high = lineStarts.count - 1
    while low < high {
        let mid = (low + high + 1) / 2
        if lineStarts[mid] <= offset { low = mid } else { high = mid - 1 }
    }
    return (low + 1, offset - lineStarts[low] + 1)
}

public func lineNumber(at offset: Int, lineStarts: [Int]) -> Int {
    lineColumn(at: offset, lineStarts: lineStarts).line
}

/// 某一行的整行范围（含行尾换行符）。
public func paragraphRange(forLine line: Int, lineStarts: [Int], textLength: Int) -> NSRange {
    guard !lineStarts.isEmpty else { return NSRange(location: 0, length: textLength) }
    let index = min(max(line - 1, 0), lineStarts.count - 1)
    let start = min(lineStarts[index], textLength)
    let end = index + 1 < lineStarts.count ? min(lineStarts[index + 1], textLength) : textLength
    return NSRange(location: start, length: max(0, end - start))
}

/// JSON 路径展示（$.a.b[0] 风格，特殊键使用 ["..."]）。
public enum JSONPathFormatter {
    public static func key(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        let isValidIdentifier = !name.isEmpty
            && name.unicodeScalars.allSatisfy { allowed.contains($0) }
            && (name.first?.isLetter == true || name.first == "_")
        if isValidIdentifier {
            return "." + name
        }
        return "[" + jsonStringLiteral(from: name) + "]"
    }

    public static func index(_ value: Int) -> String { "[\(value)]" }
}

/// 树展开状态使用的稳定键（与展示路径分离，键名中的特殊字符会转义）。
public func childExpansionKey(parent: String, memberKey: String? = nil, index: Int? = nil) -> String {
    if let memberKey {
        let escaped = memberKey
            .replacingOccurrences(of: "~", with: "~0")
            .replacingOccurrences(of: "/", with: "~1")
        return parent + "/k:" + escaped
    }
    return parent + "/i:" + String(index ?? 0)
}
