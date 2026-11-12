import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var isDropTargeted = false
    @State private var didStart = false
    @State private var leftPaneWidth: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            splitView
            StatusBarView(model: model)
        }
        .background(Theme.background)
        .overlay(alignment: .bottomTrailing) { toastView }
        .overlay { dropOverlay }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .toolbar { toolbarContent }
        .navigationTitle(model.windowTitle)
        .onAppear {
            guard !didStart else { return }
            didStart = true
            model.startup()
        }
    }

    private var editorPane: some View {
        VStack(spacing: 0) {
            editorHeader
            Rectangle().fill(Theme.border).frame(height: 1)
            EditorRepresentable(model: model)
                .background(Theme.background)
        }
    }

    /// 左右分栏；锁按钮浮在分割线中点，控制选中同步开关。
    private var splitView: some View {
        GeometryReader { proxy in
            HSplitView {
                editorPane
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        GeometryReader { inner in
                            Color.clear
                                .onAppear { leftPaneWidth = inner.size.width }
                                .onChange(of: inner.size.width) { _, width in leftPaneWidth = width }
                        }
                    )
                TreePaneView(model: model, tree: model.tree)
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(height: 26)
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                model.openFilePanel()
            } label: {
                Label("打开", systemImage: "folder")
            }
            .help("打开 JSON 文件（⌘O）")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.format(indent: model.indentWidth)
            } label: {
                Text("格式化")
                    .font(.system(size: 12, weight: .medium))
            }
            .help("格式化（当前缩进 \(model.indentWidth) 空格）")

            Picker("缩进", selection: $model.indentWidth) {
                Text("2 空格").tag(2)
                Text("4 空格").tag(4)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 128)
            .help("格式化缩进宽度")

            Button {
                model.loadDemo()
            } label: {
                Label("示例", systemImage: "doc.text")
            }
            .help("载入内置示例")

            Button {
                model.copyAll()
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .help("复制全部内容（⇧⌘C）")
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast = model.toast {
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
                model.open(url: url)
            }
        }
        return true
    }
}

struct AppCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("打开…") { model.openFilePanel() }
                .keyboardShortcut("o", modifiers: .command)
            Button("载入示例") { model.loadDemo() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .undoRedo) {
            Button("撤销") { model.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.canUndo)
            Button("重做") { model.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.canRedo)
        }
        CommandMenu("JSON") {
            Button("格式化（2 空格）") { model.format(indent: 2) }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("格式化（4 空格）") { model.format(indent: 4) }
            Button("压缩") { model.minify() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Divider()
            Button("复制全部内容") { model.copyAll() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
        }
        CommandMenu("视图") {
            Button("展开全部节点") { model.expandAll() }
            Button("折叠全部节点") { model.collapseAll() }
            Divider()
            Button("搜索") { model.requestSearchFocus() }
                .keyboardShortcut("f", modifiers: .command)
            Button("跳转到错误") { model.jumpToError() }
                .disabled(!model.parseState.isError)
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
    weak var model: AppModel?
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

    func attach(_ model: AppModel) {
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
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("QJson", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 960, minHeight: 600)
                .onAppear {
                    appDelegate.attach(model)
                }
        }
        .defaultSize(width: 1220, height: 780)
        .windowToolbarStyle(.unified)
        .commands {
            AppCommands(model: model)
        }
    }
}
