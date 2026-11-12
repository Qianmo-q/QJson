import Foundation
import JSONCore

/// 树视图的独立状态，避免展开/折叠时触发整个应用界面重绘。
final class TreeStore: ObservableObject {
    @Published var rows: [JSONTreeRow] = []
    @Published var truncated = false
    @Published var version = 0
    @Published var pendingScrollTarget: Int?
}
