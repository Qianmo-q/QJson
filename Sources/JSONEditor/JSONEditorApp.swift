import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var workspace: WorkspaceModel
    @State private var isDropTargeted = false
    @State private var sidebarQuery = ""

    var body: some View {
        HStack(spacing: 0) {
            if workspace.sidebarVisible {
                SidebarView(workspace: workspace, query: $sidebarQuery)
                Rectangle().fill(Theme.border).frame(width: 1)
            }
            VStack(spacing: 0) {
                WorkspaceCanvasView(workspace: workspace)
                StatusBarView(workspace: workspace)
            }
        }
        .background(Theme.background)
        .overlay(alignment: .bottomTrailing) { toastView }
        .overlay { dropOverlay }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .toolbar { toolbarContent }
        .navigationTitle(workspace.windowTitle)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                workspace.sidebarVisible.toggle()
            } label: {
                Label("侧边栏", systemImage: "sidebar.left")
            }
            .help("显示或隐藏侧边栏")
            Button {
                workspace.openFilePanel()
            } label: {
                Label("打开", systemImage: "folder")
            }
            .help("打开 JSON 文件（⌘O）")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                workspace.activeModel?.format(indent: workspace.indentWidth)
            } label: {
                Text("格式化")
                    .font(.system(size: 12, weight: .medium))
            }
            .help("格式化（当前缩进 \(workspace.indentWidth) 空格）")
            .disabled(workspace.activeModel?.isEmpty != false)

            Picker("缩进", selection: $workspace.indentWidth) {
                Text("2 空格").tag(2)
                Text("4 空格").tag(4)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 128)
            .help("格式化缩进宽度")

            Button {
                workspace.loadDemo()
            } label: {
                Label("示例", systemImage: "doc.text")
            }
            .help("载入内置示例")

            Button {
                workspace.activeModel?.copyAll()
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .help("复制全部内容（⇧⌘C）")
            .disabled(workspace.activeModel?.isEmpty != false)
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast = workspace.toast {
            Text(toast)
                .font(.system(size: 11))
                .foregroundColor(Theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                .padding(.trailing, 16)
                .padding(.bottom, 40)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var dropOverlay: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .padding(8)
                .overlay {
                    Text("释放以打开 JSON 文件")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                }
                .allowsHitTesting(false)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let value = item as? URL {
                url = value
            }
            guard let url else { return }
            DispatchQueue.main.async {
                workspace.open(url: url)
            }
        }
        return true
    }
}

struct SidebarView: View {
    @ObservedObject var workspace: WorkspaceModel
    @Binding var query: String

