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
    @State private var showingSearch = false
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
                                    AccountCard(
                                        account: account,
                                        payment: store.scheduledPayments.first {
                                            $0.accountId == account.id
                                        },
                                        currentPlan: currentQuincenaPlan,
                                        nextPlan: nextQuincenaPlan,
                                        currency: currency
                                    )
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

                    RecentMovementsSection(
                        movements: recentMovements,
                        accounts: store.accounts,
                        currency: currency,
                        onViewAccount: { movement in
                            selectedAccount = store.accounts.first {
                                $0.id == movement.accountId
                            }
                        },
                        onDelete: { movement in movementToDelete = movement }
                    )
                }
                .padding(.vertical)
            }
            .background(Color.calculaBackground)
            .navigationTitle("Inicio")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSearch) {
                SearchView()
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

    /// Últimos 10 movimientos (igual que la web).
    private var recentMovements: [Movement] {
        Array(store.movements.prefix(10))
    }

    /// Contexto de quincenas con la nómina configurada.
    private var quincenaContext: QuincenaContext {
        QuincenaEngine.currentAndNext(settings: store.payroll)
    }

    /// Plan de la quincena actual (para el estado de las tarjetas de
    /// cuenta, como `summarizeAccountItems` de la web).
    private var currentQuincenaPlan: QuincenaPlan? {
        guard quincenaContext.windows.indices.contains(quincenaContext.currentIndex) else { return nil }
        return QuincenaEngine.buildQuincenaPlan(
            windowIndex: quincenaContext.currentIndex,
            context: quincenaContext,
            payments: store.scheduledPayments,
            accounts: store.accounts
        )
    }

    /// Plan de la quincena siguiente (mismo uso que el actual).
    private var nextQuincenaPlan: QuincenaPlan? {
        guard quincenaContext.windows.indices.contains(quincenaContext.currentIndex + 1) else { return nil }
        return QuincenaEngine.buildQuincenaPlan(
            windowIndex: quincenaContext.currentIndex + 1,
            context: quincenaContext,
            payments: store.scheduledPayments,
            accounts: store.accounts
        )
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

/// Lista de movimientos recientes en Inicio (extraída del body para que el
/// compilador verifique el tipo en tiempo razonable; mismo aspecto y
/// comportamiento: fila con menú "Ver cuenta"/"Eliminar" y separador
/// entre filas).
private struct RecentMovementsSection: View {
    let movements: [Movement]
    let accounts: [Account]
    let currency: String
    let onViewAccount: (Movement) -> Void
    let onDelete: (Movement) -> Void

    var body: some View {
        Group {
            Text("Movimientos recientes")
                .font(.headline)
                .padding(.horizontal)

            if movements.isEmpty {
                Text("Aún no hay movimientos.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(movements) { movement in
                        MovementRow(
                            movement: movement,
                            accountName: accountName(for: movement.accountId),
                            currency: currency
                        )
                        .contextMenu {
                            Button("Ver cuenta") {
                                onViewAccount(movement)
                            }
                            Button("Eliminar", role: .destructive) {
                                onDelete(movement)
                            }
                        }
                        if movement.id != movements.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color.calculaCard)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
            }
        }
    }

    private func accountName(for id: String) -> String {
        accounts.first { $0.id == id }?.name ?? "Cuenta"
    }
}

/// Resumen de los ítems de quincena de una cuenta, como
/// `summarizeAccountItems` de la web (MAP.md §4.3).
private struct AccountPlanSummary {
    var dueCount: Int = 0
    var amount: Double = 0
    var share: Double = 0
    var isDue: Bool = false
    var overdue: Bool = false
    var due: Date? = nil
    var unitAmount: Double = 0
}

/// Tarjeta de cuenta (color guardado en `cardColor`, como la web).
/// Mismo contenido que el carrusel de la web (`renderCarousel`):
/// nombre, tipo ("Subscripción" / "Pago recurrente" / "Cargos y abonos"),
/// etiqueta ("Próximo pago" / "Saldo pendiente" / "Esta quincena"),
/// cantidad grande, estado (frecuencia · fecha, "Apartar $X esta
/// quincena", "Pagar el día X · esta quincena", "Cuenta liquidada"…)
/// y el aviso "Toca para ver movimientos". Presentación nativa de iOS.
struct AccountCard: View {
    let account: Account
    let payment: ScheduledPayment?
    let currentPlan: QuincenaPlan?
    let nextPlan: QuincenaPlan?
    var currency: String = "MXN"

    private var isSubscription: Bool {
        account.isSubscription
            || payment?.isSubscription == true
            || payment?.kind == "subscription"
    }

    private var typeLabel: String {
        if isSubscription { return "Subscripción" }
        if account.isRecurring { return "Pago recurrente" }
        return "Cargos y abonos"
    }

    private func summary(in plan: QuincenaPlan?) -> AccountPlanSummary? {
        guard let plan else { return nil }
        let mine = plan.items.filter { $0.account.id == account.id }
        guard !mine.isEmpty else { return nil }
        let dues = mine.filter(\.isDue)
        let base = dues.first ?? mine[0]
        return AccountPlanSummary(
            dueCount: dues.count,
            amount: dues.map(\.amount).reduce(0, +),
            share: mine.map(\.share).reduce(0, +),
            isDue: !dues.isEmpty,
            overdue: mine.contains(where: \.overdue),
            due: base.due,
            unitAmount: base.unitAmount
        )
    }

    /// "1 pago de $X" / "N pagos de $X", como `paymentsLabel` de la web.
    private func paymentsLabel(count: Int, unitAmount: Double) -> String {
        count <= 1
            ? "1 pago de \(Format.money(unitAmount, currency: currency))"
            : "\(count) pagos de \(Format.money(unitAmount, currency: currency))"
    }

    /// "Hoy" / "Mañana" / "En N días" / "Vencido…" o fecha corta,
    /// como `dateDescription` de la web.
    private func dueDescription(_ date: Date) -> String {
        let days = Calendar.current.dateComponents(
            [.day],
            from: QuincenaEngine.startOfDay(Date()),
            to: QuincenaEngine.startOfDay(date)
        ).day ?? 0
        switch days {
        case ..<(-1): return "Vencido hace \(-days) días"
        case -1: return "Vencido ayer"
        case 0: return "Hoy"
        case 1: return "Mañana"
        case 2..<7: return "En \(days) días"
        default: return Format.shortDate(date)
        }
    }

    /// Etiqueta, cantidad y estado, con la misma lógica que
    /// `renderCarousel` de la web.
    private var cardContent: (label: String, amount: Double, status: String) {
        let current = summary(in: currentPlan)
        let next = summary(in: nextPlan)
        if account.isRecurring {
            if let current, current.dueCount > 1 {
                return (
                    "Esta quincena",
                    current.amount,
                    paymentsLabel(count: current.dueCount, unitAmount: current.unitAmount)
                )
            }
            let amount = payment?.amount ?? 0
            if let current, current.isDue, let due = current.due {
                let frequency = QuincenaEngine.frequencyLabel(payment?.frequency ?? "monthly")
                return ("Próximo pago", amount, "\(frequency) · \(dueDescription(due))")
            }
            if let current, !current.isDue {
                return (
                    "Próximo pago",
                    amount,
                    "Apartar \(Format.money(current.share, currency: currency)) esta quincena"
                )
            }
            if let next, next.dueCount > 1 {
                return (
                    "Próximo pago",
                    amount,
                    "Siguiente quincena: \(paymentsLabel(count: next.dueCount, unitAmount: next.unitAmount))"
                )
            }
            if let payment, let nextDate = payment.nextPayment {
                let frequency = QuincenaEngine.frequencyLabel(payment.frequency)
                return ("Próximo pago", amount, "\(frequency) · \(dueDescription(nextDate))")
            }
            return ("Próximo pago", amount, "Sin pago programado")
        }
        let status: String
        if account.dueDay > 0 {
            if account.balance > 0 {
                if let current {
                    status = "Pagar el día \(account.dueDay) · \(current.overdue ? "vencido" : "esta quincena")"
                } else if next != nil {
                    status = "Pagar el día \(account.dueDay) · siguiente quincena"
                } else {
                    status = "Pagar el día \(account.dueDay)"
                }
            } else if account.balance < 0 {
                status = "Tienes saldo a favor"
            } else {
                status = "Pagar el día \(account.dueDay) · cuenta liquidada"
            }
        } else if account.balance > 0 {
            status = "Tienes un saldo pendiente"
        } else if account.balance < 0 {
            status = "Tienes saldo a favor"
        } else {
            status = "Cuenta liquidada"
        }
        return ("Saldo pendiente", account.balance, status)
    }

    var body: some View {
        let content = cardContent
        VStack(alignment: .leading, spacing: 0) {
            Text(account.name)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(typeLabel)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 4)
            Spacer()
            Text(content.label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Text(Format.money(content.amount, currency: currency))
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 2)
            Text(content.status)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .padding(.top, 6)
            Text("Toca para ver movimientos")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 12)
        }
        .frame(width: 280, height: 210, alignment: .leading)
        .padding(20)
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
