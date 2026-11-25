import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum SplitAxis {
    case horizontal
    case vertical
}

enum PaneViewMode {
    case editor
    case tree
}

struct WorkspaceTab: Identifiable {
    let id = UUID()
    let model: AppModel
    var viewMode: PaneViewMode = .editor

    var title: String { model.fileName ?? "未命名" }
    var documentID: UUID? { model.openDocument?.id }
}

struct WorkspacePane: Identifiable {
    let id: UUID
    var tabs: [WorkspaceTab]
    var activeTabID: UUID
    var splitAxis: SplitAxis?
    var children: [WorkspacePane]

    var isLeaf: Bool { children.isEmpty }

    init(tabs: [WorkspaceTab], activeTabID: UUID? = nil, splitAxis: SplitAxis? = nil, children: [WorkspacePane] = []) {
        self.id = UUID()
        self.tabs = tabs
        self.activeTabID = activeTabID ?? tabs.first?.id ?? UUID()
        self.splitAxis = splitAxis
        self.children = children
    }

    var activeTab: WorkspaceTab? {
        tabs.first { $0.id == activeTabID } ?? tabs.first
    }
}

final class WorkspaceModel: ObservableObject {
    @Published private(set) var documents: [OpenDocument] = []
    @Published private(set) var rootPane: WorkspacePane
    @Published var focusedPaneID: UUID
    @Published var sidebarVisible = true
    @Published var toast: String?

