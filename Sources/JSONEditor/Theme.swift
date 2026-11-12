import AppKit
import SwiftUI

/// 主题外观：跟随系统 / 强制深色 / 强制白色（浅色）。
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "与系统同步"
        case .dark: return "深色"
        case .light: return "白色"
        }
    }

    /// 传给 NSApp.appearance 的外观；nil 表示跟随系统。
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .dark: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        }
    }
}

/// 跟随系统外观的动态配色。所有键、值、高亮色均提供浅色/深色两套。
enum Palette {
    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }

    static func dynamic(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> NSColor {
        dynamic(hex(light, alpha: lightAlpha), hex(dark, alpha: darkAlpha))
    }

    static let background = dynamic(light: 0xFFFFFF, dark: 0x1E1F22)
    static let panelBackground = dynamic(light: 0xF7F8FA, dark: 0x242529)
    static let gutterBackground = dynamic(light: 0xF3F5F7, dark: 0x1A1B1E)
    static let gutterText = dynamic(light: 0x8A929C, dark: 0x6E7681)
    static let text = dynamic(light: 0x1F2328, dark: 0xE6E8EB)
    static let secondaryText = dynamic(light: 0x6A737D, dark: 0x9BA3AE)
    static let border = dynamic(light: 0xD9DEE4, dark: 0x33363B)
    static let key = dynamic(light: 0x0550AE, dark: 0x79C0FF)
    static let string = dynamic(light: 0x0A7D33, dark: 0x7EE787)
    static let number = dynamic(light: 0xB35900, dark: 0xFFA657)
    static let boolean = dynamic(light: 0x8250DF, dark: 0xD2A8FF)
    static let null = dynamic(light: 0x6E7781, dark: 0x8B949E)
    static let punctuation = dynamic(light: 0x57606A, dark: 0xC9D1D9)
    static let selection = dynamic(light: 0xBBD9FF, dark: 0x2A4A6B)
    static let matchBackground = dynamic(light: 0xFFF0A8, dark: 0x5A4A00)
    static let currentMatchBackground = dynamic(light: 0xFFC94D, dark: 0x8A6A00)
    static let errorBackground = dynamic(light: 0xFFE1E1, dark: 0x4A1D1D)
    static let errorText = dynamic(light: 0xCF222E, dark: 0xFF7B72)
    static let selectedRow = dynamic(light: 0xE6F0FC, dark: 0x2B3B50)
    static let controlBackground = dynamic(light: 0xFFFFFF, dark: 0x2C2D31)
    static let hoverBackground = dynamic(light: 0xEFF3F7, dark: 0x2A2C30)
    static let accent = NSColor.controlAccentColor
}

enum Theme {
    static var background: Color { Color(nsColor: Palette.background) }
    static var panelBackground: Color { Color(nsColor: Palette.panelBackground) }
    static var gutterBackground: Color { Color(nsColor: Palette.gutterBackground) }
    static var text: Color { Color(nsColor: Palette.text) }
    static var secondaryText: Color { Color(nsColor: Palette.secondaryText) }
    static var border: Color { Color(nsColor: Palette.border) }
    static var key: Color { Color(nsColor: Palette.key) }
    static var string: Color { Color(nsColor: Palette.string) }
    static var number: Color { Color(nsColor: Palette.number) }
    static var boolean: Color { Color(nsColor: Palette.boolean) }
    static var null: Color { Color(nsColor: Palette.null) }
    static var punctuation: Color { Color(nsColor: Palette.punctuation) }
    static var errorText: Color { Color(nsColor: Palette.errorText) }
    static var selectedRow: Color { Color(nsColor: Palette.selectedRow) }
    static var controlBackground: Color { Color(nsColor: Palette.controlBackground) }
    static var matchBackground: Color { Color(nsColor: Palette.matchBackground) }
    static var currentMatchBackground: Color { Color(nsColor: Palette.currentMatchBackground) }
    static var accent: Color { Color(nsColor: Palette.accent) }

    static let editorFontSize: CGFloat = 13
    static var editorFont: NSFont { NSFont.monospacedSystemFont(ofSize: editorFontSize, weight: .regular) }
    static var rulerFont: NSFont { NSFont.monospacedSystemFont(ofSize: 11, weight: .regular) }
    static var treeFont: Font { .system(size: 12.5, design: .monospaced) }
    static var pathFont: Font { .system(size: 11, design: .monospaced) }

    static func color(for kind: JSONNodeKindToken) -> NSColor {
        switch kind {
        case .key: return Palette.key
        case .string: return Palette.string
        case .number: return Palette.number
        case .boolean: return Palette.boolean
        case .null: return Palette.null
        case .punctuation: return Palette.punctuation
        }
    }
}

/// 供主题映射使用的词法类别（避免编辑器层依赖具体枚举命名冲突）。
enum JSONNodeKindToken {
    case key
    case string
    case number
    case boolean
    case null
    case punctuation
}
