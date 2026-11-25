import AppKit

enum WorkspaceSelfTest {
    static func run() {
        let emptyWorkspace = WorkspaceModel()
        precondition(emptyWorkspace.activeModel?.isEmpty == true)
        emptyWorkspace.newTab()
        emptyWorkspace.newTab()
        precondition(tabCount(in: emptyWorkspace.rootPane) == 3)
        emptyWorkspace.closeActiveTab()
        precondition(tabCount(in: emptyWorkspace.rootPane) == 2)
        emptyWorkspace.closeActiveTab()
        precondition(tabCount(in: emptyWorkspace.rootPane) == 1)
        precondition(emptyWorkspace.activeModel?.isEmpty == true)
        emptyWorkspace.newTab()
        precondition(tabCount(in: emptyWorkspace.rootPane) == 2)
        precondition(emptyWorkspace.activeModel?.isEmpty == true)

        let activationWorkspace = WorkspaceModel()
        let activationDocument = activationWorkspace.createDocument(text: "{\"a\":1}", fileName: "activation.json")
        activationWorkspace.open(activationDocument)
        let activationSourcePaneID = activationWorkspace.focusedPaneID
        let activationSourceTab = activationWorkspace.activeTab!
        activationWorkspace.splitFocusedPane(axis: .horizontal)
        precondition(activationWorkspace.focusedPaneID != activationSourcePaneID)
        activationWorkspace.activate(tab: activationSourceTab, in: activationSourcePaneID)
        precondition(activationWorkspace.focusedPaneID == activationSourcePaneID)
        precondition(activationWorkspace.activeTab?.id == activationSourceTab.id)
        activationWorkspace.newTab()
        let currentTab = activationWorkspace.activeTab!
        precondition(currentTab.id != activationSourceTab.id)
        activationWorkspace.focus(activationSourceTab.model)
        precondition(activationWorkspace.activeTab?.id == currentTab.id)
        precondition(activationWorkspace.focusedPaneID == activationSourcePaneID)

        let workspace = WorkspaceModel()
        let document = workspace.createDocument(text: "{\"a\":1}", fileName: "sample.json")
        workspace.open(document)
        let firstModel = workspace.activeModel!
        workspace.newTab(for: document)
        let secondModel = workspace.activeModel!
        precondition(firstModel !== secondModel)
        precondition(firstModel.openDocument === document && secondModel.openDocument === document)
        precondition(firstModel.undoManager === document.undoManager && secondModel.undoManager === document.undoManager)
        precondition(workspace.documentsTabCount(document.id) == 2)

        let editor = EditorController(model: firstModel)
        firstModel.attach(editor: editor)
        editor.replaceCharacters(in: NSRange(location: 5, length: 1), with: "2")
        precondition(document.text == "{\"a\":2}")
        precondition(document.undoManager.canUndo)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        let mirrorEditor = EditorController(model: secondModel)
        secondModel.attach(editor: mirrorEditor)
        precondition(mirrorEditor.text == document.text)
        secondModel.detach(editor: mirrorEditor)
        firstModel.undo()
        precondition(document.text == "{\"a\":1}")
        precondition(document.undoManager.canRedo)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        let undoMirrorEditor = EditorController(model: secondModel)
        secondModel.attach(editor: undoMirrorEditor)
        precondition(undoMirrorEditor.text == document.text)
        secondModel.detach(editor: undoMirrorEditor)
        firstModel.redo()
        precondition(document.text == "{\"a\":2}")
        firstModel.undo()
        precondition(document.text == "{\"a\":1}")
        firstModel.detach(editor: editor)

        let sourcePaneID = workspace.focusedPaneID
        workspace.splitFocusedPane(axis: .horizontal)
        workspace.newTab(in: sourcePaneID)
        precondition(workspace.focusedPaneID == sourcePaneID)
        precondition(tabCount(in: workspace.rootPane) == 4)
        workspace.closeFocusedPane()
        precondition(leafCount(in: workspace.rootPane) == 1)
        precondition(tabCount(in: workspace.rootPane) == 1)
        precondition(workspace.documentsTabCount(document.id) == 0)

        let tabsBeforeSplit = tabCount(in: workspace.rootPane)
        for index in 0..<8 {
            workspace.splitFocusedPane(axis: index.isMultiple(of: 2) ? .horizontal : .vertical)
        }
        precondition(leafCount(in: workspace.rootPane) == 9)
        precondition(tabCount(in: workspace.rootPane) == tabsBeforeSplit + 8)
        workspace.setViewMode(.tree, in: workspace.focusedPaneID)
        precondition(workspace.activeTab?.viewMode == .tree)

        let tabIDsBeforeEmptyPaneClose = Set(tabIDs(in: workspace.rootPane))
        let closedTabID = workspace.activeTab!.id
        workspace.closeActiveTab()
        precondition(leafCount(in: workspace.rootPane) == 8)
        precondition(tabCount(in: workspace.rootPane) == tabsBeforeSplit + 7)
        precondition(Set(tabIDs(in: workspace.rootPane)) == tabIDsBeforeEmptyPaneClose.subtracting([closedTabID]))
        precondition(workspace.activeModel != nil)
        precondition(workspace.documentsTabCount(document.id) == 0)

        var expectedTabIDs = Set(tabIDs(in: workspace.rootPane))
        let remainingPaneIDs = leafIDs(in: workspace.rootPane)
        for (index, paneID) in remainingPaneIDs.dropLast().enumerated() {
            workspace.focusedPaneID = paneID
            let closedTabID = workspace.activeTab!.id
            workspace.closeFocusedPane()
            expectedTabIDs.remove(closedTabID)
            precondition(leafCount(in: workspace.rootPane) == remainingPaneIDs.count - index - 1)
            let remainingTabIDs = tabIDs(in: workspace.rootPane)
            precondition(remainingTabIDs.count == tabCount(in: workspace.rootPane))
            precondition(Set(remainingTabIDs) == expectedTabIDs)
        }
        precondition(!workspace.isSplit)
        precondition(tabCount(in: workspace.rootPane) == 1)
        precondition(workspace.documentsTabCount(document.id) == 0)

        print("WorkspaceSelfTest: 通过")
    }

    private static func tabCount(in pane: WorkspacePane) -> Int {
        pane.tabs.count + pane.children.reduce(0) { $0 + tabCount(in: $1) }
    }

    private static func leafCount(in pane: WorkspacePane) -> Int {
        pane.isLeaf ? 1 : pane.children.reduce(0) { $0 + leafCount(in: $1) }
    }

    private static func tabIDs(in pane: WorkspacePane) -> [UUID] {
        pane.tabs.map(\.id) + pane.children.flatMap { tabIDs(in: $0) }
    }

    private static func leafIDs(in pane: WorkspacePane) -> [UUID] {
        pane.isLeaf ? [pane.id] : pane.children.flatMap { leafIDs(in: $0) }
    }
}
