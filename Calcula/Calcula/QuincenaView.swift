import SwiftUI

// MARK: - Pantalla de quincena (MAP.md §3.6 y §4.2–4.4)
// "Esta quincena" o "Siguiente quincena": hero con lo que hay que pagar
// y apartar, sección de pagos vencidos y sección de apartados.

struct QuincenaScreen: View {
    @EnvironmentObject private var store: DataStore

    let windowIndex: Int

    @State private var abonarAccount: Account?
    @State private var deferPayment: ScheduledPayment?
    @State private var paymentToMark: ScheduledPayment?
    @State private var markOccurrenceText: String?
    @State private var showingPayroll = false

    private var context: QuincenaContext {
        QuincenaEngine.currentAndNext(settings: store.payroll)
    }

    private var plan: QuincenaPlan? {
        guard context.windows.indices.contains(windowIndex) else { return nil }
        return QuincenaEngine.buildQuincenaPlan(
            windowIndex: windowIndex,
            context: context,
            payments: store.scheduledPayments,
            accounts: store.accounts
        )
    }

    private var currency: String { store.profile?.currency ?? "MXN" }

    private var dueItems: [QuincenaItem] {
        plan?.items.filter(\.isDue) ?? []
    }

    private var setAsideItems: [QuincenaItem] {
        plan?.items.filter { !$0.isDue } ?? []
    }

    var body: some View {
        Group {
            if let plan {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nómina del \(Format.date(plan.window.start))")
                                .font(.title2.bold())
                            Text("Cubre \(Format.date(plan.window.start)) – \(Format.date(plan.window.end))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Pagar ahora")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(Format.money(plan.toPay, currency: currency))
                                        .font(.title3.bold())
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Apartar")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(Format.money(plan.toSetAside, currency: currency))
                                        .font(.title3.bold())
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 4)
                    }

                    Section("Pagos de esta quincena") {
                        if dueItems.isEmpty {
                            Text("Nada por pagar esta quincena.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(dueItems) { item in
                            QuincenaDueRow(
                                item: item,
                                currency: currency,
                                onPay: {
                                    paymentToMark = item.payment
                                    markOccurrenceText = item.occurrenceTotal > 1
                                        ? "Pago \(item.occurrenceIndex) de \(item.occurrenceTotal)"
                                        : nil
                                },
                                onAbonar: { abonarAccount = item.account },
                                onDiferir: { deferPayment = item.payment }
                            )
                        }
                    }

                    Section("Apartar") {
                        if setAsideItems.isEmpty {
                            Text("Nada que apartar esta quincena.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(setAsideItems) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.payment.name)
                                        .font(.headline)
                                    Spacer()
                                    Text(Format.money(item.share, currency: currency))
                                        .font(.headline)
                                }
                                HStack(spacing: 6) {
                                    Text("Apartar \(Format.money(item.share, currency: currency)) · \(item.installment)/\(item.split)")
                                    Text("·")
                                    Text(Format.date(item.due))
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .navigationTitle("Nómina del \(Format.date(plan.window.start))")
            } else {
                ContentUnavailableView(
                    "Sin quincena",
                    systemImage: "calendar",
                    description: Text("No se pudo calcular esta quincena.")
                )
            }
        }
        .background(Color.calculaBackground)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Nómina") { showingPayroll = true }
            }
        }
        .sheet(item: $abonarAccount) { account in
            AddMovementView(preselectedAccountId: account.id)
        }
        .sheet(item: $deferPayment) { payment in
            DeferStudioView(pago: payment)
        }
        .sheet(item: $paymentToMark) { payment in
            MarkPaymentSheet(payment: payment, occurrenceText: markOccurrenceText)
        }
        .sheet(isPresented: $showingPayroll) {
            PayrollSheet()
        }
    }
}

