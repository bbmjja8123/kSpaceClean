import SwiftUI

extension DuplicateCategory {
    var displayName: String {
        switch self {
        case .identical: return "Identical"
        case .directoryDedup: return "Directory"
        case .perceptual: return "Similar"
        case .largeFile: return "Large"
        case .buildArtifact: return "Artifacts"
        case .rawJPEG: return "RAW+JPEG"
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
        }
    }
}
