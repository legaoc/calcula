import SwiftUI
import UIKit

/// Onboarding de 4 pasos (igual que la web, MAP.md §3.6).
/// Se muestra cuando `profileLoaded && profile?.onboardingDone != true`
/// (ver `CalculaApp`). Al terminar llama a `store.finishOnboarding`,
/// que guarda el perfil y crea las cuentas "Gastos" / "Ahorro" elegidas.
struct OnboardingView: View {
    @EnvironmentObject private var store: DataStore

    @State private var step = 0
    @State private var name = ""
    @State private var income = "fortnightly"
    @State private var currency = "MXN"
    @State private var colors: [String] = ["111111"]
    @State private var wants: Set<String> = []
    @State private var customColor = Color.black
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var didPrefill = false

    private var isLastStep: Bool { step == 3 }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Paso \(step + 1) de 4")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(step + 1), total: 4)
                    .tint(.calculaAccent)
            }
            .padding()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch step {
                    case 0: incomeStep
                    case 1: currencyStep
                    case 2: colorsStep
                    default: wantsStep
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }

            Divider()

            HStack(spacing: 12) {
                if step == 0 {
                    Button("Cancelar") {
                        Task { await finish() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                } else {
                    Button("Atrás") {
                        step -= 1
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                }

                Spacer()

                Button(isLastStep ? "Empezar" : "Siguiente") {
                    if isLastStep {
                        Task { await finish() }
                    } else {
                        step += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.calculaAccent)
                .disabled(isBusy || (step == 2 && colors.isEmpty))
            }
            .padding()
        }
        .background(Color.calculaBackground)
        .task {
            prefillIfNeeded()
        }
    }

    // MARK: - Paso 1: cadencia de pago

    private var incomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("¿Cada cuándo te pagan?")
                .font(.title2.bold())
            Text("Así organizamos tus quincenas y tus metas.")
                .foregroundStyle(.secondary)
            ForEach(IncomeOption.allCases) { option in
                optionButton(
                    title: option.label,
                    selected: income == option.rawValue
                ) {
                    income = option.rawValue
                }
            }
        }
    }

    // MARK: - Paso 2: moneda

    private var currencyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("¿En qué moneda?")
                .font(.title2.bold())
            Text("Es la moneda con la que se muestran todos tus montos.")
                .foregroundStyle(.secondary)
            optionButton(title: "Pesos mexicanos (MXN)", selected: currency == "MXN") {
                currency = "MXN"
            }
            optionButton(title: "Dólares (USD)", selected: currency == "USD") {
                currency = "USD"
            }
        }
    }

    // MARK: - Paso 3: colores

    private var colorsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Elige tus colores")
                .font(.title2.bold())
            Text("Elige hasta 3. El primero es el acento de la app.")
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 56), spacing: 12)],
                spacing: 12
            ) {
                ForEach(ThemePalette.swatches) { swatch in
                    colorSwatch(hex: swatch.hex, name: swatch.name)
                }
            }

            HStack(spacing: 12) {
                ColorPicker("Color propio", selection: $customColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44, height: 44)
                Button("Agregar color propio") {
                    addCustomColor()
                }
                .buttonStyle(.bordered)
                .disabled(colors.count >= 3)
            }

            if !colors.isEmpty {
                Text("Elegidos: \(colors.count) de 3")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Paso 4: cuentas

    private var wantsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("¿Qué cuentas quieres?")
                .font(.title2.bold())
            Text("Puedes crear más cuentas después, desde Ajustes.")
                .foregroundStyle(.secondary)

            TextField("Tu nombre (opcional)", text: $name)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)

            ForEach(WantOption.allCases) { option in
                optionButton(
                    title: option.label,
                    subtitle: option.subtitle,
                    selected: wants.contains(option.rawValue)
                ) {
                    toggleWant(option.rawValue)
                }
            }
        }
    }

    // MARK: - Componentes

    private func optionButton(
        title: String,
        subtitle: String? = nil,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.calculaAccent)
                }
            }
            .padding()
            .background(Color.calculaCard)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Color.calculaAccent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func colorSwatch(hex: String, name: String) -> some View {
        let selected = colors.contains(hex)
        return Button {
            toggleColor(hex)
        } label: {
            ZStack {
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Circle().stroke(
                            selected ? Color.calculaAccent : Color.primary.opacity(0.15),
                            lineWidth: selected ? 3 : 1
                        )
                    )
                if selected {
                    Image(systemName: "checkmark")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }

    // MARK: - Lógica

    private func prefillIfNeeded() {
        guard !didPrefill else { return }
        didPrefill = true
        guard let profile = store.profile else { return }
        if let existing = profile.name, !existing.isEmpty { name = existing }
        if let existing = profile.income, !existing.isEmpty { income = existing }
        if let existing = profile.currency, !existing.isEmpty { currency = existing }
        if !profile.colors.isEmpty { colors = Array(profile.colors.prefix(3)) }
        wants = Set(profile.wants)
    }

    private func toggleColor(_ hex: String) {
        if colors.contains(hex) {
            colors.removeAll { $0 == hex }
        } else if colors.count < 3 {
            colors.append(hex)
        }
    }

    private func addCustomColor() {
        guard colors.count < 3 else { return }
        let hex = Self.hexString(from: customColor)
        guard !colors.contains(hex) else { return }
        colors.append(hex)
    }

    private func toggleWant(_ want: String) {
        if wants.contains(want) {
            wants.remove(want)
        } else {
            wants.insert(want)
        }
    }

    private func finish() async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        let orderedWants = WantOption.allCases
            .map(\.rawValue)
            .filter { wants.contains($0) }
        do {
            try await store.finishOnboarding(
                name: name.trimmingCharacters(in: .whitespaces),
                income: income,
                currency: currency,
                colors: colors.isEmpty ? ["111111"] : colors,
                wants: orderedWants
            )
        } catch {
            errorMessage = "No se pudo guardar. Revisa tu conexión e inténtalo de nuevo."
        }
    }

    /// Hex sin "#" (como lo guarda la web en `profile.colors`).
    private static func hexString(from color: Color) -> String {
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "%02x%02x%02x",
            Int(r * 255), Int(g * 255), Int(b * 255)
        )
    }
}