/// Fila de un ítem vencido: nombre, monto, vencimiento y acciones.
/// Recurrentes: "Pagar" (bloqueado si no es el siguiente por pagar) y
/// "Diferir". Cargos: "Abonar".
private struct QuincenaDueRow: View {
    let item: QuincenaItem
    let currency: String
    let onPay: () -> Void
    let onAbonar: () -> Void
    let onDiferir: () -> Void

    private var canPay: Bool { QuincenaEngine.isNextPayable(item) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.payment.name)
                    .font(.headline)
                Spacer()
                Text(Format.money(item.amount, currency: currency))
                    .font(.headline)
            }
            HStack(spacing: 6) {
                Text(Format.date(item.due))
                if item.overdue {
                    Text("· Vencido")
                        .foregroundStyle(.red)
                }
                if item.occurrenceTotal > 1 {
                    Text("· Pago \(item.occurrenceIndex) de \(item.occurrenceTotal)")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                switch item.kind {
                case .recurring:
                    Button("Pagar", action: onPay)
                        .buttonStyle(.borderedProminent)
                        .tint(Color.calculaAccent)
                        .disabled(!canPay)
                    Button("Diferir", action: onDiferir)
                        .buttonStyle(.bordered)
                    if !canPay {
                        Text("Paga el anterior primero")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                case .charges:
                    Button("Abonar", action: onAbonar)
                        .buttonStyle(.borderedProminent)
                        .tint(Color.calculaAccent)
                }
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Tarjeta compacta de quincena (Inicio, MAP.md §3.2)
// Mismo contenido que `renderQuincenaCard` de la web: "Esta quincena" /
// "Nómina del {fecha corta}" / "Cubre {rango corto}", cantidad grande
// con "de tu nómina", las dos acciones "Pagar ahora" y "Apartar" con
// sus cantidades, y la lista compacta de ítems (con insignia Pagar /
// Vencido / Apartar N/M) o el mensaje "No te toca pagar ni apartar
// nada aquí." cuando no hay nada. Presentación nativa de iOS.

struct QuincenaCard: View {
    @EnvironmentObject private var store: DataStore

    let windowIndex: Int
    let context: QuincenaContext

    private var plan: QuincenaPlan? {
        guard context.windows.indices.contains(windowIndex) else { return nil }
        return QuincenaEngine.buildQuincenaPlan(
            windowIndex: windowIndex,
            context: context,
            payments: store.scheduledPayments,
            accounts: store.accounts
        )
    }

    private var isCurrent: Bool { windowIndex == context.currentIndex }
    private var currency: String { store.profile?.currency ?? "MXN" }

    /// Fondo de las cajas internas: claro translúcido sobre la tarjeta
    /// oscura ("Esta quincena") y relleno del sistema sobre la clara.
    private var innerBackground: Color {
        isCurrent ? Color.white.opacity(0.08) : Color(.tertiarySystemFill)
    }

    var body: some View {
        Group {
            if let plan {
                NavigationLink {
                    QuincenaScreen(windowIndex: windowIndex)
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(isCurrent ? "Esta quincena" : "Siguiente quincena")
                                    .font(.caption.bold())
                                    .foregroundStyle(isCurrent ? .white.opacity(0.7) : .secondary)
                                Text("Nómina del \(Format.shortDate(plan.window.start))")
                                    .font(.headline)
                                Text("Cubre \(Format.shortDate(plan.window.start)) – \(Format.shortDate(plan.window.end))")
                                    .font(.subheadline)
                                    .foregroundStyle(isCurrent ? .white.opacity(0.8) : .secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(Format.money(plan.fromPayroll, currency: currency))
                                    .font(.system(size: 32, weight: .bold))
                                Text("de tu nómina")
                                    .font(.caption)
                                    .foregroundStyle(isCurrent ? .white.opacity(0.7) : .secondary)
                            }
                        }

                        HStack(spacing: 8) {
                            splitBox(label: "Pagar ahora", amount: plan.toPay)
                            splitBox(label: "Apartar", amount: plan.toSetAside)
                        }

                        if plan.items.isEmpty {
                            Text("No te toca pagar ni apartar nada aquí.")
                                .font(.subheadline)
                                .foregroundStyle(isCurrent ? .white.opacity(0.7) : .secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(innerBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            VStack(spacing: 8) {
                                ForEach(plan.items) { item in
                                    QuincenaCompactRow(
                                        item: item,
                                        currency: currency,
                                        isCurrent: isCurrent
                                    )
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isCurrent ? Color.calculaAccent : Color.calculaCard)
                    .foregroundStyle(isCurrent ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func splitBox(label: String, amount: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(isCurrent ? .white.opacity(0.7) : .secondary)
            Text(Format.money(amount, currency: currency))
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(innerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// Fila compacta de un ítem de quincena: insignia (Pagar / Vencido /
/// Apartar N/M), nombre, cuenta y parte de esta quincena, como
/// `renderQuincenaItems` de la web.
private struct QuincenaCompactRow: View {
    let item: QuincenaItem
    let currency: String
    let isCurrent: Bool

    private var badgeText: String {
        if item.isDue {
            return item.overdue ? "Vencido" : "Pagar"
        }
        return "Apartar \(item.installment)/\(item.split)"
    }

    /// "1 pago de $X" / "N pagos de $X", como `paymentsLabel` de la web.
    private var multiLabel: String? {
        guard item.isDue, item.dueCount > 1 else { return nil }
        return item.dueCount <= 1
            ? "1 pago de \(Format.money(item.unitAmount, currency: currency))"
            : "\(item.dueCount) pagos de \(Format.money(item.unitAmount, currency: currency))"
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(badgeText)
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemFill))
                .foregroundStyle(.primary)
                .clipShape(Capsule())
            VStack(alignment: .leading, spacing: 2) {
                Text(item.payment.name)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(item.account.name)
                    if let multiLabel {
                        Text("· \(multiLabel)")
                    }
                }
                .font(.caption)
                .foregroundStyle(isCurrent ? .white.opacity(0.7) : .secondary)
            }
            Spacer()
            Text(Format.money(item.share, currency: currency))
                .fontWeight(.semibold)
        }
        .font(.subheadline)
    }
}

// MARK: - Hoja "Tu Nómina" (WEB-INVENTORY §6)
// Días de pago de las quincenas; Guardar persiste en settings/payroll
// (setDoc sin merge, igual que la web). Se abre desde el botón "Nómina"
// de Inicio ("Para estar al día") y del detalle de quincena.
struct PayrollSheet: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    /// 0 = último día del mes; si no, Día 16, 17, 18, 20, 25, 28 o 30.
    @State private var payday1 = 15
    @State private var payday2Option = 0
    @State private var didLoad = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let secondOptions = [16, 17, 18, 20, 25, 28, 30]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Usamos tus días de pago para armar esta quincena y la siguiente.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Primera quincena") {
                    Picker("Día", selection: $payday1) {
                        ForEach(1...15, id: \.self) { day in
                            Text("Día \(day)").tag(day)
                        }
                    }
                }
                Section("Segunda quincena") {
                    Picker("Día", selection: $payday2Option) {
                        Text("Último día del mes").tag(0)
                        ForEach(Self.secondOptions, id: \.self) { day in
                            Text("Día \(day)").tag(day)
                        }
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Tu Nómina")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
            .task {
                guard !didLoad else { return }
                didLoad = true
                payday1 = store.payroll.payday1
                payday2Option = store.payroll.payday2LastDay ? 0 : store.payroll.payday2
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.setPayroll(PayrollSettings(
                payday1: payday1,
                payday2: payday2Option == 0 ? 30 : payday2Option,
                payday2LastDay: payday2Option == 0
            ))
            dismiss()
        } catch {
            errorMessage = "No se pudo guardar la nómina"
        }
    }
}
