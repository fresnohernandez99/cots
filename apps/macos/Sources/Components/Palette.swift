import AppKit
import CotsCore
import SwiftUI

/// Named note colors. Topics without an explicit color get a stable one from this list.
enum Palette {
    static let names = ["blue", "purple", "pink", "red", "orange", "yellow", "green", "teal", "indigo", "mint", "brown", "gray"]

    static func color(_ name: String?) -> Color? {
        guard let name = name?.lowercased() else { return nil }
        switch name {
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "teal": return .teal
        case "indigo": return .indigo
        case "mint": return .mint
        case "brown": return .brown
        case "gray", "grey": return .gray
        default:
            let hex = name.hasPrefix("#") ? String(name.dropFirst()) : name
            guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
            return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
        }
    }

    static func label(_ name: String) -> LocalizedStringKey {
        switch name {
        case "blue": return "Azul"
        case "purple": return "Morado"
        case "pink": return "Rosa"
        case "red": return "Rojo"
        case "orange": return "Naranja"
        case "yellow": return "Amarillo"
        case "green": return "Verde"
        case "teal": return "Turquesa"
        case "indigo": return "Índigo"
        case "mint": return "Menta"
        case "brown": return "Marrón"
        default: return "Gris"
        }
    }

    /// Non-template dot, so menus show the actual color instead of a monochrome glyph.
    static func swatch(_ color: Color) -> Image {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor(color).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return Image(nsImage: image)
    }

    /// Amber that reads as text: dark in light mode, light in dark mode (≥ 4.5:1 on the
    /// window background either way). System yellow and orange are too pale for text.
    static let amber = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 1, green: 0.702, blue: 0.251, alpha: 1)
            : NSColor(srgbRed: 0.698, green: 0.314, blue: 0, alpha: 1)
    })

    /// "Por revisar": the same blue as on Windows, readable as text in both modes
    /// (5.4:1 light, 6.7:1 dark). System orange was 2.2:1 on white.
    static let pendingBlue = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.353, green: 0.663, blue: 1, alpha: 1)
            : NSColor(srgbRed: 0.039, green: 0.4, blue: 0.839, alpha: 1)
    })

    /// Amber fill for prominent buttons with white text (5.2:1), in both modes.
    static let amberFill = Color(nsColor: NSColor(srgbRed: 0.698, green: 0.314, blue: 0, alpha: 1))

    /// Deterministic across launches (unlike `hashValue`), so a project keeps its color.
    static func topicColor(_ topic: String) -> Color {
        let hash = topic.lowercased().unicodeScalars.reduce(UInt32(5381)) { ($0 &<< 5) &+ $0 &+ $1.value }
        return color(names[Int(hash % UInt32(names.count - 1))])! // gray stays reserved
    }
}
