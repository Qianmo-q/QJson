import JSONCore
import SwiftUI

struct TreePaneView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var tree: TreeStore

    var body: some View {
        VStack(spacing: 0) {
            SearchBarView(model: model)
            Rectangle().fill(Theme.border).frame(height: 1)
            if !model.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty,
               model.searchResult.totalCount > 0 || model.isSearching {
                SearchResultsView(model: model)
                    .frame(height: resultsHeight)
                Rectangle().fill(Theme.border).frame(height: 1)
            }
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            TreeContentView(model: model, tree: tree)
        }
        .background(Theme.panelBackground)
    }

    private var resultsHeight: CGFloat {
        let rows = max(1, min(model.searchResult.hits.count, 5))
        return min(260, CGFloat(rows) * 50 + 6)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("树形预览")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.secondaryText)
            if tree.truncated {
                Text("（行数已截断）")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.secondaryText)
            }
            Spacer()
            Button { model.expandAll() } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .help("展开全部")
            .disabled(model.root == nil)
            Button { model.collapseAll() } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .help("折叠全部")
            .disabled(model.root == nil)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Theme.panelBackground)
    }
}

struct TreeContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var tree: TreeStore
    @State private var addingContainerID: Int?
    @State private var addInsertionNodeIndex: Int?
    @State private var addContainerRow: JSONTreeRow?
    @State private var deleteRequest: DeleteRequest?

    var body: some View {
        ZStack {
            Theme.background
            if tree.rows.isEmpty {
                emptyState
            } else {
                TreeTable(
                    model: model,
                    tree: tree,
                    ui: model.treeUI,
                    addInsertionNodeIndex: addInsertionNodeIndex,
                    addContainerRow: addContainerRow,
                    onAdd: { beginAdd($0) },
                    onDelete: { deleteRequest = DeleteRequest(node: $0.node) },
                    onCloseAdd: { closeAdd() }
                )
            }
        }
        .alert(
            "删除节点",
            isPresented: Binding(
                get: { deleteRequest != nil },
                set: { if !$0 { deleteRequest = nil } }
            ),
            presenting: deleteRequest
        ) { request in
            Button("删除", role: .destructive) {
                model.deleteNode(request.node)
                deleteRequest = nil
            }
            Button("取消", role: .cancel) { deleteRequest = nil }
        } message: { request in
            let name = request.node.key.map { "“\($0)”" } ?? "该元素"
            Text("将删除 \(name) 及其全部子节点，可通过撤销恢复。")
        }
        .onChange(of: tree.rows.count) { _, _ in refreshAddRow() }
        .onChange(of: addingContainerID) { _, _ in refreshAddRow() }
    }

    private func beginAdd(_ row: JSONTreeRow) {
        model.treeUI.endEditing()
        model.expandContainer(rowID: row.id)
        addingContainerID = row.id
        refreshAddRow()
    }

    private func closeAdd() {
        addingContainerID = nil
        addInsertionNodeIndex = nil
        addContainerRow = nil
    }

    private func refreshAddRow() {
        guard let containerID = addingContainerID,
              let index = tree.rows.firstIndex(where: { $0.id == containerID }) else {
            addInsertionNodeIndex = nil
            addContainerRow = nil
            return
        }
        var insertion = index + 1
        let depth = tree.rows[index].depth
        while insertion < tree.rows.count, tree.rows[insertion].depth > depth {
            insertion += 1
        }
        addInsertionNodeIndex = insertion
        addContainerRow = tree.rows[index]
    }

    @ViewBuilder
    private var emptyState: some View {
        if case .error(let error) = model.parseState {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 22))
                    .foregroundColor(Theme.errorText)
                Text("JSON 不合法，无法生成树形预览")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
                Text("第 \(error.line) 行第 \(error.column) 列：\(error.message)")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.errorText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                Button("跳转到错误") { model.jumpToError() }
                    .buttonStyle(.link)
            }
        } else if model.isParsing {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("解析中…").font(.system(size: 12)).foregroundColor(Theme.secondaryText)
            }
        } else if model.root == nil {
            VStack(spacing: 6) {
                Image(systemName: "curlybraces")
                    .font(.system(size: 22))
                    .foregroundColor(Theme.secondaryText)
                Text("打开文件或载入示例以查看树形结构")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
            }
        }
    }
}