    @Published var appearanceMode: AppearanceMode {
        didSet {
            guard appearanceMode != oldValue else { return }
            applyAppearance()
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: Self.appearanceDefaultsKey)
        }
    }

    @Published var indentWidth: Int {
        didSet {
            guard indentWidth != oldValue else { return }
            UserDefaults.standard.set(indentWidth, forKey: Self.indentDefaultsKey)
        }
    }

    @Published var syncSelection: Bool {
        didSet {
            guard syncSelection != oldValue else { return }
            UserDefaults.standard.set(syncSelection, forKey: Self.syncDefaultsKey)
        }
    }

    private var toastWork: DispatchWorkItem?
    private static let appearanceDefaultsKey = "QJson.appearanceMode"
    private static let syncDefaultsKey = "QJson.syncSelection"
    private static let indentDefaultsKey = "QJson.indentWidth"

    init() {
        let defaults = UserDefaults.standard
        appearanceMode = AppearanceMode(rawValue: defaults.string(forKey: Self.appearanceDefaultsKey) ?? "") ?? .system
        syncSelection = defaults.object(forKey: Self.syncDefaultsKey) == nil ? true : defaults.bool(forKey: Self.syncDefaultsKey)
        indentWidth = defaults.integer(forKey: Self.indentDefaultsKey) == 4 ? 4 : 2
        let tab = WorkspaceTab(model: AppModel(workspace: nil))
        let pane = WorkspacePane(tabs: [tab])
        rootPane = pane
        focusedPaneID = pane.id
        tab.model.workspace = self
        applyAppearance()
    }

    var isSplit: Bool { countLeaves(in: rootPane) > 1 }
    var activeTab: WorkspaceTab? { activeTab(in: rootPane, paneID: focusedPaneID) }
    var activeModel: AppModel? { activeTab?.model }
    var windowTitle: String {
        guard let title = activeTab?.title else { return "QJson" }
        return "\(title) — QJson"
    }

    func showToast(_ message: String) {
        toast = message
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.toast == message else { return }
            self.toast = nil
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }

    private func applyAppearance() {
        NSApplication.shared.appearance = appearanceMode.appearance
    }

    // MARK: - Tabs

    func newTab(in paneID: UUID? = nil) {
        guard let targetID = paneID ?? focusedLeafID() else { return }
        insertTab(WorkspaceTab(model: AppModel(workspace: self)), in: targetID)
    }

    func newTab(for document: OpenDocument) {
        guard let paneID = focusedLeafID() else { return }
        let model = AppModel(workspace: self, document: document)
        insertTab(WorkspaceTab(model: model), in: paneID)
    }

    private func insertTab(_ tab: WorkspaceTab, in paneID: UUID) {
        guard updatePane(paneID, { pane in
            pane.tabs.append(tab)
            pane.activeTabID = tab.id
        }) else { return }
        focusedPaneID = paneID
    }

    func activate(tab: WorkspaceTab, in paneID: UUID) {
        guard updatePane(paneID, activate: tab.id) else { return }
        focusedPaneID = paneID
    }

    func closeActiveTab() {
        guard let tab = activeTab else { return }
        close(tabID: tab.id)
    }

    func close(tabID: UUID) {
        guard let location = locateTab(tabID) else { return }
        let model = location.tab.model
        if let document = model.openDocument, tabCount(for: document.id) == 1, document.isDirty,
           !confirmDiscard(fileName: document.fileName) {
            return
        }
        guard updatePane(location.paneID, { pane in
            pane.tabs.removeAll { $0.id == tabID }
            if pane.activeTabID == tabID {
                pane.activeTabID = pane.tabs.last?.id ?? pane.activeTabID
            }
        }) else { return }
        if let document = model.openDocument, tabCount(for: document.id) == 0 {
            documents.removeAll { $0.id == document.id }
        }
        if findPane(location.paneID)?.tabs.isEmpty == true {
            if countLeaves(in: rootPane) > 1 {
                closePane(paneID: location.paneID)
            } else {
                let replacement = WorkspaceTab(model: AppModel(workspace: self))
                guard updatePane(location.paneID, { pane in
                    pane.tabs = [replacement]
                    pane.activeTabID = replacement.id
                }) else { return }
                focusedPaneID = location.paneID
            }
        }
    }

    func closeOtherTabs(except tabID: UUID, in paneID: UUID) {
        guard let pane = findPane(paneID), pane.isLeaf else { return }
        let remaining = pane.tabs.first { $0.id == tabID }
        for tab in pane.tabs where tab.id != tabID { close(tabID: tab.id) }
        if let remaining, let current = findPane(paneID)?.activeTab, current.id != remaining.id {
            _ = updatePane(paneID, activate: remaining.id)
        }
    }

    func closeTabsToRight(of tabID: UUID, in paneID: UUID) {
        guard let pane = findPane(paneID), pane.isLeaf,
              let index = pane.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        for tab in pane.tabs.dropFirst(index + 1) { close(tabID: tab.id) }
    }

    private func confirmDiscard(fileName: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "放弃对“\(fileName)”的修改？"
        alert.informativeText = "这是最后一个标签页，关闭后未保存内容将丢失。"
        alert.addButton(withTitle: "放弃修改")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Documents

    @discardableResult
    func createDocument(text: String, fileName: String?, fileURL: URL? = nil) -> OpenDocument {
        let document = OpenDocument(text: text, fileName: fileName, fileURL: fileURL)
        documents.append(document)
        return document
    }

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

    func open(url: URL, forceNewTab: Bool = false) {
        do {
            let data = try Data(contentsOf: url)
            guard let text = AppModel.decodeText(data) else {
                showToast("无法识别文件编码")
                return
            }
            let normalized = url.standardizedFileURL
            let document = documents.first { $0.fileURL?.standardizedFileURL == normalized }
                ?? createDocument(text: text, fileName: url.lastPathComponent, fileURL: normalized)
            open(document, forceNewTab: forceNewTab)
            showToast("已打开 \(document.fileName)")
        } catch {
            showToast("打开失败：\(error.localizedDescription)")
        }
    }

    func open(_ document: OpenDocument, forceNewTab: Bool = false) {
        if !forceNewTab, let location = tabs(for: document.id).last {
            activate(tab: location.tab, in: location.paneID)
            return
        }
        guard let paneID = focusedLeafID(), let pane = findPane(paneID), pane.isLeaf else { return }
        if let empty = pane.activeTab, empty.model.isEmpty {
            empty.model.bind(document)
            _ = updatePane(paneID, activate: empty.id)
        } else {
            newTab(for: document)
        }
        focusedPaneID = paneID
    }

    func loadDemo() {
        let document = documents.first { $0.fileURL == nil && $0.fileName == "示例.json" }
            ?? createDocument(text: DemoJSON.text, fileName: "示例.json")
        open(document)
        showToast("已载入示例")
    }

    func revealInEditor(_ model: AppModel) {
        guard let tab = allTabs().first(where: { $0.tab.model === model }),
              let paneID = paneID(for: tab.tab.id) else { return }
        setActiveViewMode(.editor, in: paneID)
    }

    func showEditor(for model: AppModel) {
        revealInEditor(model)
    }

    func focus(_ model: AppModel) {
        guard let location = allTabs().first(where: { $0.tab.model === model }),
              findPane(location.paneID)?.activeTab?.model === model else { return }
        focusedPaneID = location.paneID
    }

    // MARK: - Panes

    func splitFocusedPane(axis: SplitAxis) {
        guard let paneID = focusedLeafID(), let source = findPane(paneID), source.isLeaf else { return }
        let newTab = WorkspaceTab(model: AppModel(workspace: self))
        let newPane = WorkspacePane(tabs: [newTab])
        if insertSiblingPane(newPane, after: paneID, axis: axis) {
            focusedPaneID = newPane.id
            return
        }
        guard replacePane(paneID, { pane in
            pane = WorkspacePane(
                tabs: [],
                activeTabID: source.id,
                splitAxis: axis,
                children: [source, newPane]
            )
        }) else { return }
        focusedPaneID = newPane.id
    }

    private func insertSiblingPane(
        _ newPane: WorkspacePane,
        after paneID: UUID,
        axis: SplitAxis
    ) -> Bool {
        var updated = rootPane
        guard insertSiblingPane(newPane, after: paneID, axis: axis, in: &updated) else { return false }
        rootPane = updated
        return true
    }

    private func insertSiblingPane(
        _ newPane: WorkspacePane,
        after paneID: UUID,
        axis: SplitAxis,
        in pane: inout WorkspacePane
    ) -> Bool {
        guard !pane.isLeaf else { return false }
        if pane.splitAxis == axis,
           let index = pane.children.firstIndex(where: { $0.id == paneID }) {
            pane.children.insert(newPane, at: index + 1)
            return true
        }
        for index in pane.children.indices {
            if insertSiblingPane(newPane, after: paneID, axis: axis, in: &pane.children[index]) {
                return true
            }
        }
        return false
    }

    func closeFocusedPane() {
        guard let paneID = focusedLeafID() else { return }
        closePane(paneID: paneID)
    }

    private func closePane(paneID: UUID) {
        guard countLeaves(in: rootPane) > 1, let closingPane = findPane(paneID), closingPane.isLeaf else { return }
        let closingDocumentIDs = Set(closingPane.tabs.compactMap(\.documentID))
        for documentID in closingDocumentIDs {
            guard let document = documents.first(where: { $0.id == documentID }) else { continue }
            let closingCount = closingPane.tabs.filter { $0.documentID == documentID }.count
            if document.isDirty, tabCount(for: documentID) == closingCount, !confirmDiscard(fileName: document.fileName) {
                return
            }
        }

        let previousFocus = focusedPaneID
        var updated = rootPane
        guard removePane(paneID, from: &updated) else { return }
        rootPane = updated
        if findPane(previousFocus)?.isLeaf != true, let survivor = firstLeafID(in: rootPane) {
            focusedPaneID = survivor
        }
        pruneDocuments()
    }

    private func removePane(_ paneID: UUID, from pane: inout WorkspacePane) -> Bool {
        if let replacement = removePaneNode(paneID, from: &pane) {
            pane = replacement
            return true
        }
        return pane.isLeaf && pane.id == paneID
    }

    private func removePaneNode(_ paneID: UUID, from pane: inout WorkspacePane) -> WorkspacePane? {
        if pane.isLeaf {
            return pane.id == paneID ? nil : pane
        }
        for index in pane.children.indices where containsLeaf(paneID, in: pane.children[index]) {
            if let replacement = removePaneNode(paneID, from: &pane.children[index]) {
                pane.children[index] = replacement
            } else {
                pane.children.remove(at: index)
            }
            break
        }
        if pane.children.count == 1 { return pane.children[0] }
        return pane.children.isEmpty ? nil : pane
    }

    private func pruneDocuments() {
        let openIDs = Set(allTabs().compactMap { $0.tab.documentID })
        documents.removeAll { !openIDs.contains($0.id) }
    }

    // MARK: - View state

    func setViewMode(_ mode: PaneViewMode, in paneID: UUID) {
        guard updatePane(paneID, { pane in
            guard let index = pane.tabs.firstIndex(where: { $0.id == pane.activeTabID }) else { return }
            pane.tabs[index].viewMode = mode
        }) else { return }
        focusedPaneID = paneID
    }

    private func setActiveViewMode(_ mode: PaneViewMode, in paneID: UUID) {
        setViewMode(mode, in: paneID)
    }

    func nextTab(in paneID: UUID? = nil) {
        guard let id = paneID ?? focusedLeafID(), let pane = findPane(id), pane.isLeaf else { return }
        guard let index = pane.tabs.firstIndex(where: { $0.id == pane.activeTabID }) else { return }
        let next = pane.tabs[(index + 1) % pane.tabs.count]
        activate(tab: next, in: id)
    }

    func previousTab(in paneID: UUID? = nil) {
        guard let id = paneID ?? focusedLeafID(), let pane = findPane(id), pane.isLeaf else { return }
        guard let index = pane.tabs.firstIndex(where: { $0.id == pane.activeTabID }) else { return }
        let previous = pane.tabs[(index - 1 + pane.tabs.count) % pane.tabs.count]
        activate(tab: previous, in: id)
    }

    // MARK: - Tree helpers

    private func updatePane(_ paneID: UUID, activate tabID: UUID? = nil, _ body: (inout WorkspacePane) -> Void = { _ in }) -> Bool {
        guard updatePane(paneID, activate: tabID, in: &rootPane, body) else { return false }
        return true
    }

    private func updatePane(_ paneID: UUID, activate tabID: UUID?, in pane: inout WorkspacePane, _ body: (inout WorkspacePane) -> Void) -> Bool {
        if pane.isLeaf {
            guard pane.id == paneID else { return false }
            body(&pane)
            if let tabID { pane.activeTabID = tabID }
            return true
        }
        for index in pane.children.indices {
            if updatePane(paneID, activate: tabID, in: &pane.children[index], body) { return true }
        }
        return false
    }

    private func replacePane(_ paneID: UUID, _ body: (inout WorkspacePane) -> Void) -> Bool {
        guard replacePane(paneID, in: &rootPane, body) else { return false }
        return true
    }

    private func replacePane(_ paneID: UUID, in pane: inout WorkspacePane, _ body: (inout WorkspacePane) -> Void) -> Bool {
        if pane.isLeaf {
            guard pane.id == paneID else { return false }
            body(&pane)
            return true
        }
        for index in pane.children.indices {
            if replacePane(paneID, in: &pane.children[index], body) { return true }
        }
        return false
    }

    private func findPane(_ paneID: UUID, in pane: WorkspacePane? = nil) -> WorkspacePane? {
        let current = pane ?? rootPane
        if current.id == paneID { return current }
        for child in current.children {
            if let found = findPane(paneID, in: child) { return found }
        }
        return nil
    }

    private func locateTab(_ tabID: UUID, in pane: WorkspacePane? = nil) -> (tab: WorkspaceTab, paneID: UUID)? {
        let current = pane ?? rootPane
        if let tab = current.tabs.first(where: { $0.id == tabID }) { return (tab, current.id) }
        for child in current.children {
            if let found = locateTab(tabID, in: child) { return found }
        }
        return nil
    }

    private func paneID(for tabID: UUID) -> UUID? { locateTab(tabID)?.paneID }

    private func tabs(for documentID: UUID) -> [(tab: WorkspaceTab, paneID: UUID)] {
        allTabs().filter { $0.tab.documentID == documentID }
    }

    private func allTabs(in pane: WorkspacePane? = nil) -> [(tab: WorkspaceTab, paneID: UUID)] {
        let current = pane ?? rootPane
        var result = current.tabs.map { (tab: $0, paneID: current.id) }
        for child in current.children { result.append(contentsOf: allTabs(in: child)) }
        return result
    }

    private func tabCount(for documentID: UUID) -> Int { tabs(for: documentID).count }

    func documentsTabCount(_ documentID: UUID) -> Int { tabCount(for: documentID) }

    private func activeTab(in pane: WorkspacePane, paneID: UUID) -> WorkspaceTab? {
        if pane.isLeaf { return pane.id == paneID ? pane.activeTab : nil }
        for child in pane.children {
            if let tab = activeTab(in: child, paneID: paneID) { return tab }
        }
        return nil
    }

    private func focusedLeafID() -> UUID? {
        if let pane = findPane(focusedPaneID), pane.isLeaf { return pane.id }
        return firstLeafID(in: rootPane)
    }

    private func firstLeafID(in pane: WorkspacePane) -> UUID? {
        pane.isLeaf ? pane.id : pane.children.first.flatMap { firstLeafID(in: $0) }
    }

    private func countLeaves(in pane: WorkspacePane) -> Int {
        pane.isLeaf ? 1 : pane.children.reduce(0) { $0 + countLeaves(in: $1) }
    }

    private func containsLeaf(_ paneID: UUID, in pane: WorkspacePane) -> Bool {
        if pane.isLeaf { return pane.id == paneID }
        return pane.children.contains { containsLeaf(paneID, in: $0) }
    }
}
