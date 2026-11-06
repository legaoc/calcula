import SwiftUI

/// Inicio: total, tarjetas de cuentas y movimientos recientes.
/// El menú al mantener presionado es el `contextMenu` nativo de SwiftUI
/// (en iOS 26 se presenta con Liquid Glass, como el UIMenu de la web).
struct HomeView: View {
    @EnvironmentObject private var store: DataStore
    @State private var selectedAccount: Account?
    @State private var movementToDelete: Movement?
    @State private var paymentToPay: ScheduledPayment?
    @State private var showingAccounts = false
    @State private var hapticTrigger = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total pendiente")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(Format.money(store.totalBalance, currency: currency))
                            .font(.system(size: 34, weight: .bold))
                        Text("\(store.accounts.count) cuentas")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    HStack {
                        Text("Cuentas")
                            .font(.headline)
                        Spacer()
                        Button("Ver todas") { showingAccounts = true }
                            .font(.subheadline)
                    }
                    .padding(.horizontal)

                    if store.visibleAccounts.isEmpty {
                        Text("Aún no tienes cuentas. Crea una para empezar.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(store.visibleAccounts) { account in
                                    AccountCard(account: account, currency: currency)
                                        .onTapGesture { selectedAccount = account }
                                        .contextMenu {
                                            Button("Ver movimientos") {
                                                selectedAccount = account
                                            }
                                            Button("Eliminar cuenta", role: .destructive) {
                                                Task {
                                                    try? await store.deleteAccount(account)
                                                }
                                            }
                                        }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Banner de recordatorios ("Por pagar", MAP.md §4.10).
                    if !upcomingReminders.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Por pagar")
                                .font(.headline)
                            ForEach(Array(upcomingReminders.prefix(3))) { item in
                                DueReminderRow(
                                    title: item.name,
                                    detail: "\(relativeDay(item.date)) · \(Format.money(item.amount, currency: currency))"
                                )
                            }
                        }
                        .padding()
                        .background(Color.calculaCard)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    }

                    // "Para estar al día": esta quincena y la siguiente.
                    Text("Para estar al día")
                        .font(.headline)
                        .padding(.horizontal)
                    VStack(spacing: 12) {
                        QuincenaCard(windowIndex: quincenaContext.currentIndex, context: quincenaContext)
                        if quincenaContext.windows.indices.contains(quincenaContext.currentIndex + 1) {
                            QuincenaCard(windowIndex: quincenaContext.currentIndex + 1, context: quincenaContext)
                        }
                    }
                    .padding(.horizontal)

                    // Próximos pagos (los primeros 5, como la web).
                    if !store.scheduledPayments.isEmpty {
                        Text("Próximos pagos")
                            .font(.headline)
                            .padding(.horizontal)
                        LazyVStack(spacing: 0) {
                            ForEach(Array(store.scheduledPayments.prefix(5))) { payment in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(payment.name)
                                            .lineLimit(1)
                                        Text(Format.date(payment.nextPayment))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(Format.money(payment.amount, currency: currency))
                                        .fontWeight(.semibold)
                                    Button("Pagar") { paymentToPay = payment }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            }
                        }
                        .background(Color.calculaCard)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    }

                    Text("Movimientos recientes")
                        .font(.headline)
                        .padding(.horizontal)

