<p align="center">
  <img src="assets/icon.png" width="132" alt="QJson 图标">
</p>

<h1 align="center">QJson</h1>

<p align="center">macOS 原生 JSON 查看与临时编辑工具 · Swift + SwiftUI</p>

QJson 面向「快速看一段 JSON、临时改几个值、复制走」的场景：左侧文本编辑、右侧树形预览与行内编辑，配合搜索、格式化/压缩。应用不提供保存/导出，编辑结果一键复制到剪贴板。

## 功能

- **编辑器**：JSON 语法高亮（仅可视区域着色）、行号、错误行列定位、撤销/重做。
- **解析**：自研严格解析器，保留对象键顺序并记录每个节点的源区间；防抖 300ms 后台解析。
- **树形预览**：原生 NSTableView 行复用，对象/数组按层级展示并按类型着色；单击行展开/折叠，悬停显示删除按钮。
- **行内编辑**：双击键名改名；双击值就地编辑并实时推断类型（`"文本"` / `123` / `true` / `null` / `{}` / `[]`）；回车或点击空白处提交，Esc 取消；支持对象/数组增删。
- **搜索**：键 / 值 / 键和值三种范围，命中列表、全部高亮、上一个/下一个循环跳转，并在文本与树之间同步定位。
- **格式化工具**：2/4 空格格式化、压缩；内置 Demo。
- **左右联动**：文本光标与树行双向同步选中；分割线中点的锁按钮可随时解除同步，设置持久化。
- **主题**：与系统同步 / 深色 / 白色三态切换，实时生效并记忆选择。
- **性能**：1MB 文档打开即用；10MB 级文档后台解析；5 万行级树展开本机实测 50ms 内。

## 安装（内部使用版）

1. 从 [Releases](https://github.com/Qianmo-q/QJson/releases/latest) 下载 `QJson-0.2.0.dmg`；
2. 打开 DMG，将 **QJson** 拖入 Applications；
3. 首次启动若被 Gatekeeper 拦截：
   - 打开「系统设置 → 隐私与安全性」，在安全区域点击「仍要打开」；
   - 或执行：`xattr -dr com.apple.quarantine /Applications/QJson.app`。

> 当前安装包使用 **ad-hoc 签名、未做 Apple 公证**，仅适合本机或少量内部分发。
> 系统要求：macOS 14+；当前发布包为 Apple Silicon（arm64）。

## 快捷键

| 快捷键 | 功能 |
|---|---|
| ⌘O | 打开 JSON 文件 |
| ⇧⌘D | 载入内置示例 |
| ⌘Z / ⇧⌘Z | 撤销 / 重做 |
| ⇧⌘F | 格式化（2 空格） |
| ⇧⌘M | 压缩 |
| ⇧⌘C | 复制全部内容 |
| ⌘F | 聚焦搜索框 |

树形区：单击行展开/折叠，双击键或值编辑，`+` 新增子节点，悬停行显示删除。

## 从源码构建

环境：macOS 14+、Swift 6 工具链（仅 Command Line Tools 即可，无需完整 Xcode）。

```bash
git clone https://github.com/Qianmo-q/QJson.git
cd QJson
scripts/build_app.sh
open build/QJson.app
```

脚本会输出 `build/QJson.app` 与 `build/QJson-<版本>.dmg`（ad-hoc 签名）。
核心引擎自检：

```bash
swift run -c release JSONSelfTest
```

### 正式签名与公证（可选）

```bash
xcrun notarytool store-credentials "qjson-notary" \
  --apple-id "APPLE_ID" --team-id "TEAM_ID" --password "APP_SPECIFIC_PASSWORD"

CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
NOTARY_PROFILE="qjson-notary" \
scripts/build_app.sh release
```

## 项目结构

```
Sources/JSONCore/     解析、格式化、树补丁、搜索、转换（纯逻辑，含命令自检）
Sources/JSONEditor/   SwiftUI 应用、NSTextView 编辑器、树视图与主题
scripts/build_app.sh  构建 .app / .dmg
Resources/            Info.plist 与应用图标
```

## 已知限制

- 不提供保存/导出，仅一键复制（产品定位如此）。
- 当前发布包仅 arm64；Intel Mac 需自行从源码构建。
- 大表格在开启 VoiceOver 等无障碍枚举时会较慢，普通滚动与浏览不受影响。

## License

[Apache-2.0](LICENSE)