struct TreeRowView: View {
    let model: AppModel
    @ObservedObject var ui: TreeUIState
    let row: JSONTreeRow
    let onAdd: () -> Void
    let onDelete: () -> Void

    private enum FocusField {
        case key
        case value
    }

    @State private var keyDraft = ""
    @State private var valueDraft = ""
    @State private var keyInvalid = false
    @State private var suppressFocusCommit = false
    @FocusState private var focus: FocusField?

    private var node: JSONNode { row.node }
    private var isSelected: Bool { ui.selectedRowID == row.id }
    private var isHovered: Bool { ui.hoveredRowID == row.id }
    private var isEditingKey: Bool { ui.editingRowID == row.id && ui.editingKey }
    private var isEditingValue: Bool { ui.editingRowID == row.id && !ui.editingKey }
    private var isEditingAny: Bool { isEditingKey || isEditingValue }
    private var parsedValue: (raw: String, type: JSONLiteralType)? { JSONLiteralInput.parse(valueDraft) }

    var body: some View {
        HStack(spacing: 3) {
            Color.clear.frame(width: CGFloat(row.depth) * 14, height: 1)
            if node.isContainer {
                Button {
                    model.toggleExpansion(rowID: row.id)
                } label: {
                    Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Theme.secondaryText)
                        .frame(width: 12, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 12, height: 16)
            }

            keyPart

            if isEditingValue {
                valueEditor
            } else {
                valueView
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { beginValueEditing() }
                    .onTapGesture { activateRow() }
            }

            if node.isContainer {
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.accent.opacity(0.85))
                }
                .buttonStyle(.plain)
                .help(node.kind == .object ? "添加键值对" : "添加元素")
            }

