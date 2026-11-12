import Foundation

/// 树的选中与行内编辑状态，由行视图直接观察，避免因编辑/选中触发整个表格重建。
final class TreeUIState: ObservableObject {
    @Published var selectedRowID: Int?
    @Published var editingRowID: Int?
    @Published var editingKey = false
    @Published var commitToken = 0

    func endEditing() {
        editingRowID = nil
    }
}
