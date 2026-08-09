import SwiftUI

extension DuplicateCategory {
    var displayName: String {
        switch self {
        case .identical: return NSLocalizedString("Identical", comment: "Duplicate category")
        case .directoryDedup: return NSLocalizedString("Directory", comment: "Duplicate category")
        case .perceptual: return NSLocalizedString("Similar", comment: "Duplicate category")
        case .largeFile: return NSLocalizedString("Large", comment: "Duplicate category")
        case .buildArtifact: return NSLocalizedString("Artifacts", comment: "Duplicate category")
        case .rawJPEG: return NSLocalizedString("RAW+JPEG", comment: "Duplicate category")
        case .nameHeuristic: return NSLocalizedString("Renamed", comment: "Duplicate category")
        }
    }

    var iconName: String {
        switch self {
        case .identical: return "doc.on.doc"
        case .directoryDedup: return "folder.badge.gearshape"
        case .perceptual: return "eye"
        case .largeFile: return "doc.resize"
        case .buildArtifact: return "hammer"
        case .rawJPEG: return "camera"
        case .nameHeuristic: return "rectangle.stack.badge.person.crop"
        }
    }

    var color: Color {
        switch self {
        case .identical: return .blue
        case .directoryDedup: return .purple
        case .perceptual: return .orange
        case .largeFile: return .red
        case .buildArtifact: return .gray
        case .rawJPEG: return .green
        case .nameHeuristic: return .teal
        }
    }
}
