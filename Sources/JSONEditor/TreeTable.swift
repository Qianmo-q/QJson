import AppKit
import JSONCore
import SwiftUI

/// 原生 NSTableView 承载树行：滚动、滚动条、行复用由 AppKit 负责。
struct TreeTable: NSViewRepresentable {
    let model: AppModel
    let tree: TreeStore
    let ui: TreeUIState
    let addInsertionNodeIndex: Int?
    let addContainerRow: JSONTreeRow?
    let onAdd: (JSONTreeRow) -> Void
    let onDelete: (JSONTreeRow) -> Void
    let onCloseAdd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .legacy
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.intercellSpacing = .zero
        tableView.rowHeight = 32
        tableView.style = .plain
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tree-row"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        scrollView.documentView = tableView

        context.coordinator.tableView = tableView
        context.coordinator.scrollView = scrollView
        context.coordinator.installHoverTrackingIfNeeded()
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.installHoverTrackingIfNeeded()
        context.coordinator.reloadIfNeeded()
        if let target = tree.pendingScrollTarget {
            context.coordinator.scrollTo(id: target)
            DispatchQueue.main.async {
                if tree.pendingScrollTarget == target {
                    tree.pendingScrollTarget = nil
                }
            }
        }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: TreeTable
        weak var tableView: NSTableView?
        weak var scrollView: NSScrollView?

        private var lastVersion = -1
        private var lastAddIndex: Int?
        private var lastAddContainerID: Int?
        private var lastRowCount = -1
        private var isReloading = false
        private var hoverMonitor: Any?
        private var hoverObserver: NSObjectProtocol?

        init(_ parent: TreeTable) {
            self.parent = parent
        }

        deinit {
            if let hoverMonitor { NSEvent.removeMonitor(hoverMonitor) }
            if let hoverObserver { NotificationCenter.default.removeObserver(hoverObserver) }
        }

        /// 悬停行按真实指针位置统一计算，避免行复用后残留悬停底色。
        func installHoverTrackingIfNeeded() {
            if hoverMonitor == nil {
                hoverMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseUp]) { [weak self] event in
                    self?.updateHover(at: event.locationInWindow)
                    return event
                }
                if let contentView = scrollView?.contentView {
                    contentView.postsBoundsChangedNotifications = true
                    hoverObserver = NotificationCenter.default.addObserver(
                        forName: NSView.boundsDidChangeNotification,
                        object: contentView,
                        queue: .main
                    ) { [weak self] _ in
                        guard let self, let window = self.tableView?.window else { return }
                        self.updateHover(at: window.mouseLocationOutsideOfEventStream)
                    }
                }
            }
            tableView?.window?.acceptsMouseMovedEvents = true
        }

        func updateHover(at windowPoint: NSPoint) {
            guard let tableView else {
                setHover(nil)
                return
            }
            let point = tableView.convert(windowPoint, from: nil)
            guard tableView.visibleRect.contains(point) else {
                setHover(nil)
                return
            }
            let tableRow = tableView.row(at: point)
            guard tableRow >= 0, !isReloading else {
                setHover(nil)
                return
            }
            let entry = row(at: tableRow)
            guard !entry.isAdd, let nodeRow = entry.row else {
                setHover(nil)
                return
            }
            setHover(nodeRow.id)
        }

        private func setHover(_ id: Int?) {
            guard parent.ui.hoveredRowID != id else { return }
            parent.ui.hoveredRowID = id
        }

        private var rowCount: Int {
            parent.tree.rows.count + (parent.addInsertionNodeIndex != nil ? 1 : 0)
        }

        private func row(at index: Int) -> (row: JSONTreeRow?, isAdd: Bool) {
            if let insertion = parent.addInsertionNodeIndex, index == insertion {
                return (parent.addContainerRow, true)
            }
            let nodeIndex = parent.addInsertionNodeIndex.map { index > $0 ? index - 1 : index } ?? index
            guard nodeIndex >= 0, nodeIndex < parent.tree.rows.count else { return (nil, false) }
            return (parent.tree.rows[nodeIndex], false)
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rowCount
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("tree-cell")
            let cell: NSTableCellView
            let hosting: NSHostingView<AnyView>
            if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView,
               let existing = reused.subviews.first as? NSHostingView<AnyView> {
                cell = reused
                hosting = existing
            } else {
                cell = NSTableCellView()
                cell.identifier = identifier
                hosting = NSHostingView(rootView: AnyView(EmptyView()))
                hosting.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(hosting)
                NSLayoutConstraint.activate([
                    hosting.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                    hosting.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                    hosting.topAnchor.constraint(equalTo: cell.topAnchor),
                    hosting.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
                ])
            }
            hosting.rootView = AnyView(content(forRow: row))
            return cell
        }

        private func content(forRow index: Int) -> some View {
            let entry = row(at: index)
            if entry.isAdd, let containerRow = entry.row {
                return AnyView(
                    InlineAddRow(model: parent.model, container: containerRow, onClose: parent.onCloseAdd)
                        .frame(height: 32)
                )
            }
            guard let nodeRow = entry.row else {
                return AnyView(EmptyView())
            }
            return AnyView(
                TreeRowView(
                    model: parent.model,
                    ui: parent.ui,
                    row: nodeRow,
                    onAdd: { [weak self] in self?.parent.onAdd(nodeRow) },
                    onDelete: { [weak self] in self?.parent.onDelete(nodeRow) }
                )
                .frame(height: 32)
            )
        }

        func reloadIfNeeded() {
            guard let tableView, !isReloading else { return }
            let addID = parent.addInsertionNodeIndex == nil ? nil : parent.addContainerRow?.id
            guard lastVersion != parent.tree.version
                    || lastAddIndex != parent.addInsertionNodeIndex
                    || lastAddContainerID != addID
                    || lastRowCount != rowCount else {
                return
            }
            let addChanged = lastAddIndex != parent.addInsertionNodeIndex
            lastVersion = parent.tree.version
            lastAddIndex = parent.addInsertionNodeIndex
            lastAddContainerID = addID
            lastRowCount = rowCount
            isReloading = true
            let origin = scrollView?.contentView.bounds.origin ?? .zero
            tableView.reloadData()
            isReloading = false
            if origin.y > 0 {
                scrollView?.contentView.scroll(to: origin)
                if let clip = scrollView?.contentView {
                    scrollView?.reflectScrolledClipView(clip)
                }
            }
            if addChanged, let addIndex = parent.addInsertionNodeIndex {
                DispatchQueue.main.async {
                    tableView.scrollRowToVisible(addIndex)
                }
            }
        }

        func scrollTo(id: Int) {
            guard let tableView else { return }
            guard let nodeIndex = parent.tree.rows.firstIndex(where: { $0.id == id }) else { return }
            let logical = parent.addInsertionNodeIndex.map { nodeIndex >= $0 ? nodeIndex + 1 : nodeIndex } ?? nodeIndex
            tableView.scrollRowToVisible(logical)
        }
    }
}

