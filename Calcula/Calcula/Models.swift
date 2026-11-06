import Foundation
import FirebaseFirestore

// MARK: - Modelos Firestore (mismo proyecto `psnllega`, mismas colecciones
// y campos que la versión web: users/{uid}/<colección>/<doc>).
// Ver MAP.md para el mapa completo. Los campos opcionales existen en la
// web pero no siempre están presentes en todos los documentos.

/// Cuenta: users/{uid}/accounts/{id}
struct Account: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var name: String = ""
    /// "charges" (cargos / tarjetas) o "recurring" (pagos recurrentes).
    var type: String = "charges"
    var isSubscription: Bool = false
    var iconSlug: String? = nil
    var iconHex: String? = nil
    var iconDomain: String? = nil
    var balance: Double = 0
    /// Día del mes en que vence (solo cuentas "charges"). 0 = sin día.
    var dueDay: Int = 0
    var categories: [String] = []
    var sortOrder: Int = 0
    /// Oculta la cuenta del inicio (la web lo guarda con este campo).
    var hiddenFromHome: Bool = false
    var cardColor: String? = nil
    @ServerTimestamp var createdAt: Date?

    var isRecurring: Bool { type == "recurring" }
}

/// Movimiento: users/{uid}/movements/{id}
/// type es literalmente "cargo", "abono" o "pago" (la web lo normaliza con
/// lowercased+trim). cargo suma al saldo, abono resta, pago no mueve saldos.
struct Movement: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var accountId: String = ""
    var type: String = "cargo"
    var amount: Double = 0
    var note: String = ""
    /// Categoría. Solo la escribe el registro rápido; el modal por cuenta
    /// no la escribe (esos movimientos cuentan como "otros").
    var category: String? = nil
    /// Id del pago programado. Solo en movimientos type "pago".
    var scheduledPaymentId: String? = nil
    @ServerTimestamp var createdAt: Date?

    var isCharge: Bool { type.lowercased() == "cargo" }
    /// Delta que el movimiento aplica al saldo de la cuenta.
    /// "pago" no mueve ningún saldo (ver MAP.md §1.3 y §8.6).
    var balanceDelta: Double {
        switch type.lowercased() {
        case "cargo": return amount
        case "abono": return -amount
        default: return 0
        }
    }
}

/// Meta: users/{uid}/goals/{id}
struct Goal: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var name: String = ""
    var target: Double = 0
    var saved: Double = 0
    /// Frecuencia de ahorro (ej. "semanal", "quincenal", "mensual").
    var cadence: String = ""
    var deadline: Date? = nil
    @ServerTimestamp var createdAt: Date?

    var progress: Double {
        guard target > 0 else { return 0 }
        return min(max(saved / target, 0), 1)
    }
}

/// Presupuesto: users/{uid}/budgets/{id}
struct Budget: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var name: String = ""
    var amount: Double = 0
    var category: String = ""
    @ServerTimestamp var createdAt: Date?
}

/// Pago programado: users/{uid}/scheduledPayments/{id}
struct ScheduledPayment: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var accountId: String = ""
    var name: String = ""
    var amount: Double = 0
    /// Frecuencia (ej. "mensual", "semanal", "custom").
    var frequency: String = ""
    var customDays: Int = 30
    var nextPayment: Date? = nil
    var active: Bool = true
    /// "subscription" o "payment".
    var kind: String = "payment"
    var isSubscription: Bool = false
    var iconSlug: String? = nil
    var iconHex: String? = nil
    var iconDomain: String? = nil
    /// En cuántas quincenas se reparte el pago (plan clásico, 1–12).
    var splitQuincenas: Int? = nil
    /// Nuevo nombre del mismo concepto (lo escribe el studio de diferir).
    var splitParts: Int? = nil
    /// Unidad del plan del studio: "week" | "fortnight" | "month".
    var splitUnit: String? = nil
    /// true solo en pagos creados por "Diferir una cantidad" (sin cuenta).
    var deferCustom: Bool? = nil
    @ServerTimestamp var createdAt: Date?

    /// Nº de partes en que se reparte: splitParts, si no splitQuincenas,
    /// si no 1 (misma lectura con fallback que la web).
    var splitCount: Int {
        if let splitParts, splitParts > 0 { return splitParts }
        if let splitQuincenas, splitQuincenas > 0 { return splitQuincenas }
        return 1
    }
}

/// Categoría personalizada: {id (slug), label}.
struct CustomCategory: Codable, Equatable {
    var id: String = ""
    var label: String = ""
}

/// Perfil: users/{uid}/settings/profile (documento único).
struct UserProfile: Codable, Equatable {
    var name: String? = nil
    /// Cadencia de ingresos: "daily" | "weekly" | "fortnightly" | "monthly".
    var income: String? = nil
    /// Moneda global: "MXN" | "USD".
    var currency: String? = nil
    /// Hasta 3 hex sin "#"; colors[0] es el acento.
    var colors: [String] = []
    /// Qué cuentas quiere: "charges" | "savings" | "subs" | "recurring".
    var wants: [String] = []
    var customCats: [CustomCategory] = []
    var onboardingDone: Bool = false
}

/// Nómina: users/{uid}/settings/payroll (documento único).
struct PayrollSettings: Codable, Equatable {
    /// Día de la primera quincena (1–15).
    var payday1: Int = 15
    /// Día de la segunda quincena (16–31); 30 es placeholder si
    /// payday2LastDay es true.
    var payday2: Int = 30
    /// true = segunda quincena el último día del mes.
    var payday2LastDay: Bool = true
}

/// Recordatorios: users/{uid}/settings/reminders (documento único).
struct ReminderSettings: Codable, Equatable {
    var enabled: Bool = true
    /// Antelación en días (la UI solo alterna 1 ↔ 2).
    var daysBefore: Int = 2
}