            if isHovered && node.parent != nil && !isEditingAny {
                Button(action: onDelete) {
                    Text("删除")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.errorText, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("删除该节点")
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .contentShape(Rectangle())
        .onTapGesture { activateRow() }
        .contextMenu { contextMenu }
    }

    @ViewBuilder
    private var keyPart: some View {
        if let key = node.key {
            if isEditingKey {
                keyEditor
                Text(":")
                    .font(Theme.treeFont)
                    .foregroundColor(Theme.punctuation)
            } else {
                (Text(key).foregroundColor(Theme.key)
                    + Text(":").foregroundColor(Theme.punctuation))
                    .font(Theme.treeFont)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { beginKeyEditing() }
                    .onTapGesture { activateRow() }
            }
        } else if let index = node.indexInParent, node.parent != nil {
            Text("[\(index)]")
                .font(Theme.treeFont)
                .foregroundColor(Theme.secondaryText)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("复制值") { model.copyNodeValue(node) }
        if let key = node.key {
            Button("复制键") { model.copyText(key, message: "已复制键") }
        }
        Divider()
        if node.key != nil {
            Button("编辑键名") { beginKeyEditing() }
        }
        if !node.isContainer {
            Button("编辑值") { beginValueEditing() }
        }
        if node.isContainer {
            Button(node.kind == .object ? "添加键值对" : "添加元素") { onAdd() }
        }
        Divider()
        Button("删除节点", role: .destructive) { onDelete() }
            .disabled(node.parent == nil)
    }

    private var background: Color {
        if isSelected { return Theme.selectedRow }
        if isHovered { return Color(nsColor: Palette.hoverBackground) }
        return Color.clear
    }

    // MARK: - 内联编辑

    private func activateRow() {
        ui.commitToken += 1
        guard ui.editingRowID != row.id else { return }
        ui.selectedRowID = row.id
        model.treeSelectionDidChange(row: row)
        if node.isContainer {
            model.toggleExpansion(rowID: row.id)
        }
    }

    private func beginKeyEditing() {
        guard let key = node.key else { return }
        keyDraft = key
        keyInvalid = false
        ui.editingKey = true
        ui.editingRowID = row.id
        DispatchQueue.main.async { focus = .key }
    }

    private func beginValueEditing() {
        guard !node.isContainer else { return }
        valueDraft = literalValue(for: node)
        ui.editingKey = false
        ui.editingRowID = row.id
        DispatchQueue.main.async { focus = .value }
    }

    private func literalValue(for node: JSONNode) -> String {
        switch node.kind {
        case .string: return jsonStringLiteral(from: node.stringValue ?? "")
        case .number: return node.numberText ?? "0"
        case .bool: return (node.boolValue ?? false) ? "true" : "false"
        case .null: return "null"
        case .object, .array: return JSONFormatter.minified(node)
        }
    }

    private func endEditing() {
        suppressFocusCommit = true
        ui.endEditing()
        DispatchQueue.main.async { suppressFocusCommit = false }
    }

    private func cancelEditing() {
        endEditing()
    }

    private func commitKey() {
        let trimmed = keyDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            keyInvalid = true
            model.showToast("键名不能为空")
            return
        }
        if let failure = model.renameKey(node: node, newKey: trimmed) {
            keyInvalid = true
            model.showToast(failure)
            return
        }
        endEditing()
    }

    private func commitValue() {
        guard let parsed = parsedValue else {
            model.showToast("请输入合法的 JSON 值，例如 \"文本\"、123、true、{}、[]")
            return
        }
        endEditing()
        model.applyValueEdit(node: node, rawValue: parsed.raw)
    }

    private var keyEditor: some View {
        HStack(spacing: 4) {
            TextField("键名", text: $keyDraft)
                .textFieldStyle(.plain)
                .font(Theme.treeFont)
                .foregroundColor(Theme.text)
                .focused($focus, equals: .key)
                .onSubmit { commitKey() }
                .onExitCommand { cancelEditing() }
                .onChange(of: keyDraft) { _, _ in keyInvalid = false }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(minWidth: 90, idealWidth: 170, maxWidth: 170)
                .background(Theme.controlBackground, in: RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(keyInvalid ? Theme.errorText : Theme.accent, lineWidth: 1.5)
                }
        }
        .onChange(of: focus) { _, newValue in
            guard newValue == nil, !suppressFocusCommit else { return }
            commitKey()
        }
        .onChange(of: ui.commitToken) { _, _ in commitKey() }
    }

    private var valueEditor: some View {
        HStack(spacing: 4) {
            TextField("JSON 值，如 \"文本\"、123、true、{}、[]", text: $valueDraft)
                .textFieldStyle(.plain)
                .font(Theme.treeFont)
                .foregroundColor(Theme.text)
                .focused($focus, equals: .value)
                .onSubmit { commitValue() }
                .onExitCommand { cancelEditing() }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(minWidth: 140, idealWidth: 300, maxWidth: 300)
                .background(Theme.controlBackground, in: RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(parsedValue == nil ? Theme.errorText : Theme.accent, lineWidth: 1.5)
                }
            Text(parsedValue?.type.label ?? "非法 JSON")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(parsedValue == nil ? Theme.errorText : Theme.secondaryText)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Theme.controlBackground, in: Capsule())
        }
        .onChange(of: focus) { _, newValue in
            guard newValue == nil, !suppressFocusCommit else { return }
            commitValue()
        }
        .onChange(of: ui.commitToken) { _, _ in commitValue() }
    }

    @ViewBuilder
    private var valueView: some View {
        switch node.kind {
        case .object:
            Text("{ \(node.children.count) }")
                .font(Theme.treeFont)
                .foregroundColor(Theme.punctuation)
        case .array:
            Text("[ \(node.children.count) ]")
                .font(Theme.treeFont)
                .foregroundColor(Theme.punctuation)
        case .string:
            Text("\"\(preview(node.stringValue ?? ""))\"")
                .font(Theme.treeFont)
                .foregroundColor(Theme.string)
                .lineLimit(1)
                .truncationMode(.tail)
        case .number:
            Text(node.numberText ?? "")
                .font(Theme.treeFont)
                .foregroundColor(Theme.number)
                .lineLimit(1)
        case .bool:
            Text((node.boolValue ?? false) ? "true" : "false")
                .font(Theme.treeFont)
                .foregroundColor(Theme.boolean)
        case .null:
            Text("null")
                .font(Theme.treeFont)
                .foregroundColor(Theme.null)
        }
    }

