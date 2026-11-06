import SwiftUI

// MARK: - Diseño (mismos tokens de la versión web)
extension Color {
    /// Fondo gris claro de la web (#e7e7ee). En SwiftUI se usa el fondo
    /// agrupado del sistema, que se adapta a modo claro/oscuro.
    static let calculaBackground = Color(.systemGroupedBackground)
    static let calculaCard = Color(.secondarySystemGroupedBackground)
    /// Acento casi negro de la web (#111111).
    static let calculaAccent = Color(red: 0.067, green: 0.067, blue: 0.067)
    /// Dorado usado en detalles (sello / icono).
    static let calculaGold = Color(red: 0.725, green: 0.592, blue: 0.357)

    /// Hex sin "#" como lo guarda la web en `cardColor` ("111111").
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: h).scanHexInt64(&value)
        let r, g, b: Double
        if h.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        } else {
            r = 0.067; g = 0.067; b = 0.067
        }
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Formato de dinero y fechas (es_MX / MXN por defecto, como la web)
enum Format {
    /// La web usa la moneda global del perfil: MXN con locale es-MX,
    /// USD con locale en-US, siempre 2 decimales.
    static func money(_ value: Double, currency: String = "MXN") -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.locale = Locale(identifier: currency == "USD" ? "en-US" : "es_MX")
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_MX")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    static func date(_ date: Date?) -> String {
        guard let date else { return "" }
        return dayMonth.string(from: date)
    }

    /// Fecha corta sin año ("30 sep", "15 dic"), como `formatShortDate`
    /// de la web. La usan las tarjetas de cuenta, quincena, diferir y
    /// el detalle de meta.
    static let shortDayMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_MX")
        f.dateFormat = "d MMM"
        return f
    }()

    static func shortDate(_ date: Date?) -> String {
        guard let date else { return "" }
        return shortDayMonth.string(from: date)
    }
}
