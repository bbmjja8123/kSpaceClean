import Foundation

public enum CapabilityGate {
    public static var isMacOS14: Bool {
        if #available(macOS 14, *) { return true }
        return false
    }

    public static var supportsSwiftData: Bool { isMacOS14 }
    public static var supportsInteractiveWidgets: Bool { isMacOS14 }
    public static var supportsLiveActivities: Bool { isMacOS14 }
    public static var supportsControlWidgets: Bool { isMacOS14 }
    public static var supportsTipKit: Bool { isMacOS14 }

    public static var supportsAppIntents: Bool { true }  // macOS 13+
}
