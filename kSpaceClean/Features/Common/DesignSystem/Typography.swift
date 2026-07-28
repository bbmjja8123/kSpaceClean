// kSpaceClean/Features/Common/DesignSystem/Typography.swift
import SwiftUI

/// Typography scale tokens for kSpaceClean.
///
/// Each factory returns a `Font` configured for a specific role in the UI.
/// Use the semantic factory name (e.g. ``heroNumber()``) at the call site so
/// the visual hierarchy remains explicit and reusable across screens.
enum Typography {
    /// Hero-sized numeric display — 36pt semibold. Used for the disk-usage hero number.
    static func heroNumber() -> Font {
        .system(size: 36, weight: .semibold, design: .default)
    }
    /// Large title — 24pt semibold. Top-of-page titles.
    static func largeTitle() -> Font {
        .system(size: 24, weight: .semibold, design: .default)
    }
    /// Medium title — 17pt semibold. Section headers, card titles.
    static func mediumTitle() -> Font {
        .system(size: 17, weight: .semibold, design: .default)
    }
    /// Large body — 15pt medium. Emphasized body content, prominent list rows.
    static func largeBody() -> Font {
        .system(size: 15, weight: .medium, design: .default)
    }
    /// Regular body — 13pt regular. Default body text.
    static func regularBody() -> Font {
        .system(size: 13, weight: .regular, design: .default)
    }
    /// Small body — 11pt regular. Captions, helper text, fine print.
    static func smallBody() -> Font {
        .system(size: 11, weight: .regular, design: .default)
    }
    /// File path — 12pt monospaced regular. Used for filesystem paths in results.
    static func filePath() -> Font {
        .system(size: 12, weight: .regular, design: .monospaced)
    }
    /// Size number — 17pt semibold. Numeric size labels next to file rows.
    static func sizeNumber() -> Font {
        .system(size: 17, weight: .semibold, design: .default)
    }
}