    private func preview(_ value: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        if cleaned.count > 240 {
            return String(cleaned.prefix(240)) + "…"
        }
        return cleaned
    }
}

struct DeleteRequest: Identifiable {
    let node: JSONNode
    var id: Int { node.range.location }
}

enum JSONLiteralType {
    case string
    case number
    case boolean
    case null
    case object
    case array

    var label: String {
        switch self {
        case .string: return "字符串"
        case .number: return "数字"
        case .boolean: return "布尔"
        case .null: return "null"
        case .object: return "对象"
        case .array: return "数组"
        }
    }

    init(kind: JSONKind) {
        switch kind {
        case .string: self = .string
        case .number: self = .number
        case .bool: self = .boolean
        case .null: self = .null
        case .object: self = .object
        case .array: self = .array
        }
    }
}

enum JSONLiteralInput {
    /// 解析用户输入的 JSON 字面量；类型由输入本身决定。
    static func parse(_ text: String) -> (raw: String, type: JSONLiteralType)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let result = JSONParser.parse(trimmed)
        guard result.error == nil, let root = result.root else { return nil }
        return (trimmed, JSONLiteralType(kind: root.kind))
    }
}

struct InlineAddRow: View {
    let model: AppModel
    let container: JSONTreeRow
    let onClose: () -> Void

    @State private var keyText = ""
    @State private var valueText = "\"\""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case key
        case value
    }

    private var isArray: Bool { container.node.kind == .array }
    private var parsedValue: (raw: String, type: JSONLiteralType)? { JSONLiteralInput.parse(valueText) }

    var body: some View {
            HStack(spacing: 5) {
                Color.clear.frame(width: CGFloat(container.depth + 1) * 14, height: 1)
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Theme.secondaryText)
                if !isArray {
                    field("键", text: $keyText, minWidth: 80, idealWidth: 130, maxWidth: 130, focus: .key) {
                        focusedField = .value
                    }
                    Text(":")
                        .font(Theme.treeFont)
                        .foregroundColor(Theme.punctuation)
                }
                field("JSON 值，如 \"文本\"", text: $valueText, minWidth: 110, idealWidth: 230, maxWidth: 230, focus: .value) {
                    commit()
                }
                Text(parsedValue?.type.label ?? "非法 JSON")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(parsedValue == nil ? Theme.errorText : Theme.secondaryText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Theme.controlBackground, in: Capsule())
                Button("添加") { commit() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                Button("取消") { onClose() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
            }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(Color(nsColor: Palette.hoverBackground))
        .onAppear {
            DispatchQueue.main.async {
                focusedField = isArray ? .value : .key
            }
        }
        .onExitCommand { onClose() }
    }

    private func field(
        _ placeholder: String,
        text: Binding<String>,
        minWidth: CGFloat,
        idealWidth: CGFloat,
        maxWidth: CGFloat,
        focus: Field,
        onSubmit: @escaping () -> Void
    ) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(Theme.treeFont)
            .foregroundColor(Theme.text)
            .focused($focusedField, equals: focus)
            .onSubmit(onSubmit)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth)
            .background(Theme.controlBackground, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5).stroke(Theme.border, lineWidth: 1)
            }
    }

    private func commit() {
        guard let parsed = parsedValue else {
            model.showToast("请输入合法的 JSON 值，例如 \"文本\"、123、true、{}、[]")
            return
        }
        var failure: String?
        if isArray {
            failure = model.addElement(
                to: container.node,
                rawValue: parsed.raw
            )
        } else {
            let key = keyText.trimmingCharacters(in: .whitespaces)
            if key.isEmpty {
                failure = "键名不能为空"
            } else {
                failure = model.addMember(
                    to: container.node,
                    key: key,
                    rawValue: parsed.raw
                )
            }
        }
        if let failure {
            model.showToast(failure)
        } else {
            onClose()
        }
    }
}
