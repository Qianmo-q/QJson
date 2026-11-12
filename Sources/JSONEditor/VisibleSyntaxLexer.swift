import AppKit

/// 仅对视口附近文本做词法着色，保证大文档下高亮开销恒定。
enum VisibleSyntaxLexer {
    static func tokens(
        in source: NSString,
        visibleRange: NSRange,
        lookbehind: Int = 4000,
        lookahead: Int = 4000
    ) -> [SyntaxToken] {
        guard source.length > 0, visibleRange.length > 0 else { return [] }
        let scanStart = max(0, visibleRange.location - lookbehind)
        let scanEnd = min(source.length, visibleRange.location + visibleRange.length + lookahead)
        guard scanEnd > scanStart else { return [] }
        let length = scanEnd - scanStart
        var units = [UInt16](repeating: 0, count: length)
        source.getCharacters(&units, range: NSRange(location: scanStart, length: length))

        var tokens: [SyntaxToken] = []
        var index = 0
        while index < length {
            let unit = units[index]
            if unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D {
                index += 1
                continue
            }
            let start = index
            switch unit {
            case 0x22: // "
                index += 1
                var closed = false
                while index < length {
                    let current = units[index]
                    if current == 0x5C {
                        index += 2
                        continue
                    }
                    if current == 0x22 {
                        index += 1
                        closed = true
                        break
                    }
                    index += 1
                }
                if !closed { index = length }
                var lookaheadIndex = index
                while lookaheadIndex < length,
                      units[lookaheadIndex] == 0x20 || units[lookaheadIndex] == 0x09 {
                    lookaheadIndex += 1
                }
                let isKey = lookaheadIndex < length && units[lookaheadIndex] == 0x3A
                tokens.append(SyntaxToken(
                    range: NSRange(location: scanStart + start, length: index - start),
                    kind: isKey ? .key : .string
                ))
            case 0x30...0x39, 0x2D: // 数字
                index += 1
                while index < length {
                    let current = units[index]
                    if (current >= 0x30 && current <= 0x39)
                        || current == 0x2E || current == 0x65 || current == 0x45
                        || current == 0x2B || current == 0x2D {
                        index += 1
                    } else {
                        break
                    }
                }
                tokens.append(SyntaxToken(
                    range: NSRange(location: scanStart + start, length: index - start),
                    kind: .number
                ))
            case 0x74, 0x66, 0x6E: // t f n
                while index < length, isWordUnit(units[index]) { index += 1 }
                let word = String(decoding: units[start..<index], as: UTF16.self)
                let kind: JSONNodeKindToken
                switch word {
                case "true", "false": kind = .boolean
                case "null": kind = .null
                default: kind = .punctuation
                }
                tokens.append(SyntaxToken(
                    range: NSRange(location: scanStart + start, length: index - start),
                    kind: kind
                ))
            default:
                index += 1
                tokens.append(SyntaxToken(
                    range: NSRange(location: scanStart + start, length: 1),
                    kind: .punctuation
                ))
            }
        }
        return tokens
    }

    private static func isWordUnit(_ unit: UInt16) -> Bool {
        (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A)
    }
}

struct SyntaxToken {
    let range: NSRange
    let kind: JSONNodeKindToken
}