                    if store.movements.isEmpty {
                        Text("Aún no hay movimientos.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(recentMovements) { movement in
                                MovementRow(
                                    movement: movement,
                                    accountName: accountName(for: movement.accountId),
                                    currency: currency
                                )
                                .contextMenu {
                                    Button("Ver cuenta") {
                                        selectedAccount = store.accounts.first {
                                            $0.id == movement.accountId
                                        }
                                    }
                                    Button("Eliminar", role: .destructive) {
                                        movementToDelete = movement
                                    }
                                }
                                if movement.id != recentMovements.last?.id {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                        .background(Color.calculaCard)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .background(Color.calculaBackground)
            .navigationTitle("Inicio")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationDestination(item: $selectedAccount) { account in
                AccountDetailView(account: account)
            }
            .navigationDestination(isPresented: $showingAccounts) {
                AccountsView()
            }
            .alert(
                "Eliminar movimiento",
                isPresented: Binding(
                    get: { movementToDelete != nil },
                    set: { if !$0 { movementToDelete = nil } }
                )
            ) {
                Button("Eliminar", role: .destructive) {
                    Task { await deleteSelectedMovement() }
                }
                Button("Cancelar", role: .cancel) { movementToDelete = nil }
            } message: {
                Text("Esta acción no se puede deshacer. El saldo de la cuenta se ajustará.")
            }
            .alert(
                "Pagar",
                isPresented: Binding(
                    get: { paymentToPay != nil },
                    set: { if !$0 { paymentToPay = nil } }
                )
            ) {
                Button("Pagar") {
                    Task {
                        if let payment = paymentToPay {
                            try? await store.payScheduled(payment)
                            hapticTrigger += 1
                        }
                        paymentToPay = nil
                    }
                }
                Button("Cancelar", role: .cancel) { paymentToPay = nil }
            } message: {
                Text("Se registrará el pago y avanzará la próxima fecha de cobro.")
            }
            .sensoryFeedback(.impact, trigger: hapticTrigger)
        }
    }

    private func accountName(for id: String) -> String {
        store.accounts.first { $0.id == id }?.name ?? "Cuenta"
    }

    /// Últimos 10 movimientos (igual que la web).
    private var recentMovements: [Movement] {
        Array(store.movements.prefix(10))
    }

    /// Contexto de quincenas con la nómina configurada.
    private var quincenaContext: QuincenaContext {
        QuincenaEngine.currentAndNext(settings: store.payroll)
    }

    /// Ítems de `upcomingReminderItems` (MAP.md §4.10): pagos programados
    /// y cargos con vencimiento dentro de la ventana `daysBefore`.
    private var upcomingReminders: [ReminderItem] {
        guard store.reminderSettings.enabled else { return [] }
        let daysBefore = store.reminderSettings.daysBefore
        let today = QuincenaEngine.startOfDay(Date())
        var items: [ReminderItem] = []
        for payment in store.scheduledPayments {
            guard let next = payment.nextPayment else { continue }
            let days = Calendar.current.dateComponents(
                [.day], from: today, to: QuincenaEngine.startOfDay(next)
            ).day ?? 0
            if days >= 0 && days <= daysBefore {
                items.append(ReminderItem(
                    id: "pay-\(payment.id ?? "")",
                    name: payment.name, date: next, amount: payment.amount
                ))
            }
        }
        for account in store.accounts where account.type == "charges"
            && account.balance > 0 && account.dueDay > 0 {
            guard let due = QuincenaEngine.upcomingChargeDue(
                dueDay: account.dueDay, fromDate: Date()
            ) else { continue }
            let days = Calendar.current.dateComponents(
                [.day], from: today, to: QuincenaEngine.startOfDay(due)
            ).day ?? 0
            if days >= 0 && days <= daysBefore {
                items.append(ReminderItem(
                    id: "charge-\(account.id ?? "")",
                    name: account.name, date: due, amount: account.balance
                ))
            }
        }
        return items.sorted { $0.date < $1.date }
    }

    private func relativeDay(_ date: Date) -> String {
        let days = Calendar.current.dateComponents(
            [.day],
            from: QuincenaEngine.startOfDay(Date()),
            to: QuincenaEngine.startOfDay(date)
        ).day ?? 0
        switch days {
        case 0: return "Hoy"
        case 1: return "Mañana"
        case ..<0: return "Vencido"
        default: return "En \(days) días"
        }
    }

    /// Moneda global del perfil (MXN por defecto, como la web).
    private var currency: String {
        store.profile?.currency ?? "MXN"
    }

    private func deleteSelectedMovement() async {
        guard let movement = movementToDelete else { return }
        do {
            try await store.deleteMovement(movement)
            hapticTrigger += 1
        } catch {
            // El listener seguirá mostrando el movimiento; la app no se
            // bloquea por un fallo de red.
        }
        movementToDelete = nil
    }
}

/// Ítem del banner "Por pagar" en Inicio.
private struct ReminderItem: Identifiable {
    var id: String
    var name: String
    var date: Date
    var amount: Double
}

/// Fila del banner "Por pagar" (extraída del body de Inicio para que el
/// compilador verifique el tipo en tiempo razonable).
private struct DueReminderRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Text(title)
                .lineLimit(1)
            Spacer()
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// Tarjeta de cuenta (color guardado en `cardColor`, como la web).
struct AccountCard: View {
    let account: Account
    var currency: String = "MXN"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(account.name)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(account.isRecurring ? "Recurrente" : "Cargos")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(Format.money(account.balance, currency: currency))
                .font(.title3.bold())
                .foregroundStyle(.white)
        }
        .frame(width: 180, height: 120, alignment: .leading)
        .padding()
        .background(Color(hex: account.cardColor ?? "111111"))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

/// Fila de movimiento: nota, cuenta, fecha y monto con signo del delta.
struct MovementRow: View {
    let movement: Movement
    let accountName: String
    var currency: String = "MXN"

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: movement.isCharge ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .foregroundStyle(movement.isCharge ? .red : .green)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(movement.note.isEmpty ? accountName : movement.note)
                    .lineLimit(1)
                Text("\(accountName) · \(Format.date(movement.createdAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text((movement.balanceDelta >= 0 ? "+" : "−") + Format.money(abs(movement.amount), currency: currency))
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