// MARK: - Opciones

private enum IncomeOption: String, CaseIterable, Identifiable {
    case daily, weekly, fortnightly, monthly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: return "Diario"
        case .weekly: return "Cada semana"
        case .fortnightly: return "Cada quincena"
        case .monthly: return "Cada mes"
        }
    }
}

private enum WantOption: String, CaseIterable, Identifiable {
    case charges, savings, subs, recurring

    var id: String { rawValue }

    var label: String {
        switch self {
        case .charges: return "Cargos"
        case .savings: return "Ahorro"
        case .subs: return "Suscripciones"
        case .recurring: return "Pagos recurrentes"
        }
    }

    var subtitle: String {
        switch self {
        case .charges: return "Crea la cuenta \"Gastos\""
        case .savings: return "Crea la cuenta \"Ahorro\""
        case .subs: return "Tus suscripciones, como Netflix"
        case .recurring: return "Pagos que se repiten, como el internet"
        }
    }
}

/// Paleta de 20 colores de la web (MAP.md §6: `THEME_COLORS`).
private enum ThemePalette {
    struct Swatch: Identifiable {
        var id: String { hex }
        var name: String
        var hex: String
    }

    static let swatches: [Swatch] = [
        .init(name: "Grafito", hex: "1a1a1e"),
        .init(name: "Carbón", hex: "242428"),
        .init(name: "Piedra", hex: "3f3f46"),
        .init(name: "Azul noche", hex: "1e3a5f"),
        .init(name: "Petróleo", hex: "164e63"),
        .init(name: "Mar", hex: "0b3d4a"),
        .init(name: "Bosque", hex: "0f3d2e"),
        .init(name: "Musgo", hex: "14532d"),
        .init(name: "Olivo", hex: "365314"),
        .init(name: "Vino", hex: "4a1c2c"),
        .init(name: "Cereza", hex: "7a1f1f"),
        .init(name: "Terracota", hex: "9a3412"),
        .init(name: "Cacao", hex: "3b2d1a"),
        .init(name: "Café", hex: "5c4033"),
        .init(name: "Uva", hex: "2d1b4e"),
        .init(name: "Índigo", hex: "312e81"),
        .init(name: "Medianoche", hex: "1e1b4b"),
        .init(name: "Tinta", hex: "0f172a"),
        .init(name: "Pizarra", hex: "334155"),
        .init(name: "Malva", hex: "6b2d5b"),
    ]
}
