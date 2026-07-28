// kSpaceClean/Features/Common/DesignSystem/Colors.swift
import SwiftUI

extension Color {
    // Background
    static let bgCanvas = Color(red: 0.059, green: 0.063, blue: 0.071)        // #0F1012
    static let bgSurface = Color(red: 0.110, green: 0.110, blue: 0.118)       // #1C1C1E
    static let bgElevated = Color(red: 0.173, green: 0.173, blue: 0.180)      // #2C2C2E
    static let divider = Color(red: 0.227, green: 0.227, blue: 0.235)         // #3A3A3C

    // Text
    static let textPrimary = Color.white                                       // #FFFFFF
    static let textSecondary = Color(red: 0.600, green: 0.600, blue: 0.600)   // #999999
    static let textTertiary = Color(red: 0.400, green: 0.400, blue: 0.400)    // #666666
    static let textDisabled = Color(red: 0.227, green: 0.227, blue: 0.235)   // #3A3A3C

    // Brand
    static let brandPrimary = Color(red: 0.039, green: 0.518, blue: 1.000)    // #0A84FF
    static let brandAccent = Color(red: 0.353, green: 0.784, blue: 0.980)     // #5AC8FA

    // Risk (4 levels)
    static let riskRecommended = Color(red: 0.204, green: 0.780, blue: 0.349) // #34C759
    static let riskOptional = Color(red: 0.557, green: 0.557, blue: 0.576)    // #8E8E93
    static let riskCaution = Color(red: 1.000, green: 0.584, blue: 0.000)     // #FF9500
    static let riskDangerous = Color(red: 1.000, green: 0.231, blue: 0.188)   // #FF3B30

    // State
    static let stateWarning = Color(red: 1.000, green: 0.800, blue: 0.000)    // #FFCC00
    static let stateSuccess = Color(red: 0.204, green: 0.780, blue: 0.349)    // #34C759
    static let stateError = Color(red: 1.000, green: 0.231, blue: 0.188)      // #FF3B30
    static let stateScanning = Color(red: 0.039, green: 0.518, blue: 1.000)   // #0A84FF
}

extension RiskLevel {
    var backgroundColor: Color {
        switch self {
        case .recommended: return .riskRecommended
        case .optional: return .riskOptional
        case .caution: return .riskCaution
        case .dangerous: return .riskDangerous
        }
    }
    var foregroundColor: Color {
        switch self {
        case .caution: return .black
        default: return .white
        }
    }
}