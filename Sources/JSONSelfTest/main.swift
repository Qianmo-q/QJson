import Foundation
import JSONCore

var failures = 0

func check(_ condition: Bool, _ name: String) {
    if condition {
        print("  ok  \(name)")
    } else {
        failures += 1
        print("FAIL  \(name)")
    }
}

func parse(_ text: String) -> JSONNode? {
    let result = JSONParser.parse(text)
    return result.root
}

// 解析：保序、区间、节点数
do {
    let text = "{\"b\": 1, \"a\": [true, null, \"x\"]}"
    let result = JSONParser.parse(text)
    check(result.error == nil, "合法文档解析通过")
    let root = result.root
    check(root?.children.map(\.key) == ["b", "a"], "对象键顺序保留")
    check((text as NSString).substring(with: root?.children[0].range ?? NSRange()) == "1", "标量源区间正确")
    check(result.nodeCount == 6, "节点统计正确")
}

// 严格性
for text in ["", "{} {}", "{\"a\":1,}", "[1,]", "{a:1}", "'x'", "01", "1.", "\"\\x\"", "\"a\nb\""] {
    check(JSONParser.parse(text).error != nil, "非法输入报错: \(text.debugDescription)")
}

// 错误行列
do {
    let error = JSONParser.parse("{\n  \"a\": 1,\n  \"b\": ?\n}").error
    check(error?.line == 3, "错误行号定位")
    check((error?.column ?? 0) > 0, "错误列号定位")
}

// Unicode
do {
    let root = parse("\"\\u4F60\\u597D \\uD83D\\uDE00 😀\"")
    check(root?.stringValue == "你好 😀 😀", "Unicode 转义与代理对解码")
}

// 数字校验
check(JSONParser.isValidNumberLiteral("-12.5e+3"), "合法数字校验")
check(!JSONParser.isValidNumberLiteral("01"), "拒绝前导零")
check(!JSONParser.isValidNumberLiteral("1e"), "拒绝残缺指数")

// 格式化/压缩
do {
    let root = parse("{\"z\":1,\"a\":{\"y\":[1,2],\"b\":true}}")!
    let pretty = JSONFormatter.prettyPrinted(root, indentWidth: 2)
    check(pretty.contains("\"z\": 1,\n  \"a\": {"), "格式化缩进与键顺序")
    check(JSONParser.parse(pretty).error == nil, "格式化结果仍合法")
    check(JSONFormatter.minified(root) == "{\"z\":1,\"a\":{\"y\":[1,2],\"b\":true}}", "压缩输出")
}

// 树编辑补丁
do {
    let text = "{\n  \"a\": 1\n}"
    let root = parse(text)!
    let edit = try! JSONTextPatch.addingMember(in: text, object: root, key: "b", rawValue: "2")
    let added = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    check(added == "{\n  \"a\": 1,\n  \"b\": 2\n}", "对象新增成员保留缩进")

    let text2 = "{\"a\":1,\"b\":2,\"c\":3}"
    let root2 = parse(text2)!
    let mid = try! JSONTextPatch.deleting(in: text2, node: root2.children[1])
    let afterMid = (text2 as NSString).replacingCharacters(in: mid.range, with: mid.replacement)
    check(afterMid == "{\"a\":1,\"c\":3}", "删除中间成员")

    let arrayEdit = try! JSONTextPatch.addingElement(in: "[]", array: parse("[]")!, rawValue: "1")
    let addedArray = ("[]" as NSString).replacingCharacters(in: arrayEdit.range, with: arrayEdit.replacement)
    check(addedArray == "[1]", "空数组新增元素")
}

// 搜索
do {
    let text = "{\"Name\":\"Alice\",\"tags\":[\"admin\",\"user\"],\"note\":null}"
    let root = parse(text)!
    let values = JSONSearch.search(in: text, root: root, query: "a", scope: .values)
    check(values.hits.count == 2, "值搜索命中数")
    let keys = JSONSearch.search(in: text, root: root, query: "name", scope: .keys)
    check(keys.hits.map(\.keyText) == ["Name"], "键搜索")
    let both = JSONSearch.search(in: text, root: root, query: "user", scope: .both)
    check(both.hits.first?.displayPath == "$.tags[1]", "搜索路径展示")
    check((both.hits.first?.revealKeys.count ?? 0) == 2, "搜索揭示路径")
}

// 树展平
do {
    let root = parse("{\"a\":{\"b\":1},\"c\":2}")!
    func labels(_ rows: [JSONTreeRow]) -> [String] {
        rows.map { $0.node.key ?? "$" }
    }
    let collapsed = JSONTreeFlattener.flatten(root: root, expanded: [""])
    check(labels(collapsed.rows) == ["$", "a", "c"], "折叠状态展平")
    let expanded = JSONTreeFlattener.flatten(root: root, expanded: ["", "/k:a"])
    check(labels(expanded.rows) == ["$", "a", "b", "c"], "展开状态展平")
}

// 转换
do {
    let original = "{\"a\":\"b\\n\"}"
    let escaped = JSONConversions.escape(original)
    check((try? JSONConversions.unescape(escaped)) == original, "转义往返")
    let unicode = JSONConversions.chineseToUnicode("中文a")
    check(unicode == "\\u4E2D\\u6587a", "中文转 Unicode")
    check(JSONConversions.unicodeToChinese(unicode) == "中文a", "Unicode 转中文")
    let query = try! JSONConversions.jsonToQuery("{\"a\":\"1 2\",\"b\":true}")
    check(query == "a=1%202&b=true", "JSON 转 Query")
    let back = JSONConversions.queryToJSON("?b=%E4%B8%AD&a=x+y")
    check(back.contains("\"b\": \"中\"") && back.contains("\"a\": \"x y\""), "Query 转 JSON")
}

// 性能冒烟：5MB 文档
do {
    let item = "{\"id\":12345,\"name\":\"项目名称\",\"enabled\":true,\"tags\":[\"a\",\"b\"],\"score\":9.5}"
    var parts: [String] = []
    for index in 0..<50_000 { parts.append(item.replacingOccurrences(of: "12345", with: String(index))) }
    let text = "[" + parts.joined(separator: ",") + "]"
    let start = Date()
    let result = JSONParser.parse(text)
    let elapsed = Date().timeIntervalSince(start)
    check(result.error == nil, "大文档解析成功 (\(String(format: "%.2f", Double(text.utf8.count) / 1_048_576))MB, \(String(format: "%.2f", elapsed))s)")
    let searchStart = Date()
    let search = JSONSearch.search(in: text, root: result.root!, query: "项目名称", scope: .values, limit: 10)
    check(search.totalCount == 50_000 && search.hits.count == 10, "大文档搜索 (\(String(format: "%.2f", Date().timeIntervalSince(searchStart)))s)")
}

if failures > 0 {
    print("\n\(failures) 项失败")
    exit(1)
}
print("\n全部通过")
