import Foundation

/// 基于节点源区间生成最小文本补丁，保留用户原有的缩进与格式。
public enum JSONTextPatch {
    public struct Edit: Equatable {
        public let range: NSRange
        public let replacement: String

        public init(range: NSRange, replacement: String) {
            self.range = range
            self.replacement = replacement
        }
    }

    public static func replacingValue(of node: JSONNode, withRawValue raw: String) -> Edit {
        Edit(range: node.range, replacement: raw)
    }

    public static func addingMember(
        in text: String,
        object: JSONNode,
        key: String,
        rawValue: String
    ) throws -> Edit {
        guard object.kind == .object else { throw PatchError("目标节点不是对象") }
        let ns = text as NSString
        let closeLocation = object.range.location + object.range.length - 1
        guard object.range.location >= 0,
              object.range.location + object.range.length <= ns.length,
              closeLocation < ns.length,
              ns.character(at: closeLocation) == 0x7D else {
            throw PatchError("文本已变化，请稍后重试")
        }
        let keyLiteral = jsonStringLiteral(from: key)
        if object.children.isEmpty {
            let inside = ns.substring(with: NSRange(
                location: object.range.location + 1,
                length: closeLocation - object.range.location - 1
            ))
            if inside.contains("\n") {
                let closeIndent = indentOfLine(ns, at: closeLocation)
                return Edit(
                    range: NSRange(location: closeLocation, length: 0),
                    replacement: "\(keyLiteral): \(rawValue)\n\(closeIndent)"
                )
            }
            return Edit(
                range: NSRange(location: closeLocation, length: 0),
                replacement: "\(keyLiteral): \(rawValue)"
            )
        }
        guard let last = object.children.last else { throw PatchError("目标节点不是对象") }
        let anchor = last.range.location + last.range.length
        guard anchor >= object.range.location, anchor <= closeLocation else {
            throw PatchError("文本已变化，请稍后重试")
        }
        let gap = ns.substring(with: NSRange(location: anchor, length: closeLocation - anchor))
        if gap.contains("\n") {
            let childIndent = indentOfLine(ns, at: last.keyRange?.location ?? last.range.location)
            return Edit(
                range: NSRange(location: anchor, length: 0),
                replacement: ",\n\(childIndent)\(keyLiteral): \(rawValue)"
            )
        }
        return Edit(
            range: NSRange(location: anchor, length: 0),
            replacement: ", \(keyLiteral): \(rawValue)"
        )
    }

    public static func addingElement(in text: String, array: JSONNode, rawValue: String) throws -> Edit {
        guard array.kind == .array else { throw PatchError("目标节点不是数组") }
        let ns = text as NSString
        let closeLocation = array.range.location + array.range.length - 1
        guard array.range.location >= 0,
              array.range.location + array.range.length <= ns.length,
              closeLocation < ns.length,
              ns.character(at: closeLocation) == 0x5D else {
            throw PatchError("文本已变化，请稍后重试")
        }
        if array.children.isEmpty {
            let inside = ns.substring(with: NSRange(
                location: array.range.location + 1,
                length: closeLocation - array.range.location - 1
            ))
            if inside.contains("\n") {
                let closeIndent = indentOfLine(ns, at: closeLocation)
                return Edit(
                    range: NSRange(location: closeLocation, length: 0),
                    replacement: "\(rawValue)\n\(closeIndent)"
                )
            }
            return Edit(range: NSRange(location: closeLocation, length: 0), replacement: rawValue)
        }
        guard let last = array.children.last else { throw PatchError("目标节点不是数组") }
        let anchor = last.range.location + last.range.length
        guard anchor >= array.range.location, anchor <= closeLocation else {
            throw PatchError("文本已变化，请稍后重试")
        }
        let gap = ns.substring(with: NSRange(location: anchor, length: closeLocation - anchor))
        if gap.contains("\n") {
            let childIndent = indentOfLine(ns, at: last.range.location)
            return Edit(
                range: NSRange(location: anchor, length: 0),
                replacement: ",\n\(childIndent)\(rawValue)"
            )
        }
        return Edit(range: NSRange(location: anchor, length: 0), replacement: ", \(rawValue)")
    }

    public static func deleting(in text: String, node: JSONNode) throws -> Edit {
        guard let parent = node.parent else { throw PatchError("根节点不可删除") }
        let ns = text as NSString
        let siblings = parent.children
        let index = node.indexInParent ?? siblings.firstIndex(where: { $0 === node }) ?? 0
        guard index >= 0, index < siblings.count, node.range.location >= 0,
              node.range.location + node.range.length <= ns.length else {
            throw PatchError("文本已变化，请稍后重试")
        }
        let startToken = node.keyRange?.location ?? node.range.location
        let endToken = node.range.location + node.range.length
        guard startToken >= parent.range.location, endToken <= parent.range.location + parent.range.length else {
            throw PatchError("文本已变化，请稍后重试")
        }
        if siblings.count == 1 {
            return Edit(range: NSRange(location: startToken, length: endToken - startToken), replacement: "")
        }
        if index < siblings.count - 1 {
            let next = siblings[index + 1]
            let nextStart = next.keyRange?.location ?? next.range.location
            guard nextStart > startToken, nextStart <= ns.length else { throw PatchError("文本已变化，请稍后重试") }
            return Edit(range: NSRange(location: startToken, length: nextStart - startToken), replacement: "")
        }
        let previous = siblings[index - 1]
        let previousEnd = previous.range.location + previous.range.length
        guard previousEnd >= parent.range.location, previousEnd <= endToken else {
            throw PatchError("文本已变化，请稍后重试")
        }
        return Edit(range: NSRange(location: previousEnd, length: endToken - previousEnd), replacement: "")
    }

    private static func indentOfLine(_ ns: NSString, at location: Int) -> String {
        let safeLocation = max(0, min(location, ns.length))
        let lineRange = ns.lineRange(for: NSRange(location: safeLocation, length: 0))
        var index = lineRange.location
        let end = min(lineRange.location + lineRange.length, ns.length)
        var units: [UInt16] = []
        while index < end {
            let unit = ns.character(at: index)
            if unit == 0x20 || unit == 0x09 {
                units.append(unit)
                index += 1
            } else {
                break
            }
        }
        return String(utf16CodeUnits: units, count: units.count)
    }
}

public struct PatchError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