    private var filteredDocuments: [OpenDocument] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return workspace.documents }
        return workspace.documents.filter { $0.fileName.localizedCaseInsensitiveContains(keyword) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
                TextField("搜索文档", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .frame(height: 34)

            ScrollView {
                LazyVStack(spacing: 2) {
                    if filteredDocuments.isEmpty {
                        Text(workspace.documents.isEmpty ? "还没有打开文档" : "没有匹配的文档")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 12)
                    }
                    ForEach(filteredDocuments) { document in
                        SidebarDocumentRow(workspace: workspace, document: document)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }

            Rectangle().fill(Theme.border).frame(height: 1)
            Button {
                workspace.newTab()
            } label: {
                Label("新建空标签页", systemImage: "plus")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            Button {
                workspace.openFilePanel()
            } label: {
                Label("打开文件…", systemImage: "folder")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 220)
        .background(Theme.panelBackground)
    }
}

struct SidebarDocumentRow: View {
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var document: OpenDocument

    var body: some View {
        let tabCount = workspace.documentsTabCount(document.id)
        let isActive = workspace.activeTab?.documentID == document.id
        Button {
            workspace.open(document)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "doc.braces")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.accent)
                Text(document.fileName)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if document.isDirty {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                }
                if tabCount > 1 {
                    Text("\(tabCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.secondaryText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.controlBackground, in: Capsule())
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(isActive ? Theme.selectedRow : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("聚焦标签页") { workspace.open(document) }
            Button("在新标签页打开") { workspace.open(document, forceNewTab: true) }
        }
        .help(document.fileURL?.path ?? document.fileName)
    }
}

struct WorkspaceCanvasView: View {
    @ObservedObject var workspace: WorkspaceModel

    var body: some View {
        GeometryReader { geometry in
            let minimumSize = Self.minimumSize(for: workspace.rootPane)
            ScrollView([.vertical, .horizontal]) {
                WorkspaceSplitView(workspace: workspace, pane: workspace.rootPane)
                    .frame(
                        width: max(geometry.size.width, minimumSize.width),
                        height: max(geometry.size.height, minimumSize.height)
                    )
            }
        }
    }

    static func minimumSize(for pane: WorkspacePane) -> CGSize {
        if pane.isLeaf {
            return CGSize(width: 320, height: 220)
        }
        let childSizes = pane.children.map { minimumSize(for: $0) }
        guard !childSizes.isEmpty else {
            return CGSize(width: 320, height: 220)
        }
        let dividerSpace = CGFloat(childSizes.count - 1)
        if pane.splitAxis == .horizontal {
            return CGSize(
                width: childSizes.reduce(0) { $0 + $1.width } + dividerSpace,
                height: childSizes.map(\.height).max() ?? 220
            )
        }
        return CGSize(
            width: childSizes.map(\.width).max() ?? 320,
            height: childSizes.reduce(0) { $0 + $1.height } + dividerSpace
        )
    }
}

struct WorkspaceSplitView: View {
    @ObservedObject var workspace: WorkspaceModel
    let pane: WorkspacePane

    var body: some View {
        if pane.isLeaf {
            WorkspacePaneView(workspace: workspace, pane: pane)
                .id(pane.id)
        } else {
            GeometryReader { geometry in
                splitContent(size: geometry.size)
            }
        }
    }

    @ViewBuilder
    private func splitContent(size: CGSize) -> some View {
        if pane.splitAxis == .horizontal {
            let minimumWidths = pane.children.map { WorkspaceCanvasView.minimumSize(for: $0).width }
            let extraWidth = max(
                0,
                size.width - minimumWidths.reduce(0, +) - CGFloat(minimumWidths.count - 1)
            )
            HSplitView {
                ForEach(Array(pane.children.enumerated()), id: \.element.id) { index, child in
                    WorkspaceSplitView(workspace: workspace, pane: child)
                        .frame(
                            minWidth: minimumWidths[index],
                            idealWidth: minimumWidths[index] + extraWidth / CGFloat(minimumWidths.count),
                            maxWidth: .infinity
                        )
                }
            }
        } else {
            let minimumHeights = pane.children.map { WorkspaceCanvasView.minimumSize(for: $0).height }
            let extraHeight = max(
                0,
                size.height - minimumHeights.reduce(0, +) - CGFloat(minimumHeights.count - 1)
            )
            VSplitView {
                ForEach(Array(pane.children.enumerated()), id: \.element.id) { index, child in
                    WorkspaceSplitView(workspace: workspace, pane: child)
                        .frame(
                            minHeight: minimumHeights[index],
                            idealHeight: minimumHeights[index] + extraHeight / CGFloat(minimumHeights.count),
                            maxHeight: .infinity
                        )
                }
            }
        }
    }
}

struct WorkspacePaneView: View {
    @ObservedObject var workspace: WorkspaceModel
    let pane: WorkspacePane

    var body: some View {
        if let tab = pane.activeTab {
            DocumentPaneView(workspace: workspace, pane: pane, tab: tab, isSplit: workspace.isSplit)
                .id(tab.id)
        } else {
            Color.clear.onTapGesture { workspace.focusedPaneID = pane.id }
        }
    }
}

struct DocumentPaneView: View {
    @ObservedObject var workspace: WorkspaceModel
    let pane: WorkspacePane
    let tab: WorkspaceTab
    let isSplit: Bool
    @ObservedObject var model: AppModel
    @State private var leftPaneWidth: CGFloat = 0

    init(workspace: WorkspaceModel, pane: WorkspacePane, tab: WorkspaceTab, isSplit: Bool) {
        self.workspace = workspace
        self.pane = pane
        self.tab = tab
        self.isSplit = isSplit
        self._model = ObservedObject(wrappedValue: tab.model)
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            if model.isEmpty {
                EmptyTabView(workspace: workspace, model: model)
            } else if isSplit {
                PaneToolbar(workspace: workspace, model: model, mode: tab.viewMode, paneID: pane.id)
                if tab.viewMode == .editor {
                    EditorRepresentable(model: model)
                        .background(Theme.background)
                } else {
                    TreePaneView(model: model, tree: model.tree)
                }
            } else {
                dualView
            }
        }
        .frame(minWidth: 320, maxWidth: .infinity, minHeight: 220, maxHeight: .infinity)
        .background(Theme.background)
        .overlay {
            RoundedRectangle(cornerRadius: 0)
                .stroke(workspace.focusedPaneID == pane.id ? Theme.accent.opacity(0.55) : Color.clear, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { workspace.focusedPaneID = pane.id }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(pane.tabs) { item in
                        TabItemView(workspace: workspace, pane: pane, tab: item)
                            .frame(width: 146)
                    }
                }
            }
            Button {
                workspace.newTab(in: pane.id)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.secondaryText)
                    .frame(width: 30, height: 32)
            }
            .buttonStyle(.plain)
            .help("新建空标签页（⌘T）")
            if isSplit {
                Button {
                    workspace.focusedPaneID = pane.id
                    workspace.closeFocusedPane()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.secondaryText)
                        .frame(width: 28, height: 32)
                }
                .buttonStyle(.plain)
                .help("关闭窗格及其标签")
            }
        }
        .frame(height: 34)
        .background(Theme.panelBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private var dualView: some View {
        GeometryReader { proxy in
            HSplitView {
                EditorPaneView(model: model)
                    .frame(minWidth: 360, maxWidth: .infinity)
                    .background(
                        GeometryReader { inner in
                            Color.clear.onAppear { leftPaneWidth = inner.size.width }
                                .onChange(of: inner.size.width) { _, width in leftPaneWidth = width }
                        }
                    )
                TreePaneView(model: model, tree: model.tree)
                    .frame(minWidth: 300, maxWidth: .infinity)
            }
            .overlay(alignment: .topLeading) {
                if leftPaneWidth > 0 {
                    syncLockButton
                        .position(x: leftPaneWidth, y: proxy.size.height / 2)
                }
            }
        }
    }

    private var syncLockButton: some View {
        Button {
            model.toggleSyncSelection()
        } label: {
            Image(systemName: model.syncSelection ? "lock.fill" : "lock.open")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(model.syncSelection ? Theme.accent : Theme.secondaryText)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Theme.controlBackground))
                .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                .shadow(color: Color.black.opacity(0.12), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .help(model.syncSelection ? "左右选中同步已锁定，点击解锁" : "左右选中同步已解锁，点击锁定")
    }
}

struct TabItemView: View {
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var model: AppModel
    let pane: WorkspacePane
    let tab: WorkspaceTab

    init(workspace: WorkspaceModel, pane: WorkspacePane, tab: WorkspaceTab) {
        self.workspace = workspace
        self.pane = pane
        self.tab = tab
        self._model = ObservedObject(wrappedValue: tab.model)
    }

    var body: some View {
        let isActive = tab.id == pane.activeTabID
        HStack(spacing: 5) {
            if model.isDirty {
                Circle().fill(Theme.accent).frame(width: 6, height: 6)
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.secondaryText)
            }
            Text(tab.title)
                .font(.system(size: 11, weight: isActive ? .medium : .regular))
                .foregroundColor(isActive ? Theme.text : Theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button {
                workspace.close(tabID: tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(Theme.secondaryText)
                    .frame(width: 16, height: 18)
            }
            .buttonStyle(.plain)
            .opacity(isActive ? 1 : 0.65)
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(isActive ? Theme.background : Color.clear)
        .overlay(alignment: .top) {
            if isActive { Rectangle().fill(Theme.accent).frame(height: 2) }
        }
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 1) }
        .contentShape(Rectangle())
        .onTapGesture { workspace.activate(tab: tab, in: pane.id) }
        .contextMenu {
            Button("关闭标签页") { workspace.close(tabID: tab.id) }
            Button("关闭其他标签页") { workspace.closeOtherTabs(except: tab.id, in: pane.id) }
            Button("关闭右侧标签页") { workspace.closeTabsToRight(of: tab.id, in: pane.id) }
            if let document = tab.model.openDocument {
                Button("在新标签页打开同一文档") { workspace.newTab(for: document) }
            }
        }
    }
}

struct EditorPaneView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Rectangle().fill(Theme.border).frame(height: 1)
            EditorRepresentable(model: model)
                .background(Theme.background)
        }
    }

    private var editorHeader: some View {
        HStack(spacing: 6) {
            paneButton(title: "格式化", icon: "text.alignleft") {
                model.format(indent: model.indentWidth)
            }
            .help("格式化（当前 \(model.indentWidth) 空格缩进）")
            paneButton(title: "压缩", icon: "rectangle.compress.vertical") {
                model.minify()
            }
            .help("压缩为单行")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Theme.panelBackground)
    }

    private func paneButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(Theme.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.controlBackground, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5).stroke(Theme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct PaneToolbar: View {
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var model: AppModel
    let mode: PaneViewMode
    let paneID: UUID

    var body: some View {
        HStack(spacing: 6) {
            Button {
                model.format(indent: model.indentWidth)
            } label: {
                Label("格式化", systemImage: "text.alignleft")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .disabled(model.root == nil)
            Button {
                model.minify()
            } label: {
                Label("压缩", systemImage: "rectangle.compress.vertical")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .disabled(model.root == nil)
            Spacer(minLength: 0)
            Picker("视图", selection: Binding(
                get: { mode },
                set: { workspace.setViewMode($0, in: paneID) }
            )) {
                Text("编辑").tag(PaneViewMode.editor)
                Text("树形").tag(PaneViewMode.tree)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 112)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Theme.panelBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

struct EmptyTabView: View {
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "curlybraces")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(Theme.secondaryText)
            Text("空标签页")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.text)
            Text("打开文件或粘贴 JSON 开始查看")
                .font(.system(size: 12))
                .foregroundColor(Theme.secondaryText)
            HStack(spacing: 8) {
                Button("打开文件…") { workspace.openFilePanel() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("粘贴 JSON") { pasteJSON() }
                Button("载入示例") { workspace.loadDemo() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    private func pasteJSON() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            workspace.showToast("剪贴板中没有文本")
            return
        }
        model.loadPastedText(text)
    }
}

struct AppCommands: Commands {
    @ObservedObject var workspace: WorkspaceModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建空标签页") { workspace.newTab() }
                .keyboardShortcut("t", modifiers: .command)
            Button("打开…") { workspace.openFilePanel() }
                .keyboardShortcut("o", modifiers: .command)
            Button("关闭标签页") { workspace.closeActiveTab() }
                .keyboardShortcut("w", modifiers: .command)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("撤销") { workspace.activeModel?.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(workspace.activeModel?.canUndo != true)
            Button("重做") { workspace.activeModel?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(workspace.activeModel?.canRedo != true)
        }
        CommandMenu("JSON") {
            Button("格式化（2 空格）") { workspace.activeModel?.format(indent: 2) }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("格式化（4 空格）") { workspace.activeModel?.format(indent: 4) }
            Button("压缩") { workspace.activeModel?.minify() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Divider()
            Button("复制全部内容") { workspace.activeModel?.copyAll() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
        }
        CommandMenu("视图") {
            Button("向右分屏") { workspace.splitFocusedPane(axis: .horizontal) }
                .keyboardShortcut("d", modifiers: .command)
            Button("向下分屏") { workspace.splitFocusedPane(axis: .vertical) }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("关闭窗格") { workspace.closeFocusedPane() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            Divider()
            Button("下一个标签页") { workspace.nextTab() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("上一个标签页") { workspace.previousTab() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Divider()
            Button("展开全部节点") { workspace.activeModel?.expandAll() }
            Button("折叠全部节点") { workspace.activeModel?.collapseAll() }
            Divider()
            Button("搜索") { workspace.activeModel?.requestSearchFocus() }
                .keyboardShortcut("f", modifiers: .command)
            Button("跳转到错误") { workspace.activeModel?.jumpToError() }
                .disabled(!(workspace.activeModel?.parseState.isError ?? false))
        }
    }
}

extension ParseState {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: WorkspaceModel?
    private var pendingURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if let model {
            model.open(url: url)
        } else {
            pendingURL = url
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func attach(_ model: WorkspaceModel) {
        self.model = model
        if let pendingURL {
            self.pendingURL = nil
            model.open(url: pendingURL)
        }
    }
}

@main
struct JSONEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var workspace = WorkspaceModel()

    init() {
        if CommandLine.arguments.contains("--workspace-self-test") {
            WorkspaceSelfTest.run()
            exit(0)
        }
    }

    var body: some Scene {
        Window("QJson", id: "main") {
            ContentView(workspace: workspace)
                .frame(minWidth: 1100, minHeight: 600)
                .onAppear {
                    appDelegate.attach(workspace)
                }
        }
        .defaultSize(width: 1380, height: 860)
        .windowToolbarStyle(.unified)
        .commands {
            AppCommands(workspace: workspace)
        }
    }
}
