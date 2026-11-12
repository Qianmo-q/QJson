import Foundation

public enum JSONSearchScope: String, CaseIterable, Identifiable, Sendable {
    case values
    case keys
    case both

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .values: return "值"
        case .keys: return "键"
        case .both: return "键和值"
        }
    }
}

public struct JSONSearchHit {
    public let node: JSONNode
    public let displayPath: String
    /// 揭示该节点可见所需的容器展开键（按层级排列，含根）。
    public let revealKeys: [String]
    /// 文本区中需要高亮的命中区间。
    public let matchRanges: [NSRange]
    public let keyText: String?
    public let valueText: String?
    public let isKeyMatch: Bool

    public var primaryRange: NSRange { matchRanges.first ?? node.range }
}

public struct JSONSearchResult {
    public let hits: [JSONSearchHit]
    public let totalCount: Int
    public let truncated: Bool
    public let query: String

    public static let empty = JSONSearchResult(hits: [], totalCount: 0, truncated: false, query: "")

    public var highlightRanges: [NSRange] { hits.flatMap(\.matchRanges) }
}

public enum JSONSearch {
    /// 值搜索基于源文本（所见即所搜），键搜索限定在键区间内。
    public static func search(
        in text: String,
        root: JSONNode,
        query rawQuery: String,
        scope: JSONSearchScope,
        limit: Int = 3000,
        occurrenceLimit: Int = 200_000
    ) -> JSONSearchResult {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .empty }
        let ns = text as NSString
        let scanned = allOccurrences(of: query, in: ns, limit: occurrenceLimit)
        let occurrences = scanned.ranges

        var hits: [JSONSearchHit] = []
        var total = 0
        var stack: [JSONNode] = [root]
        while let node = stack.popLast() {
            var ranges: [NSRange] = []
            var keyMatch = false

            if scope != .values, let keyRange = node.keyRange, keyRange.length > 2 {
                let content = NSRange(location: keyRange.location + 1, length: keyRange.length - 2)
                let found = occurrencesWithin(content, occurrences: occurrences)
                if !found.isEmpty {
                    ranges.append(contentsOf: found)
                    keyMatch = true
                }
            }

            if scope != .keys, !node.isContainer, node.range.length > 0 {
                let content = valueContentRange(of: node, in: ns)
                let found = occurrencesWithin(content, occurrences: occurrences)
                if !found.isEmpty { ranges.append(contentsOf: found) }
            }

            if !ranges.isEmpty {
                total += 1
                if hits.count < limit {
                    hits.append(JSONSearchHit(
                        node: node,
                        displayPath: displayPath(of: node),
                        revealKeys: revealKeys(of: node),
                        matchRanges: ranges,
                        keyText: node.key,
                        valueText: node.kind.isContainer ? nil : node.displayValue,
                        isKeyMatch: keyMatch
                    ))
                }
            }

            if node.isContainer {
                for child in node.children.reversed() { stack.append(child) }
            }
        }
        let truncated = total > hits.count || scanned.truncated
        return JSONSearchResult(hits: hits, totalCount: total, truncated: truncated, query: query)
    }

    private static func allOccurrences(
        of query: String,
        in source: NSString,
        limit: Int
    ) -> (ranges: [NSRange], truncated: Bool) {
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: source.length)
        var truncated = false
        let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        while searchRange.length > 0 {
            let found = source.range(of: query, options: options, range: searchRange)
            if found.location == NSNotFound { break }
            if ranges.count >= limit {
                truncated = true
                break
            }
            ranges.append(found)
            let next = found.location + max(found.length, 1)
            if next >= source.length { break }
            searchRange = NSRange(location: next, length: source.length - next)
        }
        return (ranges, truncated)
    }

    private static func occurrencesWithin(_ content: NSRange, occurrences: [NSRange]) -> [NSRange] {
        guard content.length > 0, !occurrences.isEmpty else { return [] }
        let contentEnd = content.location + content.length
        var low = 0
        var high = occurrences.count
        while low < high {
            let mid = (low + high) / 2
            let occurrence = occurrences[mid]
            if occurrence.location + occurrence.length <= content.location {
                low = mid + 1
            } else {
                high = mid
            }
        }
        var result: [NSRange] = []
        var index = low
        while index < occurrences.count {
            let occurrence = occurrences[index]
            if occurrence.location >= contentEnd { break }
            if occurrence.location >= content.location,
               occurrence.location + occurrence.length <= contentEnd {
                result.append(occurrence)
            }
            index += 1
        }
        return result
    }

    private static func valueContentRange(of node: JSONNode, in source: NSString) -> NSRange {
        var range = node.range
        if node.kind == .string, range.length >= 2 {
            range = NSRange(location: range.location + 1, length: range.length - 2)
        }
        let end = range.location + range.length
        guard range.location >= 0, end <= source.length else {
            return NSRange(location: 0, length: 0)
        }
        return range
    }

    private static func displayPath(of node: JSONNode) -> String {
        var segments: [String] = []
        var current = node
        while let parent = current.parent {
            if let key = current.key {
                segments.append(JSONPathFormatter.key(key))
            } else if let index = current.indexInParent {
                segments.append(JSONPathFormatter.index(index))
            }
            current = parent
        }
        return "$" + segments.reversed().joined()
    }

    /// 命中节点可见所需的展开键：根 + 各级祖先容器（不含命中节点自身）。
    private static func revealKeys(of node: JSONNode) -> [String] {
        var chain: [JSONNode] = []
        var current = node.parent
        while let ancestor = current {
            chain.append(ancestor)
            current = ancestor.parent
        }
        chain.reverse()
        var keys: [String] = []
        var currentKey = ""
        for (depth, ancestor) in chain.enumerated() {
            if depth == 0 {
                currentKey = ""
            } else if let key = ancestor.key {
                currentKey = childExpansionKey(parent: currentKey, memberKey: key)
            } else {
                currentKey = childExpansionKey(parent: currentKey, index: ancestor.indexInParent ?? 0)
            }
            keys.append(currentKey)
        }
        return keys
    }
}

