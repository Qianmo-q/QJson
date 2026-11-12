import AppKit
import Combine
import JSONCore
import SwiftUI
import UniformTypeIdentifiers

enum ParseState {
    case idle
    case valid(nodeCount: Int, elapsed: TimeInterval)
    case error(JSONParseError)

    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
}

final class AppModel: ObservableObject {
    let undoManager = UndoManager()
    private(set) weak var editor: EditorController?

    @Published private(set) var parseState: ParseState = .idle
    @Published private(set) var isParsing = false
    @Published private(set) var root: JSONNode?
    @Published var fileName: String?
    @Published var toast: String?
    @Published var caretLine = 1
    @Published var caretColumn = 1
    @Published var selectionLength = 0
    @Published var lineCount = 1
    @Published var characterCount = 0
    /// 格式化缩进宽度，持久化到 UserDefaults。
    @Published var indentWidth: Int {
        didSet {
            guard indentWidth != oldValue else { return }
            UserDefaults.standard.set(indentWidth, forKey: Self.indentDefaultsKey)
        }
    }
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    /// 主题外观模式，持久化到 UserDefaults。
    @Published var appearanceMode: AppearanceMode {
        didSet {
            guard appearanceMode != oldValue else { return }
            applyAppearance()
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: Self.appearanceDefaultsKey)
        }
    }
    /// 左右选中联动开关：锁定（默认）时两侧互相跟随，解锁后各自独立。
    @Published var syncSelection: Bool {
        didSet {
            UserDefaults.standard.set(syncSelection, forKey: Self.syncDefaultsKey)
        }
    }

    @Published var searchQuery = "" {
        didSet {
            if searchQuery != oldValue {
                currentHitIndex = nil
                scheduleSearch()
            }
        }
    }
    @Published var searchScope: JSONSearchScope = .values {
        didSet {
            if searchScope != oldValue {
                currentHitIndex = nil
                scheduleSearch(immediate: true)
            }
        }
    }
    @Published private(set) var searchResult: JSONSearchResult = .empty
    @Published private(set) var currentHitIndex: Int?
    @Published private(set) var isSearching = false
    @Published var searchFocusToken = 0

    let tree = TreeStore()
    let treeUI = TreeUIState()

    var treeRows: [JSONTreeRow] { tree.rows }
    var treeTruncated: Bool { tree.truncated }

    private var expandedKeys: Set<String> = [""]
    private var lastText = ""
    private var pendingOpenURL: URL?
    private var didInitialLoad = false
    private var parseGeneration = 0
    private var parseWork: DispatchWorkItem?
    private var shouldRevealErrorAfterParse = false
    private var autoExpandRootOnNextParse = false
    private var searchGeneration = 0
    private var searchWork: DispatchWorkItem?
    private var toastWork: DispatchWorkItem?
    private var undoObservers: [NSObjectProtocol] = []
    private var isSyncingSelection = false

    private static let appearanceDefaultsKey = "QJson.appearanceMode"
    private static let syncDefaultsKey = "QJson.syncSelection"
    private static let indentDefaultsKey = "QJson.indentWidth"

    init() {
        let defaults = UserDefaults.standard
        appearanceMode = AppearanceMode(rawValue: defaults.string(forKey: Self.appearanceDefaultsKey) ?? "") ?? .system
        if defaults.object(forKey: Self.syncDefaultsKey) != nil {
            syncSelection = defaults.bool(forKey: Self.syncDefaultsKey)
        } else {
            syncSelection = true
        }
        indentWidth = defaults.integer(forKey: Self.indentDefaultsKey) == 4 ? 4 : 2
        observeUndo()
        applyAppearance()
    }

    deinit {
        undoObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    var windowTitle: String {
        if let fileName { return "\(fileName) — QJson" }
        return "QJson"
    }

    var currentHit: JSONSearchHit? {
        guard let index = currentHitIndex, index >= 0, index < searchResult.hits.count else { return nil }
        return searchResult.hits[index]
    }

    func attach(editor: EditorController) {
        self.editor = editor
        refreshUndoState()
    }

    /// 首次显示窗口时载入示例；若启动时通过 Finder 打开了文件，则优先打开该文件。
    func startup() {
        guard !didInitialLoad else { return }
        didInitialLoad = true
        if let url = pendingOpenURL {
            pendingOpenURL = nil
            open(url: url)
            return
        }
        if let editor, editor.text.isEmpty {
            loadDemo()
        } else {
            scheduleParse(editor?.text ?? "", immediate: true)
        }
    }

    // MARK: - 文本与解析

    func editorTextDidChange(_ text: String, lineStarts: [Int]) {
        lastText = text
        characterCount = (text as NSString).length
        lineCount = max(1, lineStarts.count)
        isParsing = true
        searchResult = .empty
        currentHitIndex = nil
        editor?.setSearchHighlights(ranges: [], current: nil)
        scheduleParse(text)
    }

    func scheduleParse(_ text: String, immediate: Bool = false) {
        parseWork?.cancel()
        parseGeneration += 1
        let generation = parseGeneration
        isParsing = true
        let work = DispatchWorkItem { [weak self] in
            let started = Date()
            let result = JSONParser.parse(text)
            let elapsed = Date().timeIntervalSince(started)
            DispatchQueue.main.async {
                guard let self, generation == self.parseGeneration else { return }
                self.apply(result, elapsed: elapsed)
            }
        }
        parseWork = work
        if immediate {
            DispatchQueue.global(qos: .userInitiated).async(execute: work)
        } else {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    private func apply(_ result: JSONParseResult, elapsed: TimeInterval) {
        isParsing = false
        refreshUndoState()
        if let error = result.error {
            root = nil
            parseState = .error(error)
            let range = paragraphRange(
                forLine: error.line,
                lineStarts: result.lineStarts,
                textLength: characterCount
            )
            editor?.setErrorHighlight(line: error.line, range: range)
            if shouldRevealErrorAfterParse {
                shouldRevealErrorAfterParse = false
                editor?.reveal(NSRange(location: min(error.utf16Offset, characterCount), length: 0), select: false)
            }
            tree.rows = []
            tree.truncated = false
            tree.version += 1
                searchResult = .empty
            currentHitIndex = nil
            editor?.setSearchHighlights(ranges: [], current: nil)
            return
        }
        root = result.root
        parseState = .valid(nodeCount: result.nodeCount, elapsed: elapsed)
        shouldRevealErrorAfterParse = false
        editor?.setErrorHighlight(line: nil, range: nil)
        if autoExpandRootOnNextParse {
            autoExpandRootOnNextParse = false
            // 大文档默认只显示根节点，避免一次性生成大量树行；小文档保持展开。
            if let root, root.children.count <= 200 {
                expandedKeys.insert("")
            }
        }
        rebuildTree()
        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scheduleSearch(immediate: true)
        } else {
            editor?.setSearchHighlights(ranges: [], current: nil)
        }
        // 重新解析后节点区间已变化，按当前光标重新对齐树选中。
        if syncSelection, let editor {
            syncTreeSelection(to: editor.selectedOffset)
        }
    }

    private func refreshNow() {
        scheduleParse(lastText, immediate: true)
    }

    // MARK: - 撤销

    private func observeUndo() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .NSUndoManagerDidUndoChange,
            .NSUndoManagerDidRedoChange,
            .NSUndoManagerDidCloseUndoGroup,
            .NSUndoManagerDidOpenUndoGroup,
        ]
        for name in names {
            undoObservers.append(center.addObserver(forName: name, object: undoManager, queue: .main) { [weak self] _ in
                self?.refreshUndoState()
            })
        }
    }

    func refreshUndoState() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
    }

    func undo() {
        guard undoManager.canUndo else { return }
        undoManager.undo()
        refreshUndoState()
    }

    func redo() {
        guard undoManager.canRedo else { return }
        undoManager.redo()
        refreshUndoState()
    }

    // MARK: - 光标

    func editorCaretMoved(line: Int, column: Int, selectionLength: Int, offset: Int) {
        caretLine = line
        caretColumn = column
        self.selectionLength = selectionLength
        syncTreeSelection(to: offset)
    }

    // MARK: - 左右选中联动

    /// 切换左右联动；重新锁定时立即按当前光标对齐一次。
    func toggleSyncSelection() {
        syncSelection.toggle()
        guard syncSelection, let editor else { return }
        syncTreeSelection(to: editor.selectedOffset)
    }

    /// 树行被选中时，把文本编辑器选中到该节点对应的行内片段。
    func treeSelectionDidChange(row: JSONTreeRow) {
        guard syncSelection, !isSyncingSelection else { return }
        isSyncingSelection = true
        defer { isSyncingSelection = false }
        let node = row.node
        let start = min(node.keyRange?.location ?? node.range.location, node.range.location)
        editor?.selectNodeText(start: start, end: node.range.location + node.range.length)
    }

    /// 按文本偏移找到最深节点，并让树视图选中、滚动到对应行。
    private func syncTreeSelection(to offset: Int) {
        guard syncSelection, !isSyncingSelection, let root else { return }
        let textLength = editor?.textLength ?? characterCount
        let clamped = min(max(offset, 0), max(0, textLength - 1))
        let node = deepestNode(at: clamped, in: root)
        let id = node.range.location
        guard treeUI.selectedRowID != id else { return }
        isSyncingSelection = true
        defer { isSyncingSelection = false }
        if tree.rows.contains(where: { $0.id == id }) {
            treeUI.selectedRowID = id
            tree.pendingScrollTarget = id
        } else {
            revealTree(node: node, revealKeys: revealKeys(of: node))
        }
    }

    /// 深度优先定位包含指定文本偏移的最深节点；子节点按起始位置有序，可二分。
    private func deepestNode(at offset: Int, in root: JSONNode) -> JSONNode {
        var current = root
        while !current.children.isEmpty {
            let children = current.children
            var low = 0
            var high = children.count - 1
            var found = -1
            while low <= high {
                let mid = (low + high) / 2
                if nodeStart(children[mid]) <= offset {
                    found = mid
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            guard found >= 0 else { return current }
            let child = children[found]
            guard offset < child.range.location + child.range.length else { return current }
            current = child
        }
        return current
    }

    /// 节点在文本中的起始偏移（对象成员从键名开始）。
    private func nodeStart(_ node: JSONNode) -> Int {
        min(node.keyRange?.location ?? node.range.location, node.range.location)
    }

    /// 揭示节点可见所需的祖先展开键（按层级，含根）。
    private func revealKeys(of node: JSONNode) -> [String] {
        var keys: [String] = []
        var current = node.parent
        while let ancestor = current {
            keys.append(expansionKey(forNode: ancestor))
            current = ancestor.parent
        }
        return keys
    }

    // MARK: - 外观

    private func applyAppearance() {
        NSApplication.shared.appearance = appearanceMode.appearance
    }

    // MARK: - 树

    private func rebuildTree() {
        let result = JSONTreeFlattener.flatten(root: root, expanded: expandedKeys)
        tree.rows = result.rows
        tree.truncated = result.truncated
        tree.version += 1
    }

    func toggleExpansion(rowID: Int) {
        guard let index = tree.rows.firstIndex(where: { $0.id == rowID }) else { return }
        let row = tree.rows[index]
        guard row.node.isContainer else { return }
        let key = expansionKey(forNode: row.node)
        if expandedKeys.contains(key) {
            collapse(at: index, key: key)
        } else {
            expand(at: index, key: key)
        }
    }

    /// 仅展开（用于内联新增前确保子节点可见）。
    func expandContainer(rowID: Int) {
        guard let index = tree.rows.firstIndex(where: { $0.id == rowID }) else { return }
        let row = tree.rows[index]
        guard row.node.isContainer else { return }
        let key = expansionKey(forNode: row.node)
        guard !expandedKeys.contains(key) else { return }
        expand(at: index, key: key)
    }

    /// 增量展开：仅插入该节点的子树，避免整棵树重新展平。
    private func expand(at index: Int, key: String) {
        let row = tree.rows[index]
        guard row.node.isContainer, !expandedKeys.contains(key) else { return }
        expandedKeys.insert(key)
        tree.rows[index] = JSONTreeRow(
            node: row.node,
            expansionKey: key,
            depth: row.depth,
            isExpanded: true
        )
        var children = subtreeRows(of: row.node, parentKey: key, parentDepth: row.depth)
        let capacity = max(0, JSONTreeFlattener.defaultRowLimit - tree.rows.count)
        var truncated = false
        if children.count > capacity {
            children = Array(children.prefix(capacity))
            truncated = true
        }
        if !children.isEmpty {
            tree.rows.insert(contentsOf: children, at: index + 1)
        }
        tree.truncated = truncated || tree.rows.count >= JSONTreeFlattener.defaultRowLimit
        tree.version += 1
    }

    /// 增量折叠：删除该节点之后的子树行。
    private func collapse(at index: Int, key: String) {
        let row = tree.rows[index]
        expandedKeys.remove(key)
        tree.rows[index] = JSONTreeRow(
            node: row.node,
            expansionKey: "",
            depth: row.depth,
            isExpanded: false
        )
        var end = index + 1
        while end < tree.rows.count, tree.rows[end].depth > row.depth {
            end += 1
        }
        if end > index + 1 {
            tree.rows.removeSubrange((index + 1)..<end)
        }
        tree.truncated = tree.rows.count >= JSONTreeFlattener.defaultRowLimit
        tree.version += 1
    }

    private func subtreeRows(
        of node: JSONNode,
        parentKey: String,
        parentDepth: Int
    ) -> [JSONTreeRow] {
        // 只有存在非根展开项时才需要为子节点生成展开键，避免大批量字符串分配。
        let needsKeys = expandedKeys.contains { !$0.isEmpty }
        if !needsKeys {
            var rows: [JSONTreeRow] = []
            rows.reserveCapacity(node.children.count)
            for child in node.children {
                rows.append(JSONTreeRow(
                    node: child,
                    expansionKey: "",
                    depth: parentDepth + 1,
                    isExpanded: false
                ))
            }
            return rows
        }
        var result: [JSONTreeRow] = []
        result.reserveCapacity(node.children.count)
        var stack: [(node: JSONNode, key: String, depth: Int, expanded: Bool)] = []
        stack.reserveCapacity(node.children.count)
        for (index, child) in node.children.enumerated().reversed() {
            var childKey = ""
            var expanded = false
            if needsKeys, child.isContainer {
                childKey = expansionKey(for: child, index: index, parent: parentKey)
                expanded = expandedKeys.contains(childKey)
            }
            stack.append((child, childKey, parentDepth + 1, expanded))
        }
        while let item = stack.popLast() {
            result.append(JSONTreeRow(
                node: item.node,
                expansionKey: item.key,
                depth: item.depth,
                isExpanded: item.expanded
            ))
            guard item.expanded else { continue }
            for (index, child) in item.node.children.enumerated().reversed() {
                var childKey = ""
                var expanded = false
                if child.isContainer {
                    childKey = expansionKey(for: child, index: index, parent: item.key)
                    expanded = expandedKeys.contains(childKey)
                }
                stack.append((child, childKey, item.depth + 1, expanded))
            }
        }
        return result
    }

    /// 按节点祖先链按需计算并缓存展开键。
    private func expansionKey(forNode node: JSONNode) -> String {
        var chain: [JSONNode] = []
        var current: JSONNode? = node
        while let item = current, item.parent != nil {
            chain.append(item)
            current = item.parent
        }
        chain.reverse()
        var key = ""
        for item in chain {
            if let cached = item.cachedExpansionKey {
                key = cached
                continue
            }
            let computed: String
            if let memberKey = item.key {
                computed = childExpansionKey(parent: key, memberKey: memberKey)
            } else {
                computed = childExpansionKey(parent: key, index: item.indexInParent ?? 0)
            }
            item.cachedExpansionKey = computed
            key = computed
        }
        return key
    }

    private func expansionKey(for child: JSONNode, index: Int, parent: String) -> String {
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

    func expandAll() {
        guard let root else { return }
        expandedKeys = JSONTreeFlattener.allContainerExpansionKeys(root: root)
        rebuildTree()
        if tree.truncated { showToast("节点过多，仅展示前 \(JSONTreeFlattener.defaultRowLimit) 行") }
    }

    func collapseAll() {
        expandedKeys = []
        treeUI.selectedRowID = nil
        rebuildTree()
    }

    private func revealTree(node: JSONNode, revealKeys: [String]) {
        var changed = false
        for key in revealKeys where !expandedKeys.contains(key) {
            expandedKeys.insert(key)
            changed = true
        }
        if changed { rebuildTree() }
        treeUI.selectedRowID = node.range.location
        tree.pendingScrollTarget = node.range.location
    }

    // MARK: - 树编辑

    func applyValueEdit(node: JSONNode, rawValue: String) {
        let edit = JSONTextPatch.replacingValue(of: node, withRawValue: rawValue)
        editor?.replaceCharacters(in: edit.range, with: edit.replacement)
        refreshNow()
        showToast("已修改值")
    }

    /// 修改对象成员的键名；返回错误信息，成功返回 nil。
    func renameKey(node: JSONNode, newKey: String) -> String? {
        guard let parent = node.parent, parent.kind == .object,
              let keyRange = node.keyRange, let oldKey = node.key else {
            return "该节点没有可编辑的键名"
        }
        let trimmed = newKey.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "键名不能为空" }
        if trimmed != oldKey, parent.children.contains(where: { $0.key == trimmed }) {
            return "键 “\(trimmed)” 已存在"
        }
        guard trimmed != oldKey else { return nil }
        let text = editor?.text ?? lastText
        let ns = text as NSString
        guard keyRange.location >= 0, keyRange.location + keyRange.length <= ns.length else {
            return "文本已变化，请稍后重试"
        }
        editor?.replaceCharacters(in: keyRange, with: jsonStringLiteral(from: trimmed))
        refreshNow()
        showToast("已修改键名")
        return nil
    }

    func addMember(
        to object: JSONNode,
        key: String,
        rawValue: String
    ) -> String? {
        if object.children.contains(where: { $0.key == key }) {
            return "键 “\(key)” 已存在"
        }
        do {
            let text = editor?.text ?? lastText
            let edit = try JSONTextPatch.addingMember(in: text, object: object, key: key, rawValue: rawValue)
            expandedKeys.insert(expansionKey(forNode: object))
            editor?.replaceCharacters(in: edit.range, with: edit.replacement)
            refreshNow()
            showToast("已添加成员")
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func addElement(to array: JSONNode, rawValue: String) -> String? {
        do {
            let text = editor?.text ?? lastText
            let edit = try JSONTextPatch.addingElement(in: text, array: array, rawValue: rawValue)
            expandedKeys.insert(expansionKey(forNode: array))
            editor?.replaceCharacters(in: edit.range, with: edit.replacement)
            refreshNow()
            showToast("已添加元素")
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func deleteNode(_ node: JSONNode) {
        do {
            let text = editor?.text ?? lastText
            let edit = try JSONTextPatch.deleting(in: text, node: node)
            editor?.replaceCharacters(in: edit.range, with: edit.replacement)
            if treeUI.selectedRowID == node.range.location { treeUI.selectedRowID = nil }
            refreshNow()
            showToast("已删除节点")
        } catch {
            showToast(error.localizedDescription)
        }
    }

    // MARK: - 搜索

    func requestSearchFocus() {
        searchFocusToken += 1
    }

    private func scheduleSearch(immediate: Bool = false) {
        searchWork?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            applySearch(.empty, generation: generation)
            return
        }
        guard let root else {
            applySearch(.empty, generation: generation)
            return
        }
        isSearching = true
        let text = lastText
        let scope = searchScope
        let work = DispatchWorkItem { [weak self] in
            let result = JSONSearch.search(in: text, root: root, query: query, scope: scope)
            DispatchQueue.main.async {
                guard let self, generation == self.searchGeneration else { return }
                self.isSearching = false
                self.applySearch(result, generation: generation)
            }
        }
        searchWork = work
        if immediate {
            DispatchQueue.global(qos: .userInitiated).async(execute: work)
        } else {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }

    private func applySearch(_ result: JSONSearchResult, generation: Int) {
        guard generation == searchGeneration else { return }
        searchResult = result
        if result.hits.isEmpty {
            currentHitIndex = nil
        } else if currentHitIndex == nil {
            currentHitIndex = 0
        } else if let index = currentHitIndex, index >= result.hits.count {
            currentHitIndex = result.hits.count - 1
        }
        updateSearchHighlights()
    }

    private func updateSearchHighlights() {
        let ranges = Array(searchResult.highlightRanges.prefix(20_000))
        editor?.setSearchHighlights(ranges: ranges, current: currentHit?.primaryRange)
    }

    func searchNext() { stepSearch(+1) }
    func searchPrevious() { stepSearch(-1) }

    private func stepSearch(_ delta: Int) {
        let hits = searchResult.hits
        guard !hits.isEmpty else { return }
        var index = currentHitIndex ?? (delta > 0 ? -1 : 0)
        index = (index + delta) % hits.count
        if index < 0 { index += hits.count }
        selectHit(index)
    }

    func selectHit(_ index: Int) {
        guard index >= 0, index < searchResult.hits.count else { return }
        currentHitIndex = index
        let hit = searchResult.hits[index]
        editor?.reveal(hit.primaryRange, select: true)
        updateSearchHighlights()
        revealTree(node: hit.node, revealKeys: hit.revealKeys)
    }

    func clearSearch() {
        searchQuery = ""
    }

    // MARK: - 格式化

    var canTransformText: Bool {
        guard !isParsing, let editor else { return false }
        return lastText == editor.text
    }

    func format(indent: Int) {
        guard canTransformText, let root else {
            showToast("JSON 正在解析或不合法，请稍后重试")
            return
        }
        indentWidth = indent
        let pretty = JSONFormatter.prettyPrinted(root, indentWidth: indent)
        editor?.replaceAllText(pretty, undoable: true)
        refreshNow()
        showToast("已格式化（\(indent) 空格缩进）")
    }

    func minify() {
        guard canTransformText, let root else {
            showToast("JSON 正在解析或不合法，请稍后重试")
            return
        }
        editor?.replaceAllText(JSONFormatter.minified(root), undoable: true)
        refreshNow()
        showToast("已压缩")
    }

    // MARK: - 文件与演示

    func openFilePanel() {
        let panel = NSOpenPanel()
        panel.title = "打开 JSON 文件"
        panel.allowedContentTypes = [.json, .plainText, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            open(url: url)
        }
    }

    func open(url: URL) {
        guard editor != nil else {
            pendingOpenURL = url
            return
        }
        do {
            let data = try Data(contentsOf: url)
            guard let text = Self.decodeText(data) else {
                showToast("无法识别文件编码")
                return
            }
            load(text: text, fileName: url.lastPathComponent)
        } catch {
            showToast("打开失败：\(error.localizedDescription)")
        }
    }

    func loadDemo() {
        load(text: DemoJSON.text, fileName: "示例.json")
    }

    private func load(text: String, fileName: String?) {
        self.fileName = fileName
        self.toast = nil
        shouldRevealErrorAfterParse = true
        editor?.replaceAllText(text, undoable: false)
        undoManager.removeAllActions()
        refreshUndoState()
        expandedKeys = []
        autoExpandRootOnNextParse = true
        treeUI.selectedRowID = nil
        tree.pendingScrollTarget = nil
        searchResult = .empty
        currentHitIndex = nil
        editor?.setSearchHighlights(ranges: [], current: nil)
        scheduleParse(text, immediate: true)
        showToast(fileName == nil ? "已载入内容" : "已打开 \(fileName!)")
        editor?.focus()
    }

    private static func decodeText(_ data: Data) -> String? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(decoding: data.dropFirst(3), as: UTF8.self)
        }
        if data.starts(with: [0xFF, 0xFE]) {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        }
        if data.starts(with: [0xFE, 0xFF]) {
            return String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    // MARK: - 复制

    func copyAll() {
        let text = editor?.text ?? ""
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        showToast("已复制 \((text as NSString).length) 个字符到剪贴板")
    }

    func copyNodeValue(_ node: JSONNode) {
        let text = (editor?.text ?? lastText) as NSString
        var value = JSONFormatter.literal(node)
        let end = node.range.location + node.range.length
        if node.range.location >= 0, end <= text.length {
            value = text.substring(with: node.range)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        showToast("已复制节点值")
    }

    func copyText(_ value: String, message: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        showToast(message)
    }

    // MARK: - 错误跳转与提示

    func jumpToError() {
        guard case .error(let error) = parseState else { return }
        let location = min(max(0, error.utf16Offset), characterCount)
        editor?.reveal(NSRange(location: location, length: 0), select: false)
    }

    func showToast(_ message: String) {
        toast = message
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            if self?.toast == message { self?.toast = nil }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }
}
