import SwiftUI

// MARK: - Pantalla de quincena (MAP.md §3.6 y §4.2–4.4)
// "Esta quincena" o "Siguiente quincena": hero con lo que hay que pagar
// y apartar, sección de pagos vencidos y sección de apartados.

struct QuincenaScreen: View {
    @EnvironmentObject private var store: DataStore

    let windowIndex: Int

    @State private var abonarAccount: Account?
    @State private var deferPayment: ScheduledPayment?
    @State private var payingItemId: String?
    @State private var payError: String?

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
                                isPaying: payingItemId == item.id,
                                onPay: { Task { await pay(item) } },
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

                    if let payError {
                        Section {
                            Text(payError)
                                .font(.footnote)
                                .foregroundStyle(.red)
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
        .sheet(item: $abonarAccount) { account in
            AddMovementView(preselectedAccountId: account.id)
        }
        .sheet(item: $deferPayment) { payment in
            DeferStudioView(pago: payment)
        }
    }

    private func pay(_ item: QuincenaItem) async {
        payingItemId = item.id
        defer { payingItemId = nil }
        do {
            try await store.payScheduled(item.payment)
        } catch {
            payError = "No se pudo registrar el pago"
        }
    }
}

/// Fila de un ítem vencido: nombre, monto, vencimiento y acciones.
/// Recurrentes: "Pagar" (bloqueado si no es el siguiente por pagar) y
/// "Diferir". Cargos: "Abonar".
private struct QuincenaDueRow: View {
    let item: QuincenaItem
    let currency: String
    let isPaying: Bool
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
                        .disabled(!canPay || isPaying)
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
// "Nómina del {fecha}", "Cubre {rango}", "{fromPayroll} de tu nómina",
// "Pagar ahora {toPay}" / "Apartar {toSetAside}" y lista compacta de
// ítems (nombre + share). La tarjeta "Esta quincena" es oscura.

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

    var body: some View {
        Group {
            if let plan {
                NavigationLink {
                    QuincenaScreen(windowIndex: windowIndex)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(isCurrent ? "Esta quincena" : "Siguiente quincena")
                                .font(.caption.bold())
                                .foregroundStyle(isCurrent ? .white.opacity(0.7) : .secondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(isCurrent ? .white.opacity(0.7) : .secondary)
                        }
                        Text("Nómina del \(Format.date(plan.window.start))")
                            .font(.headline)
                        Text("Cubre \(Format.date(plan.window.start)) – \(Format.date(plan.window.end))")
                            .font(.subheadline)
                            .foregroundStyle(isCurrent ? .white.opacity(0.8) : .secondary)
                        Text("\(Format.money(plan.fromPayroll, currency: currency)) de tu nómina")
                            .font(.subheadline)
                        if plan.toPay > 0 {
                            Text("Pagar ahora \(Format.money(plan.toPay, currency: currency))")
                                .font(.subheadline.bold())
                        }
                        if plan.toSetAside > 0 {
                            Text("Apartar \(Format.money(plan.toSetAside, currency: currency))")
                                .font(.subheadline)
                        }
                        if !plan.items.isEmpty {
                            Divider()
                            ForEach(plan.items) { item in
                                HStack {
                                    Text(item.payment.name)
                                    Spacer()
                                    Text(Format.money(item.share, currency: currency))
                                }
                                .font(.subheadline)
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
}