public struct JSONTreeRow: Identifiable {
    public let id: Int
    public let node: JSONNode
    public let expansionKey: String
    public let depth: Int
    public let isExpanded: Bool

    public init(node: JSONNode, expansionKey: String, depth: Int, isExpanded: Bool) {
        self.id = node.range.location
        self.node = node
        self.expansionKey = expansionKey
        self.depth = depth
        self.isExpanded = isExpanded
    }
}

public struct JSONTreeFlattenResult {
    public let rows: [JSONTreeRow]
    public let truncated: Bool
}

public enum JSONTreeFlattener {
    public static let defaultRowLimit = 200_000

    /// 按展开状态展平树（迭代实现，避免深层递归）。
    public static func flatten(
        root: JSONNode?,
        expanded: Set<String>,
        rowLimit: Int = defaultRowLimit
    ) -> JSONTreeFlattenResult {
        guard let root else { return JSONTreeFlattenResult(rows: [], truncated: false) }
        var rows: [JSONTreeRow] = []
        var truncated = false
        var stack: [(node: JSONNode, key: String, depth: Int)] = [(root, "", 0)]
        while let item = stack.popLast() {
            if rows.count >= rowLimit {
                truncated = true
                break
            }
            let isExpanded = item.node.isContainer && expanded.contains(item.key)
            rows.append(JSONTreeRow(
                node: item.node,
                expansionKey: item.key,
                depth: item.depth,
                isExpanded: isExpanded
            ))
            guard isExpanded, !item.node.children.isEmpty else { continue }
            for (index, child) in item.node.children.enumerated().reversed() {
                let childKey = cachedExpansionKey(for: child, index: index, parent: item.key)
                stack.append((child, childKey, item.depth + 1))
            }
        }
        return JSONTreeFlattenResult(rows: rows, truncated: truncated)
    }

    public static func allContainerExpansionKeys(root: JSONNode, limit: Int = 100_000) -> Set<String> {
        var keys: Set<String> = []
        var stack: [(node: JSONNode, key: String)] = [(root, "")]
        while let item = stack.popLast() {
            guard item.node.isContainer else { continue }
            if keys.count >= limit { break }
            keys.insert(item.key)
            for (index, child) in item.node.children.enumerated() {
                let childKey = cachedExpansionKey(for: child, index: index, parent: item.key)
                stack.append((child, childKey))
            }
        }
        return keys
    }

    private static func cachedExpansionKey(for child: JSONNode, index: Int, parent: String) -> String {
        guard child.isContainer else { return "" }
        if let cached = child.cachedExpansionKey { return cached }
        let key: String
        if let memberKey = child.key {
            key = childExpansionKey(parent: parent, memberKey: memberKey)
        } else {
            key = childExpansionKey(parent: parent, index: index)
        }
        child.cachedExpansionKey = key
        return key
    }
}
