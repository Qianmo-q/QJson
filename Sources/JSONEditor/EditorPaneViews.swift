import AppKit
import JSONCore
import SwiftUI

struct EditorRepresentable: NSViewRepresentable {
    @ObservedObject var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let controller = EditorController(model: model)
        context.coordinator.controller = controller
        model.attach(editor: controller)
        return controller.scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    final class Coordinator {
        var controller: EditorController?
    }
}

struct SearchBarView: View {
    @ObservedObject var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(Theme.secondaryText)
            TextField("搜索键或值…", text: $model.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(Theme.text)
                .focused($focused)
                .onSubmit { model.searchNext() }
            if !model.searchQuery.isEmpty {
                Button {
                    model.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
            }
            countLabel
            Button { model.searchPrevious() } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .disabled(model.searchResult.hits.isEmpty)
            .help("上一个命中")
            Button { model.searchNext() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .disabled(model.searchResult.hits.isEmpty)
            .help("下一个命中")
            Picker("", selection: $model.searchScope) {
                ForEach(JSONSearchScope.allCases) { scope in
                    Text(scope.label).tag(scope)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 138)
            .help("搜索范围")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.panelBackground)
        .onChange(of: model.searchFocusToken) { _, _ in
            focused = true
        }
    }

    private var countLabel: some View {
        Group {
            if model.isSearching {
                Text("搜索中…")
            } else if !model.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                if model.searchResult.totalCount == 0 {
                    Text("无结果")
                } else {
                    Text("\(model.searchResult.totalCount)\(model.searchResult.truncated ? "+" : "") 处")
                }
            } else {
                Text("")
            }
        }
        .font(.system(size: 11))
        .foregroundColor(Theme.secondaryText)
        .frame(minWidth: 44, alignment: .trailing)
        .lineLimit(1)
    }
}

struct SearchResultsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(model.searchResult.hits.enumerated()), id: \.element.node.range.location) { index, hit in
                    let isCurrent = model.currentHitIndex == index
                    Button {
                        model.selectHit(index)
                    } label: {
                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: "text.magnifyingglass")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.secondaryText)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hit.displayPath)
                                    .font(Theme.pathFont)
                                    .foregroundColor(Theme.secondaryText)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(summary(for: hit))
                                    .font(Theme.treeFont)
                                    .foregroundColor(Theme.text)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            Spacer(minLength: 4)
                            if hit.isKeyMatch {
                                Text("键")
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Theme.key.opacity(0.15))
                                    .foregroundColor(Theme.key)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isCurrent ? Theme.selectedRow : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 3)
        }
        .background(Theme.panelBackground)
    }

    private func summary(for hit: JSONSearchHit) -> String {
        var parts: [String] = []
        if let key = hit.keyText { parts.append(key) }
        if let value = hit.valueText { parts.append(String(value.prefix(160))) }
        return parts.isEmpty ? hit.node.displayValue : parts.joined(separator: " : ")
    }
}

struct StatusBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            parseStatus
            Spacer(minLength: 8)
            Text("行 \(model.lineCount)")
            Text("Ln \(model.caretLine), Col \(model.caretColumn)")
            if model.selectionLength > 0 {
                Text("选中 \(model.selectionLength)")
            }
            Text("字符 \(model.characterCount)")
        }
        .font(.system(size: 11))
        .foregroundColor(Theme.secondaryText)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(Theme.panelBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    @ViewBuilder
    private var parseStatus: some View {
        if model.isParsing {
            HStack(spacing: 5) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text("解析中…")
            }
        } else {
            switch model.parseState {
            case .idle:
                Text("就绪")
            case .valid(let nodeCount, let elapsed):
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(nsColor: Palette.string))
                    Text("合法 · \(nodeCount) 个节点 · \(formatted(elapsed))")
                }
            case .error(let error):
                Button {
                    model.jumpToError()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundColor(Theme.errorText)
                        Text("错误 \(error.line):\(error.column) · \(error.message)")
                            .foregroundColor(Theme.errorText)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .help("点击跳转到错误位置")
            }
        }
    }

    private func formatted(_ interval: TimeInterval) -> String {
        let ms = interval * 1000
        if ms < 1 { return "<1 ms" }
        if ms < 1000 { return String(format: "%.0f ms", ms) }
        return String(format: "%.2f s", interval)
    }
}
