import SwiftUI

extension Color {
    init(hex: String) {
        let sanitizedHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var integer: UInt64 = 0
        Scanner(string: sanitizedHex).scanHexInt64(&integer)

        let red = Double((integer >> 16) & 0xFF) / 255
        let green = Double((integer >> 8) & 0xFF) / 255
        let blue = Double(integer & 0xFF) / 255

        self.init(red: red, green: green, blue: blue)
    }

    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    var hex: String {
        #if os(macOS)
            let resolved = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(.white)
            let red = Int((resolved.redComponent * 255).rounded())
            let green = Int((resolved.greenComponent * 255).rounded())
            let blue = Int((resolved.blueComponent * 255).rounded())
        #else
            let resolved = UIColor(self)
            var redComponent: CGFloat = 0
            var greenComponent: CGFloat = 0
            var blueComponent: CGFloat = 0
            var alpha: CGFloat = 0
            resolved.getRed(&redComponent, green: &greenComponent, blue: &blueComponent, alpha: &alpha)
            let red = Int((redComponent * 255).rounded())
            let green = Int((greenComponent * 255).rounded())
            let blue = Int((blueComponent * 255).rounded())
        #endif

        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    static let categoryBlue = Color(hex: "#4F8EF7")
    static let categoryGreen = Color(hex: "#34C759")
    static let categoryOrange = Color(hex: "#FF9500")
    static let categoryRed = Color(hex: "#FF3B30")
    static let categoryPurple = Color(hex: "#AF52DE")
    static let categoryYellow = Color(hex: "#FFCC00")
    static let categoryPink = Color(hex: "#FF2D55")
    static let categoryTeal = Color(hex: "#5AC8FA")
    static let investment = Color(hex: "#FFB300")
}
