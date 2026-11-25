import AppKit
import Combine

final class OpenDocument: ObservableObject, Identifiable {
    let id = UUID()
    let fileURL: URL?
    let fileName: String
    let undoManager = UndoManager()

    @Published var text: String {
        didSet {
            if text != oldValue {
                isDirty = text != savedText
            }
        }
    }

    private(set) var savedText: String
    private(set) var isDirty = false

    init(text: String, fileName: String?, fileURL: URL? = nil) {
        self.text = text
        self.savedText = text
        self.fileName = fileName ?? "未命名"
        self.fileURL = fileURL
    }

    func applyTextChange(previous: String, updated: String, undoable: Bool) {
        text = updated
        guard undoable else { return }
        undoManager.registerUndo(withTarget: self) { document in
            document.applyTextChange(previous: updated, updated: previous, undoable: true)
        }
    }
}
