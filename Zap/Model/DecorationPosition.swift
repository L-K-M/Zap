import SwiftUI

/// Which top corner a `DecorationStyle` is drawn in.
enum DecorationPosition: String, CaseIterable, Identifiable {
    case topLeading
    case topTrailing

    var id: String { rawValue }

    var label: String {
        switch self {
        case .topLeading: return "Top left"
        case .topTrailing: return "Top right"
        }
    }
}
