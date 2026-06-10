import SwiftUI

/// How a `DecorationStyle` is drawn: a set of diagonal corner stripes, or the
/// Amiga "boing ball" nestled in the corner.
enum DecorationKind: Equatable {
    case stripes
    case ball
}

/// An 80s-flavored corner decoration for the switcher panel — e.g. the Sinclair
/// ZX Spectrum's diagonal rainbow stripes (see `PanelDecoration`), or the Amiga
/// boing ball (see `BoingBallDecoration`). Drawn hugging the panel's top corner.
enum DecorationStyle: String, CaseIterable, Identifiable {
    case none
    case zxSpectrum
    case appleRainbow
    case vaporwave
    case sunset
    case love
    case amiga

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .zxSpectrum: return "ZX Spectrum"
        case .appleRainbow: return "Apple rainbow"
        case .vaporwave: return "Vaporwave"
        case .sunset: return "Sunset"
        case .love: return "Love"
        case .amiga: return "Amiga boing ball"
        }
    }

    /// Whether this style is drawn as corner stripes or as the boing ball.
    var kind: DecorationKind {
        self == .amiga ? .ball : .stripes
    }

    /// Stripe colors, ordered from the one nearest the corner inward. Empty for
    /// `.none`.
    var colors: [Color] {
        hexes.map { Color(hexString: $0) }
    }

    private var hexes: [String] {
        switch self {
        case .none: return []
        case .zxSpectrum: return ["#D52B1E", "#FFD500", "#00A651", "#00AEEF"]
        case .appleRainbow: return ["#E03A3E", "#F5821F", "#FDB827", "#61BB46", "#009DDC", "#963D97"]
        case .vaporwave: return ["#FF6AD5", "#C774E8", "#AD8CFF", "#8795E8", "#94D0FF"]
        case .sunset: return ["#FF512F", "#F09819", "#FFD200"]
        case .love: return ["#E40303", "#FF8C00", "#FFED00", "#008026", "#004DFF", "#750787"]
        case .amiga: return []   // drawn as a ball, not stripes — see BoingBallDecoration
        }
    }
}
