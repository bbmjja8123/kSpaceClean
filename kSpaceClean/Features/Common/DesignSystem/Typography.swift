// kSpaceClean/Features/Common/DesignSystem/Typography.swift
import SwiftUI

enum Typography {
    static func heroNumber() -> Font {
        .system(size: 36, weight: .semibold, design: .default)
    }
    static func largeTitle() -> Font {
        .system(size: 24, weight: .semibold, design: .default)
    }
    static func mediumTitle() -> Font {
        .system(size: 17, weight: .semibold, design: .default)
    }
    static func largeBody() -> Font {
        .system(size: 15, weight: .medium, design: .default)
    }
    static func regularBody() -> Font {
        .system(size: 13, weight: .regular, design: .default)
    }
    static func smallBody() -> Font {
        .system(size: 11, weight: .regular, design: .default)
    }
    static func filePath() -> Font {
        .system(size: 12, weight: .regular, design: .monospaced)
    }
    static func sizeNumber() -> Font {
        .system(size: 17, weight: .semibold, design: .default)
    }
}