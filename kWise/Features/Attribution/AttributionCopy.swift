// kWise/Features/Attribution/AttributionCopy.swift
//
// 归因文案装配：唯一允许产出自然语言的地方，全部走 xcstrings key。
// 文案红线由 AttributionCopyAuditTests 守卫（Task 10）。
import Foundation

enum AttributionCopy {
    static func causeLabel(_ cause: AttributionCause) -> String {
        String(localized: String.LocalizationValue("attr.cause.\(cause.rawValue)"))
    }

    static func reclaimLabel(_ reclaim: Reclaimability) -> String {
        switch reclaim {
        case .recycles(let days):
            String(format: String(localized: String.LocalizationValue("attr.reclaim.recycles")),
                   days)
        case .resurrects(let via):
            String(format: String(localized: String.LocalizationValue("attr.reclaim.resurrects")),
                   via)
        case .permanent:
            String(localized: String.LocalizationValue("attr.reclaim.permanent"))
        case .uncertain:
            String(localized: String.LocalizationValue("attr.reclaim.uncertain"))
        }
    }

    static func evidenceText(_ evidence: Evidence) -> String {
        String(format: String(localized: String.LocalizationValue(evidence.textKey)),
               arguments: evidence.arguments)
    }

    static func ownerLabel(_ owner: AttributionOwner) -> String {
        switch owner {
        case .app(_, let appName):
            return appName ?? ownerBundleID(owner)
        case .system:
            return "macOS"
        case .user:
            return String(localized: String.LocalizationValue("attr.owner.user"))
        case .unknown:
            return String(localized: String.LocalizationValue("attr.owner.unknown"))
        }
    }

    private static func ownerBundleID(_ owner: AttributionOwner) -> String {
        if case .app(let bundleID, _) = owner { return bundleID }
        return ""
    }
}
