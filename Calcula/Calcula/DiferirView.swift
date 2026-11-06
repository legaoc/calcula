import SwiftUI

// MARK: - Diferir (pestaña "Diferir", MAP.md §3.3 y §4.5)
// Hero "Reparte un pago" + lista de pagos programados ordenados por
// nextPayment. Tocar uno abre el studio para editarlo o diferirlo.

struct DiferirView: View {
    @EnvironmentObject private var store: DataStore
    @State private var showingNewDefer = false
    @State private var selectedPayment: ScheduledPayment?

    private var sortedPayments: [ScheduledPayment] {
        store.scheduledPayments.sorted {
            ($0.nextPayment ?? .distantFuture) < ($1.nextPayment ?? .distantFuture)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Diferir")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("Reparte un pago")
                            .font(.largeTitle.bold())
                        Text("Elige un pago que ya tienes, o una cantidad, y júntalo en semanas, quincenas o meses.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Diferir una cantidad") {
                            showingNewDefer = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.calculaAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }

                Section("¿Qué pago quieres diferir?") {
                    if sortedPayments.isEmpty {
                        Text("Todavía no hay pagos. Puedes diferir una cantidad.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(sortedPayments) { payment in
                        Button {
                            selectedPayment = payment
                        } label: {
                            DiferirRow(payment: payment)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .background(Color.calculaBackground)
            .navigationTitle("Diferir")
            .sheet(isPresented: $showingNewDefer) {
                DeferStudioView(pago: nil)
            }
            .sheet(item: $selectedPayment) { payment in
                DeferStudioView(pago: payment)
            }
        }
    }

    /// "Apartas en N quincenas/semanas/meses" si el pago ya tiene plan.
    private func splitLabel(for payment: ScheduledPayment) -> String? {
        let count = payment.splitCount
        guard count > 1 else { return nil }
        let unitWord: String
        switch payment.splitUnit {
        case "week": unitWord = "semanas"
        case "month": unitWord = "meses"
        default: unitWord = "quincenas"
        }
        return "Apartas en \(count) \(unitWord)"
    }

    @ViewBuilder
    private func DiferirRow(payment: ScheduledPayment) -> some View {
        let accountName = store.accounts.first { $0.id == payment.accountId }?.name
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(payment.name)
                    .font(.headline)
                Spacer()
                Text(Format.money(payment.amount, currency: store.profile?.currency ?? "MXN"))
                    .font(.headline)
            }
            HStack(spacing: 6) {
                if let next = payment.nextPayment {
                    Text(Format.shortDate(next))
                }
                if let accountName {
                    Text("·")
                    Text(accountName)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if let split = splitLabel(for: payment) {
                Text(split)
                    .font(.footnote)
                    .foregroundStyle(Color.calculaAccent)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Studio de diferir (MAP.md §4.5)
// Edita un pago existente (nombre, monto, frecuencia, próxima fecha y
// plan de diferir) o crea uno nuevo con "Diferir una cantidad".

struct DeferStudioView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    private let pago: ScheduledPayment?

    @State private var name: String
    @State private var amountText: String
    @State private var frequency: String
    @State private var customDays: Int
    @State private var nextPayment: Date
    @State private var splitUnit: String
    @State private var parts: Int
    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let frequencies = [
        "weekly", "every15", "monthly", "bimonthly",
        "quarterly", "semiannual", "annual", "custom",
    ]
    private static let partOptions = [2, 3, 4, 6, 8, 12]

    init(pago: ScheduledPayment?) {
        self.pago = pago
        let split = pago?.splitCount ?? 1
        _name = State(initialValue: pago?.name ?? "")
        _amountText = State(initialValue: pago.map { String($0.amount) } ?? "")
        _frequency = State(initialValue: pago?.frequency ?? "monthly")
        _customDays = State(initialValue: pago?.customDays ?? 30)
        _nextPayment = State(initialValue: pago?.nextPayment
            ?? Calendar.current.date(byAdding: .day, value: 30, to: Date())
            ?? Date())
        _splitUnit = State(initialValue: pago?.splitUnit ?? "fortnight")
        _parts = State(initialValue: Self.partOptions.contains(split) ? split : 2)
    }

    private var amount: Double {
        Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    /// Solo se puede diferir si el vencimiento está más allá de la
    /// quincena siguiente (MAP.md §4.5). Sin pago, siempre se puede.
    private var canEditPlan: Bool {
        guard let pago else { return true }
        let context = QuincenaEngine.currentAndNext(settings: store.payroll)
        return QuincenaEngine.canDefer(pago, context: context)
    }

    private var planDates: [Date]? {
        QuincenaEngine.deferPlan(amount: amount, due: nextPayment, parts: parts, unit: splitUnit)
    }

    private var isNew: Bool { pago == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section(isNew ? "Diferir una cantidad" : "Pago") {
                    if isNew {
                        Text("Crea un pago diferido: se reparte en partes iguales entre varias quincenas, semanas o meses.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if !isNew {
                        TextField("Nombre", text: $name)
                    }
                    TextField("Monto", text: $amountText)
                        .keyboardType(.decimalPad)
                    if !isNew {
                        Picker("Frecuencia", selection: $frequency) {
                            ForEach(Self.frequencies, id: \.self) { key in
                                Text(QuincenaEngine.frequencyLabel(key)).tag(key)
                            }
                        }
                        if frequency == "custom" {
                            Stepper("Cada \(customDays) días", value: $customDays, in: 1...365)
                        }
                        DatePicker("Próximo pago", selection: $nextPayment, displayedComponents: .date)
                    } else {
                        DatePicker("Fecha de vencimiento", selection: $nextPayment, displayedComponents: .date)
                    }
                }

                Section("Plan de diferir") {
                    if !canEditPlan {
                        Text("Este pago ya toca esta quincena o la siguiente. No se puede diferir.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    Picker("Unidad", selection: $splitUnit) {
                        Text("Semanas").tag("week")
                        Text("Quincenas").tag("fortnight")
                        Text("Meses").tag("month")
                    }
                    .pickerStyle(.segmented)
                    Picker("Nº de pagos", selection: $parts) {
                        ForEach(Self.partOptions, id: \.self) { option in
                            Text("\(option)").tag(option)
                        }
                    }
                    if let planDates, amount > 0 {
                        let share = amount / Double(parts)
                        ForEach(Array(planDates.enumerated()), id: \.offset) { index, date in
                            HStack {
                                Text("Pago \(index + 1)")
                                Spacer()
                                Text(Format.date(date))
                                    .foregroundStyle(.secondary)
                                Text(Format.money(share, currency: store.profile?.currency ?? "MXN"))
                                    .fontWeight(.semibold)
                            }
                            .font(.subheadline)
                        }
                    } else if amount > 0 {
                        Text("Eso empezaría antes de hoy")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .disabled(!canEditPlan)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(isNew ? "Diferir una cantidad" : "Diferir pago")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        Task { await save() }
                    }
                    .disabled(isSaving || amount <= 0)
                }
            }
        }
    }

    private func save() async {
        guard amount > 0 else {
            errorMessage = "Escribe un monto mayor a cero"
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            if let pago, let id = pago.id {
                var patch: [String: Any] = [
                    "name": name.trimmingCharacters(in: .whitespaces),
                    "amount": amount,
                    "frequency": frequency,
                    "customDays": customDays,
                    "nextPayment": nextPayment,
                ]
                if canEditPlan {
                    patch["splitParts"] = parts
                    patch["splitUnit"] = splitUnit
                    patch["splitQuincenas"] = splitUnit == "fortnight" ? parts : 1
                }
                try await store.updateScheduledPayment(id: id, patch: patch)
            } else {
                let payment = ScheduledPayment(
                    accountId: store.accounts.first?.id ?? "",
                    name: "Pago diferido",
                    amount: amount,
                    frequency: "annual",
                    customDays: 30,
                    nextPayment: nextPayment,
                    kind: "payment",
                    isSubscription: false,
                    splitQuincenas: splitUnit == "fortnight" ? parts : 1,
                    splitParts: parts,
                    splitUnit: splitUnit,
                    deferCustom: true
                )
                try await store.addScheduledPayment(payment)
            }
            dismiss()
        } catch {
            errorMessage = "No se pudo guardar el pago"
        }
    }
}
