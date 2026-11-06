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
    @State private var showingPayroll = false
    @State private var hapticTrigger = 0

    @Environment(\.scenePhase) private var scenePhase

    /// Fase del saludo del encabezado, como `greetingPhase` de la web.
    private enum GreetingPhase { case pending, playing, done }
    @State private var greetingPhase: GreetingPhase = .pending
    @State private var greetingOpacity = 0.0
    @State private var greetingOffset = 0.0
    @State private var nameOpacity = 0.0
    @State private var nameOffset = 8.0
    @State private var logoOpacity = 0.0
    @State private var logoOffset = 8.0
    @State private var backgroundedAt: Date?
    @State private var greetingTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    brandHeader

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

                    // Aviso ámbar "Por pagar" (WEB-INVENTORY §1): una línea
                    // por ítem, "En 2 días · Pago semanal · $216.00".
                    if !upcomingReminders.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Por pagar")
                                .font(.headline)
                            ForEach(Array(upcomingReminders.prefix(3))) { item in
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundStyle(.orange)
                                    Text("\(relativeDay(item.date)) · \(item.name) · \(Format.money(item.amount, currency: currency))")
                                        .font(.subheadline)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding()
                        .background(Color.orange.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    }

                    // "Para estar al día": esta quincena y la siguiente.
                    HStack {
                        Text("Para estar al día")
                            .font(.headline)
                        Spacer()
                        Button("Nómina") { showingPayroll = true }
                            .font(.subheadline)
                    }
                    .padding(.horizontal)
                    VStack(spacing: 12) {
                        QuincenaCard(windowIndex: quincenaContext.currentIndex, context: quincenaContext)
                        if quincenaContext.windows.indices.contains(quincenaContext.currentIndex + 1) {
                            QuincenaCard(windowIndex: quincenaContext.currentIndex + 1, context: quincenaContext)
                        }
                    }
                    .padding(.horizontal)

                    // Próximos pagos (los primeros 5, como la web):
                    // flecha ↗ ("!" si vencido), nombre, cuenta, fecha
                    // ("En 2 días · 8 nov 2026"), monto y botón "Pagar".
                    Text("Próximos pagos")
                        .font(.headline)
                        .padding(.horizontal)
                    if store.scheduledPayments.isEmpty {
                        Text("No tienes pagos programados.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(store.scheduledPayments.prefix(5))) { payment in
                                let accountName = store.accounts.first { $0.id == payment.accountId }?.name ?? "Cuenta"
                                let overdue = (payment.nextPayment ?? .distantFuture) < Date()
                                HStack(spacing: 12) {
                                    Text(overdue ? "!" : "↗")
                                        .font(.headline)
                                        .foregroundStyle(overdue ? .red : .secondary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(payment.name)
                                            .lineLimit(1)
                                        Text(accountName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(upcomingDateText(payment.nextPayment))
                                            .font(.caption)
                                            .foregroundStyle(overdue ? .red : .secondary)
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
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { startGreeting() }
            .onChange(of: store.profile?.name) { _, _ in startGreeting() }
            .onChange(of: store.profileLoaded) { _, _ in startGreeting() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    backgroundedAt = Date()
                } else if phase == .active {
                    defer { backgroundedAt = nil }
                    guard let hiddenAt = backgroundedAt,
                          Date().timeIntervalSince(hiddenAt) >= 25 else { return }
                    replayGreeting()
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
            .sheet(item: $paymentToPay) { payment in
                MarkPaymentSheet(payment: payment)
            }
            .sheet(isPresented: $showingPayroll) {
                PayrollSheet()
            }
            .sensoryFeedback(.impact, trigger: hapticTrigger)
        }
    }

    /// Encabezado de Inicio (MAP.md §21 / web `.brand-mark`): fila propia
    /// dentro del contenido, no barra de navegación. A la izquierda el
    /// saludo o el logo DESNUDO, directo sobre el fondo, sin cápsula ni
    /// burbuja (en la 1.2.2 el logo quedó en un ToolbarItem y en iOS 26
    /// eso se ve dentro de una burbuja de Liquid Glass); a la derecha los
    /// botones circulares de buscar y ajustes. La fila mide 44pt fijos
    /// para que el cambio de saludo a logo no mueva el contenido.
    private var brandHeader: some View {
        HStack {
            ZStack(alignment: .leading) {
                Image("CalculaWordmark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 28)
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Calcula")
                    .opacity(logoOpacity)
                    .offset(y: logoOffset)
                VStack(alignment: .leading, spacing: 2) {
                    Text(greetingPhrase())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(firstName ?? "")
                        .font(.system(size: 18, weight: .bold))
                        .opacity(nameOpacity)
                        .offset(y: nameOffset)
                }
                .opacity(greetingOpacity)
                .offset(y: greetingOffset)
            }
            .frame(height: 44, alignment: .leading)
            Spacer()
            Button { showingSearch = true } label: {
                Image(systemName: "magnifyingglass")
                    .frame(width: 40, height: 40)
                    .background(Color(.secondarySystemFill))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 40, height: 40)
                    .background(Color(.secondarySystemFill))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// Frase del saludo según la hora, como `greetingPhrase` de la web:
    /// 5–12 "Buenos días", 12–19 "Buenas tardes", resto "Buenas noches".
    private func greetingPhrase() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 5 && hour < 12 { return "Buenos días" }
        if hour >= 12 && hour < 19 { return "Buenas tardes" }
        return "Buenas noches"
    }

    /// Primer nombre del perfil para saludar, como `firstName` de la web.
    /// nil si no hay nombre (entonces se muestra el logo directo).
    private var firstName: String? {
        let name = (store.profile?.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.split(separator: " ").first.map(String.init)
    }

    /// Arranca el saludo del encabezado, como `startGreeting` de la web.
    /// Solo se reproduce una vez por sesión en primer plano: si no hay
    /// nombre y el perfil ya cargó, queda el logo directo; si el perfil
    /// aún no cargó, no hace nada y se reintenta cuando cargue.
    private func startGreeting() {
        guard greetingPhase == .pending else { return }
        guard firstName?.isEmpty == false else {
            if store.profileLoaded {
                greetingPhase = .done
                logoOpacity = 1
                logoOffset = 0
            }
            return
        }
        greetingPhase = .playing
        greetingOpacity = 1
        greetingOffset = 0
        nameOpacity = 0
        nameOffset = 8
        logoOpacity = 0
        logoOffset = 8
        // Entrada del nombre, como `.brand-hello strong` de la web
        // (helloIn .5s ease .12s): la frase aparece directa.
        withAnimation(.easeOut(duration: 0.5).delay(0.12)) {
            nameOpacity = 1
            nameOffset = 0
        }
        greetingTask?.cancel()
        greetingTask = Task {
            // A los 2400 ms el saludo empieza a desvanecerse (helloOut .4s).
            try? await Task.sleep(for: .milliseconds(2400))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) {
                greetingOpacity = 0
                greetingOffset = -7
            }
            // 380 ms después aparece el logo con su entrada (brand-in .48s).
            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled else { return }
            greetingPhase = .done
            withAnimation(.easeIn(duration: 0.48)) {
                logoOpacity = 1
                logoOffset = 0
            }
        }
    }

    /// Vuelve a reproducir el saludo, como `replayGreeting` de la web.
    private func replayGreeting() {
        guard firstName?.isEmpty == false else { return }
        greetingTask?.cancel()
        greetingPhase = .pending
        startGreeting()
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

    /// "Hoy" / "Mañana" / "En N días" / "Vencido ayer" / "Vencido hace N
    /// días" o fecha corta, como `dateDescription` de la web.
    private func relativeDay(_ date: Date) -> String {
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

    /// "En 2 días · 8 nov 2026" / "15 nov · 15 nov 2026", como
    /// `dateDescription` + `formatDate` de la web.
    private func upcomingDateText(_ date: Date?) -> String {
        guard let date else { return "" }
        return "\(relativeDay(date)) · \(Format.date(date))"
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

// MARK: - Hoja "Marcar pago" (WEB-INVENTORY §3)
// Desde "Pagar" en Próximos pagos, "Registrar pago" en detalle de cuenta
// y "Pagar" en detalle de quincena: monto, "Programado para…",
// "Cancelar" y "Marcar como pagado" (registra el pago de verdad:
// movimiento type "pago" + avanza nextPayment, igual que la web).
struct MarkPaymentSheet: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let payment: ScheduledPayment
    /// "Pago 1 de 3" cuando hay varias ocurrencias vencidas (detalle de
    /// quincena); si no, la frecuencia ("Cada semana").
    var occurrenceText: String? = nil

    @State private var isSaving = false
    @State private var errorMessage: String?

    private var currency: String { store.profile?.currency ?? "MXN" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Marcar pago")
                .font(.title2.bold())
            Text("\(payment.name) · \(occurrenceText ?? QuincenaEngine.frequencyLabel(payment.frequency))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Monto")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Format.money(payment.amount, currency: currency))
                    .font(.system(size: 29, weight: .bold))
                Text("Programado para \(Format.date(payment.nextPayment))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 18))

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Cancelar") { dismiss() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                Button("Marcar como pagado") {
                    Task { await markPaid() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.calculaAccent)
                .frame(maxWidth: .infinity)
                .disabled(isSaving)
            }
        }
        .padding()
        .presentationDetents([.medium])
    }

    private func markPaid() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.payScheduled(payment)
            dismiss()
        } catch {
            errorMessage = "No se pudo registrar el pago"
        }
    }
}
