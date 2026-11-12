import Foundation

public enum JSONFormatter {
    /// 格式化输出（键顺序保持不变）。
    public static func prettyPrinted(_ root: JSONNode, indentWidth: Int = 2) -> String {
        let unit = String(repeating: " ", count: max(1, min(indentWidth, 8)))
        var output = ""
        writePretty(root, depth: 0, indentUnit: unit, into: &output)
        return output
    }

    /// 压缩输出（去除所有结构性空白，键顺序保持不变）。
    public static func minified(_ root: JSONNode) -> String {
        var output = ""
        writeMinified(root, into: &output)
        return output
    }

    /// 标量节点的字面量文本；容器返回压缩后的 JSON。
    public static func literal(_ node: JSONNode) -> String {
        switch node.kind {
        case .string: return jsonStringLiteral(from: node.stringValue ?? "")
        case .number: return node.numberText ?? "0"
        case .bool: return (node.boolValue ?? false) ? "true" : "false"
        case .null: return "null"
        case .object, .array: return minified(node)
        }
    }

    private static func indent(_ depth: Int, _ unit: String) -> String {
        String(repeating: unit, count: max(0, depth))
    }

    private static func writePretty(_ node: JSONNode, depth: Int, indentUnit: String, into output: inout String) {
        switch node.kind {
        case .object:
            if node.children.isEmpty {
                output += "{}"
                return
            }
            output += "{\n"
            for (index, child) in node.children.enumerated() {
                output += indent(depth + 1, indentUnit)
                output += jsonStringLiteral(from: child.key ?? "")
                output += ": "
                writePretty(child, depth: depth + 1, indentUnit: indentUnit, into: &output)
                output += index == node.children.count - 1 ? "\n" : ",\n"
            }
            output += indent(depth, indentUnit) + "}"
        case .array:
            if node.children.isEmpty {
                output += "[]"
                return
            }
            output += "[\n"
            for (index, child) in node.children.enumerated() {
                output += indent(depth + 1, indentUnit)
                writePretty(child, depth: depth + 1, indentUnit: indentUnit, into: &output)
                output += index == node.children.count - 1 ? "\n" : ",\n"
            }
            output += indent(depth, indentUnit) + "]"
        case .string, .number, .bool, .null:
            output += literal(node)
        }
    }

    private static func writeMinified(_ node: JSONNode, into output: inout String) {
        switch node.kind {
        case .object:
            output += "{"
            for (index, child) in node.children.enumerated() {
                if index > 0 { output += "," }
                output += jsonStringLiteral(from: child.key ?? "")
                output += ":"
                writeMinified(child, into: &output)
            }
            output += "}"
        case .array:
            output += "["
            for (index, child) in node.children.enumerated() {
                if index > 0 { output += "," }
                writeMinified(child, into: &output)
            }
            output += "]"
        case .string, .number, .bool, .null:
            output += literal(node)
        }
    }
}
