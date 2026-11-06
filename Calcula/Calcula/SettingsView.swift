import SwiftUI
import UIKit

/// Ajustes con acordeón de 7 filas (WEB-INVENTORY §11): Cuentas, Dinero,
/// Apariencia, Recordatorios, Exportar, Sistema y Cerrar sesión. Solo una
/// sección expandida a la vez. "Acceso para Atajos" no se implementa
/// (dato sensible; ver MAP.md §2). Sincronización y Face ID viven dentro
/// de Sistema (antes eran secciones propias).
struct SettingsView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var lock: BiometricLock
    @StateObject private var notifications = NotificationService()

    /// Misma clave que la web (`calcula-dark`).
    @AppStorage("calcula-dark") private var darkMode = false

    @State private var expanded: SettingsRow?
    @State private var showingAddAccount = false
    @State private var showingProfile = false
    @State private var showingNewBudget = false
    @State private var showingNewGoal = false
    @State private var showingSignOutConfirm = false
    @State private var syncing = false
    @State private var monthCSVURL: URL?
    @State private var quincenaCSVURL: URL?
    @State private var calendarURL: URL?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(SettingsRow.allCases) { row in
                    accordionRow(row)
                }

                // Pie: historial y versión (fuera del acordeón).
                VStack(alignment: .leading, spacing: 8) {
                    NavigationLink {
                        VersionHistoryView()
                    } label: {
                        HStack {
                            Text("Historial de versiones")
                            Spacer()
                            Text(AppVersion.short)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    Text(AppVersion.display)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("App 100% nativa en SwiftUI")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.calculaCard)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding()
        }
        .background(Color.calculaBackground)
        .navigationTitle("Ajustes")
        .preferredColorScheme(darkMode ? .dark : .light)
        .sheet(isPresented: $showingAddAccount) {
            AddAccountView()
        }
        .sheet(isPresented: $showingProfile) {
            OnboardingView(editing: true)
        }
        .sheet(isPresented: $showingNewBudget) {
            BudgetFormView()
        }
        .sheet(isPresented: $showingNewGoal) {
            GoalFormView()
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

    // MARK: - Acordeón

    private enum SettingsRow: String, CaseIterable, Identifiable {
        case accounts, money, appearance, reminders, export, system, signOut

        var id: String { rawValue }

        var title: String {
            switch self {
            case .accounts: return "Cuentas"
            case .money: return "Dinero"
            case .appearance: return "Apariencia"
            case .reminders: return "Recordatorios"
            case .export: return "Exportar"
            case .system: return "Sistema"
            case .signOut: return "Cerrar sesión"
            }
        }
    }

    private func subtitle(for row: SettingsRow) -> String {
        switch row {
        case .accounts: return "Nueva, orden y visibilidad"
        case .money: return "Perfil, presupuestos y metas"
        case .appearance: return "Modo nocturno"
        case .reminders: return "\(store.reminderSettings.daysBefore) días antes"
        case .export: return "Movimientos en CSV"
        case .system: return "Actualizar, sincronización y seguridad"
        case .signOut: return "Sale de esta cuenta"
        }
    }

    @ViewBuilder
    private func accordionRow(_ row: SettingsRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation {
                    if row == .signOut {
                        showingSignOutConfirm = true
                    } else {
                        expanded = expanded == row ? nil : row
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(.headline)
                            .foregroundStyle(row == .signOut ? .red : .primary)
                        Text(subtitle(for: row))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if row != .signOut {
                        Image(systemName: "chevron.right")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(expanded == row ? 90 : 0))
                    }
                }
                .padding()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded == row {
                Divider().padding(.horizontal)
                content(for: row)
                    .padding()
            }
        }
        .background(Color.calculaCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func content(for row: SettingsRow) -> some View {
        switch row {
        case .accounts: accountsContent
        case .money: moneyContent
        case .appearance: appearanceContent
        case .reminders: remindersContent
        case .export: exportContent
        case .system: systemContent
        case .signOut: EmptyView()
        }
    }

    /// Fila de submenú: título + subtítulo (como las subfilas de la web).
    private func menuRow(title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Cuentas

    private var accountsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { showingAddAccount = true } label: {
                menuRow(title: "Nueva cuenta", subtitle: "Cargos, pago o subscripción")
            }
            NavigationLink { HomeCardsView() } label: {
                HStack {
                    menuRow(title: "Tarjetas del inicio", subtitle: "Cuáles se ven, color e icono")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            NavigationLink { ReorderAccountsView() } label: {
                HStack {
                    menuRow(title: "Orden de tarjetas", subtitle: "Reorganiza las cuentas")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Dinero

    private var moneyContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { showingProfile = true } label: {
                menuRow(title: "Mi perfil", subtitle: "\(incomeLabel) · \(store.profile?.currency ?? "MXN")")
            }
            Button { showingNewBudget = true } label: {
                menuRow(title: "Nuevo presupuesto", subtitle: "Tope del mes por categoría")
            }
            Button { showingNewGoal = true } label: {
                menuRow(title: "Nueva meta", subtitle: "Ahorro a plazo")
            }
        }
    }

    private var incomeLabel: String {
        switch store.profile?.income {
        case "daily": return "Diario"
        case "weekly": return "Semanal"
        case "monthly": return "Mensual"
        default: return "Quincenal"
        }
    }

    // MARK: - Apariencia

    private var appearanceContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $darkMode) {
                menuRow(title: "Modo nocturno", subtitle: "Fondo oscuro para la app")
            }
        }
    }

    // MARK: - Recordatorios

    private var remindersContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: reminderEnabledBinding) {
                menuRow(title: "Activar", subtitle: "Avisar \(store.reminderSettings.daysBefore) días antes")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Antelación")
                    .font(.subheadline.weight(.semibold))
                Picker("Antelación", selection: daysBeforeBinding) {
                    Text("1 día").tag(1)
                    Text("2 días").tag(2)
                }
                .pickerStyle(.segmented)
                Text("1 o 2 días antes del pago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                menuRow(title: "Avisos en la app", subtitle: "Salen dentro de Calcula")
                Spacer()
                if store.reminderSettings.enabled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Toggle(isOn: $notifications.remindersEnabled) {
                menuRow(title: "Avisos fuera de la app", subtitle: "Avisa a las 9:00 del día en que toca un pago")
            }

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

    private var reminderEnabledBinding: Binding<Bool> {
        Binding(
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
        )
    }

    private var daysBeforeBinding: Binding<Int> {
        Binding(
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
        )
    }

    // MARK: - Exportar

    private var exportContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { 
                monthCSVURL = Self.buildCSVFile(
                    name: "calcula-mes.csv",
                    movements: Self.monthMovements(store.financeMovements),
                    accounts: store.accounts
                )
            } label: {
                menuRow(title: "Exportar mes", subtitle: "CSV de movimientos")
            }
            if let monthCSVURL {
                ShareLink(item: monthCSVURL, preview: SharePreview("calcula-mes.csv")) {
                    Label("Compartir CSV del mes", systemImage: "square.and.arrow.up")
                }
            }

            Button {
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
            } label: {
                menuRow(title: "Exportar quincena", subtitle: "CSV de esta quincena")
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

    // MARK: - Sistema (incluye Sincronización y Seguridad, antes secciones propias)

    private var systemContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Actualizar app")
                    .font(.subheadline.weight(.semibold))
                Text("En esta versión, la app se actualiza desde FlareStore. Cuando haya una versión nueva, aparecerá ahí.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Sincronización")
                    .font(.subheadline.weight(.semibold))
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

            if let email = auth.user?.email {
                HStack {
                    Text("Correo")
                    Spacer()
                    Text(email)
                        .foregroundStyle(.secondary)
                }
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

// MARK: - Tarjetas del inicio (Ajustes → Cuentas)
// "Elige cuáles se ven y su color": una fila por cuenta con interruptor
// Visible, tipo y monto, y una cuadrícula de color (como la web).
private struct HomeCardsView: View {
    @EnvironmentObject private var store: DataStore

    var body: some View {
        List {
            ForEach(store.accounts) { account in
                Section {
                    Toggle(isOn: hiddenBinding(for: account)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                            Text(account.isSubscription ? "Subscripción" : account.isRecurring ? "Pago recurrente" : "Cargos y abonos")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(Format.money(account.balance, currency: store.profile?.currency ?? "MXN"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(ThemePalette.swatches) { swatch in
                                let selected = (account.cardColor ?? "").lowercased() == swatch.hex.lowercased()
                                Button {
                                    Task {
                                        try? await store.setAccountColor(account, hex: swatch.hex)
                                    }
                                } label: {
                                    Circle()
                                        .fill(Color(hex: swatch.hex))
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Circle().stroke(
                                                selected ? Color.calculaAccent : Color.primary.opacity(0.15),
                                                lineWidth: selected ? 3 : 1
                                            )
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(swatch.name)
                            }
                            ColorPicker("Color propio", selection: colorBinding(for: account), supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 32, height: 32)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Tarjetas del inicio")
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

    private func colorBinding(for account: Account) -> Binding<Color> {
        Binding(
            get: { Color(hex: account.cardColor ?? "111111") },
            set: { newColor in
                Task {
                    try? await store.setAccountColor(
                        account, hex: Self.hexString(from: newColor)
                    )
                }
            }
        )
    }

    private static func hexString(from color: Color) -> String {
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
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
                        Text(account.isSubscription ? "Subscripción" : account.isRecurring ? "Pago recurrente" : "Cargos y abonos")
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
            Text("Arrastra las tarjetas con el dedo para cambiar el orden en el inicio.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        // Modo de edición siempre activo: se arrastra directo, sin tocar
        // "Editar" (el orden se guarda en Firestore al mover, como antes).
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Orden de tarjetas")
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
