import SwiftUI

/// Ajustes (mismas secciones que la web, MAP.md §3.7).
/// "Nuevo presupuesto" y "Nueva meta" no viven aquí: solo se indica que
/// están disponibles en Finanzas. "Acceso para Atajos" no se implementa
/// (dato sensible; ver MAP.md §2).
struct SettingsView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var lock: BiometricLock
    @StateObject private var notifications = NotificationService()

    /// Misma clave que la web (`calcula-dark`).
    @AppStorage("calcula-dark") private var darkMode = false

    @State private var showingAddAccount = false
    @State private var showingProfile = false
    @State private var showingSignOutConfirm = false
    @State private var syncing = false
    @State private var monthCSVURL: URL?
    @State private var quincenaCSVURL: URL?
    @State private var calendarURL: URL?

    var body: some View {
        Form {
            accountsSection
            moneySection
            appearanceSection
            remindersSection
            exportSection
            syncSection
            securitySection
            historySection
            systemSection

            Section {
                Text(AppVersion.display)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("App 100% nativa en SwiftUI")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Ajustes")
        .preferredColorScheme(darkMode ? .dark : .light)
        .sheet(isPresented: $showingAddAccount) {
            AddAccountView()
        }
        .sheet(isPresented: $showingProfile) {
            ProfileEditView(profile: store.profile)
        }
        .task {
            await notifications.refreshAuthorizationStatus()
        }
        .onChange(of: notifications.remindersEnabled) { _, _ in
            Task {
                if let uid = auth.user?.uid {
                    await notifications.rescheduleAll(uid: uid)
                }
            }
        }
        .alert("Cerrar sesión", isPresented: $showingSignOutConfirm) {
            Button("Cerrar sesión", role: .destructive) {
                auth.signOut()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Tendrás que volver a entrar con tu correo y contraseña.")
        }
    }

    // MARK: - Cuentas

    private var accountsSection: some View {
        Section("Cuentas") {
            Button("Nueva cuenta") {
                showingAddAccount = true
            }

            if store.accounts.isEmpty {
                Text("Aún no tienes cuentas.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Tarjetas del inicio")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(store.accounts) { account in
                    Toggle(isOn: hiddenBinding(for: account)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                            Text(account.isRecurring ? "Recurrente" : "Cargos")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                NavigationLink("Orden de tarjetas") {
                    ReorderAccountsView()
                }
            }
        }
    }

    private func hiddenBinding(for account: Account) -> Binding<Bool> {
        Binding(
            get: {
                store.accounts.first { $0.id == account.id }?.hiddenFromHome
                    ?? account.hiddenFromHome
            },
            set: { hidden in
                Task {
                    try? await store.setAccountHidden(account, hidden: hidden)
                }
            }
        )
    }

    // MARK: - Dinero

    private var moneySection: some View {
        Section("Dinero") {
            Button("Mi perfil") {
                showingProfile = true
            }
            HStack {
                Text("Nuevo presupuesto")
                Spacer()
                Text("Disponible en Finanzas")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Nueva meta")
                Spacer()
                Text("Disponible en Finanzas")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Apariencia

    private var appearanceSection: some View {
        Section("Apariencia") {
            Toggle("Modo nocturno", isOn: $darkMode)
        }
    }

    // MARK: - Recordatorios

    private var remindersSection: some View {
        Section("Recordatorios") {
            Toggle("Activar", isOn: Binding(
                get: { store.reminderSettings.enabled },
                set: { enabled in
                    Task {
                        try? await store.setReminderSettings(
                            ReminderSettings(
                                enabled: enabled,
                                daysBefore: store.reminderSettings.daysBefore
                            )
                        )
                    }
                }
            ))

            Picker("Antelación", selection: Binding(
                get: { store.reminderSettings.daysBefore },
                set: { days in
                    Task {
                        try? await store.setReminderSettings(
                            ReminderSettings(
                                enabled: store.reminderSettings.enabled,
                                daysBefore: days
                            )
                        )
                    }
                }
            )) {
                Text("1 día").tag(1)
                Text("2 días").tag(2)
            }
            .pickerStyle(.segmented)

            Toggle("Avisos fuera de la app", isOn: $notifications.remindersEnabled)
            Text("Avisa a las 9:00 del día en que toca un pago programado.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Agregar a Calendario") {
                calendarURL = Self.buildCalendarFile(
                    payments: store.scheduledPayments,
                    accounts: store.accounts,
                    daysBefore: store.reminderSettings.daysBefore
                )
            }
            if let calendarURL {
                ShareLink(item: calendarURL, preview: SharePreview("calcula-pagos.ics")) {
                    Label("Compartir calendario (.ics)", systemImage: "square.and.arrow.up")
                }
            }
            Text("Genera un archivo con los pagos programados de los próximos 6 meses para tu calendario.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Exportar

    private var exportSection: some View {
        Section("Exportar") {
            Button("CSV mes") {
                monthCSVURL = Self.buildCSVFile(
                    name: "calcula-mes.csv",
                    movements: Self.monthMovements(store.financeMovements),
                    accounts: store.accounts
                )
            }
            if let monthCSVURL {
                ShareLink(item: monthCSVURL, preview: SharePreview("calcula-mes.csv")) {
                    Label("Compartir CSV del mes", systemImage: "square.and.arrow.up")
                }
            }

            Button("CSV quincena") {
                let context = QuincenaEngine.currentAndNext(
                    now: Date(), settings: store.payroll
                )
                quincenaCSVURL = Self.buildCSVFile(
                    name: "calcula-quincena.csv",
                    movements: Self.quincenaMovements(
                        store.financeMovements, window: context.current
                    ),
                    accounts: store.accounts
                )
            }
            if let quincenaCSVURL {
                ShareLink(item: quincenaCSVURL, preview: SharePreview("calcula-quincena.csv")) {
                    Label("Compartir CSV de la quincena", systemImage: "square.and.arrow.up")
                }
            }
            Text("Columnas: Fecha, Cuenta, Tipo, Monto, Nota, Categoría.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Sincronización

    private var syncSection: some View {
        Section("Sincronización") {
            HStack {
                Text("Estado")
                Spacer()
                Text(store.isListening ? "Conectado" : "Sin conexión")
                    .foregroundStyle(store.isListening ? .green : .secondary)
            }
            HStack {
                Text("Sincronizado")
                Spacer()
                Text(store.syncInSync ? "Al día" : "Pendiente")
                    .foregroundStyle(store.syncInSync ? .green : .secondary)
            }
            HStack {
                Text("Última sincronización")
                Spacer()
                Text(lastSyncText)
                    .foregroundStyle(.secondary)
            }
            Toggle("Sincronizar con la nube", isOn: Binding(
                get: { store.cloudSyncEnabled },
                set: { store.setCloudSync(enabled: $0) }
            ))
            Button(syncing ? "Sincronizando…" : "Sincronizar ahora") {
                Task {
                    syncing = true
                    await store.syncNow()
                    syncing = false
                }
            }
            .disabled(syncing)
            if let error = store.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var lastSyncText: String {
        guard let lastSyncAt = store.lastSyncAt else { return "Nunca" }
        return Self.syncDateFormatter.string(from: lastSyncAt)
    }

    private static let syncDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Seguridad

    private var securitySection: some View {
        Section("Seguridad") {
            // Igual que la web: al activar, primero se verifica la
            // identidad; solo si pasa se guarda el ajuste.
            Toggle("Bloquear con Face ID", isOn: Binding(
                get: { lock.faceIDEnabled },
                set: { newValue in
                    if newValue {
                        Task {
                            if await lock.authenticate() {
                                lock.faceIDEnabled = true
                            }
                        }
                    } else {
                        lock.faceIDEnabled = false
                    }
                }
            ))
            if !lock.biometricsAvailable {
                Text("Este dispositivo no tiene Face ID o Touch ID configurado.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Historial y sistema

    private var historySection: some View {
        Section("Historial de versiones") {
            NavigationLink {
                VersionHistoryView()
            } label: {
                HStack {
                    Text("Historial de versiones")
                    Spacer()
                    Text(AppVersion.short)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var systemSection: some View {
        Section("Sistema") {
            if let email = auth.user?.email {
                HStack {
                    Text("Correo")
                    Spacer()
                    Text(email)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Actualizar app")
                Text("En esta versión, la app se actualiza desde FlareStore. Cuando haya una versión nueva, aparecerá ahí.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("Cerrar sesión", role: .destructive) {
                showingSignOutConfirm = true
            }
        }
    }

    // MARK: - CSV (MAP.md §4.8: columnas Fecha, Cuenta, Tipo, Monto, Nota, Categoría)

    private static func monthMovements(_ movements: [Movement]) -> [Movement] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: Date()) else {
            return []
        }
        return movements.filter { movement in
            guard let date = movement.createdAt else { return false }
            return date >= interval.start && date < interval.end
        }
    }

    private static func quincenaMovements(
        _ movements: [Movement], window: QuincenaWindow
    ) -> [Movement] {
        movements.filter { movement in
            guard let date = movement.createdAt else { return false }
            return date >= window.start && date < window.end
        }
    }

    private static func buildCSVFile(
        name: String, movements: [Movement], accounts: [Account]
    ) -> URL? {
        var lines = ["Fecha,Cuenta,Tipo,Monto,Nota,Categoría"]
        let sorted = movements.sorted {
            ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }
        for movement in sorted {
            let accountName = accounts.first { $0.id == movement.accountId }?.name ?? ""
            let fields = [
                Format.date(movement.createdAt),
                accountName,
                movement.type,
                String(format: "%.2f", movement.amount),
                movement.note,
                movement.category ?? "",
            ].map(csvEscape)
            lines.append(fields.joined(separator: ","))
        }
        // BOM UTF-8, como la web.
        let text = "\u{FEFF}" + lines.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    // MARK: - Calendario .ics (MAP.md §4.10: 6 meses, alarma daysBefore)

    private static func buildCalendarFile(
        payments: [ScheduledPayment],
        accounts: [Account],
        daysBefore: Int
    ) -> URL? {
        let now = Date()
        guard let sixMonths = Calendar.current.date(
            byAdding: .month, value: 6, to: now
        ) else { return nil }
        var events: [(date: Date, title: String, amount: Double?, uid: String)] = []

        for payment in payments where payment.active {
            for date in QuincenaEngine.occurrenceDates(payment, until: sixMonths) {
                events.append((
                    date: date,
                    title: payment.name,
                    amount: payment.amount,
                    uid: "pago-\(payment.id ?? UUID().uuidString)-\(icsDate(date))"
                ))
            }
        }
        for account in accounts where account.type == "charges" {
            guard account.balance > 0, account.dueDay >= 1,
                  var due = QuincenaEngine.upcomingChargeDue(
                    dueDay: account.dueDay, fromDate: now
                  )
            else { continue }
            for _ in 0..<8 {
                events.append((
                    date: due,
                    title: "Pagar \(account.name)",
                    amount: account.balance,
                    uid: "cargo-\(account.id ?? UUID().uuidString)-\(icsDate(due))"
                ))
                due = QuincenaEngine.addingMonths(due, 1)
            }
        }

        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Calcula//STUDI05//ES",
            "CALSCALE:GREGORIAN",
        ]
        for event in events.sorted(by: { $0.date < $1.date }) {
            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(event.uid)@calcula")
            lines.append("DTSTAMP:\(icsTimestamp(now))")
            lines.append("DTSTART;VALUE=DATE:\(icsDate(event.date))")
            lines.append("SUMMARY:\(icsEscape(event.title))")
            if let amount = event.amount {
                lines.append("DESCRIPTION:\(icsEscape(Format.money(amount)))")
            }
            lines.append("BEGIN:VALARM")
            lines.append("TRIGGER:-P\(max(1, daysBefore))D")
            lines.append("ACTION:DISPLAY")
            lines.append("DESCRIPTION:\(icsEscape(event.title))")
            lines.append("END:VALARM")
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("calcula-pagos.ics")
        do {
            try lines.joined(separator: "\r\n").write(
                to: url, atomically: true, encoding: .utf8
            )
            return url
        } catch {
            return nil
        }
    }

    private static func icsDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    private static func icsTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func icsEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

// MARK: - Editar perfil

private struct ProfileEditView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    private let original: UserProfile?
    @State private var name: String
    @State private var income: String
    @State private var currency: String
    @State private var errorMessage: String?

    init(profile: UserProfile?) {
        self.original = profile
        _name = State(initialValue: profile?.name ?? "")
        _income = State(initialValue: profile?.income ?? "fortnightly")
        _currency = State(initialValue: profile?.currency ?? "MXN")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mi perfil") {
                    TextField("Nombre", text: $name)
                        .textInputAutocapitalization(.words)
                    Picker("Cada cuándo te pagan", selection: $income) {
                        ForEach(ProfileIncomeOption.allCases) { option in
                            Text(option.label).tag(option.rawValue)
                        }
                    }
                    Picker("Moneda", selection: $currency) {
                        Text("Pesos (MXN)").tag("MXN")
                        Text("Dólares (USD)").tag("USD")
                    }
                    .pickerStyle(.segmented)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Mi perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        Task { await save() }
                    }
                }
            }
        }
    }

    private func save() async {
        var profile = original ?? UserProfile()
        profile.name = name.trimmingCharacters(in: .whitespaces)
        profile.income = income
        profile.currency = currency
        do {
            try await store.saveProfile(profile)
            dismiss()
        } catch {
            errorMessage = "No se pudo guardar el perfil"
        }
    }
}

private enum ProfileIncomeOption: String, CaseIterable, Identifiable {
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

// MARK: - Orden de tarjetas

private struct ReorderAccountsView: View {
    @EnvironmentObject private var store: DataStore
    @State private var ordered: [Account] = []

    var body: some View {
        List {
            ForEach(ordered) { account in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name)
                        Text(account.isRecurring ? "Recurrente" : "Cargos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Format.money(
                        account.balance,
                        currency: store.profile?.currency ?? "MXN"
                    ))
                    .foregroundStyle(.secondary)
                }
            }
            .onMove(perform: move)
            Text("Arrastra las tarjetas para cambiar el orden en el inicio.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Orden de tarjetas")
        .toolbar {
            EditButton()
        }
        .task {
            ordered = store.accounts
        }
        .onChange(of: store.accounts) { _, newAccounts in
            ordered = newAccounts
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        ordered.move(fromOffsets: source, toOffset: destination)
        Task {
            try? await store.reorderAccounts(ordered)
        }
    }
}
