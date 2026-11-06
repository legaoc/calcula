import SwiftUI
import UIKit

/// Lista de cuentas y detalle de cada cuenta (movimientos, borrar).
struct AccountsView: View {
    @EnvironmentObject private var store: DataStore
    @State private var showingAdd = false
    @State private var accountToDelete: Account?

    var body: some View {
        List {
            ForEach(store.accounts) { account in
                NavigationLink {
                    AccountDetailView(account: account)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(account.name)
                            Text(account.isSubscription ? "Subscripción" : account.isRecurring ? "Pago recurrente" : "Cargos y abonos")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Format.money(account.balance, currency: store.profile?.currency ?? "MXN"))
                            .fontWeight(.semibold)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button("Eliminar", role: .destructive) {
                        accountToDelete = account
                    }
                    Button(account.hiddenFromHome ? "Mostrar" : "Ocultar") {
                        Task {
                            try? await store.setAccountHidden(
                                account, hidden: !account.hiddenFromHome
                            )
                        }
                    }
                    .tint(.gray)
                }
            }
        }
        .navigationTitle("Cuentas")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddAccountView()
        }
        .alert(
            "Eliminar cuenta",
            isPresented: Binding(
                get: { accountToDelete != nil },
                set: { if !$0 { accountToDelete = nil } }
            )
        ) {
            Button("Eliminar", role: .destructive) {
                Task {
                    if let account = accountToDelete {
                        try? await store.deleteAccount(account)
                    }
                    accountToDelete = nil
                }
            }
            Button("Cancelar", role: .cancel) { accountToDelete = nil }
        } message: {
            Text("Se borrará la cuenta con todos sus movimientos y pagos programados.")
        }
    }
}

/// Detalle de una cuenta: héroe con el próximo pago o el saldo, botones
/// de acción y sus movimientos (WEB-INVENTORY §10).
struct AccountDetailView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss
    let account: Account

    @State private var showingAddMovementKind: String?
    @State private var showingDeleteConfirm = false
    @State private var showingEditCard = false
    @State private var paymentToMark: ScheduledPayment?

    /// La cuenta viva del listener, para que el saldo se actualice solo.
    private var liveAccount: Account {
        store.accounts.first { $0.id == account.id } ?? account
    }

    /// El pago programado de la cuenta (recurrentes / suscripciones).
    private var payment: ScheduledPayment? {
        store.scheduledPayments.first { $0.accountId == account.id }
    }

    private var currency: String { store.profile?.currency ?? "MXN" }

    /// "Cada mes · 30 nov", como el héroe de la web.
    private var frequencyText: String? {
        guard let payment, let next = payment.nextPayment else { return nil }
        return "\(QuincenaEngine.frequencyLabel(payment.frequency)) · \(Format.shortDate(next))"
    }

    var body: some View {
        List {
            // Héroe con el color de la tarjeta (como la web).
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if liveAccount.isRecurring, let payment {
                        Text("Próximo pago")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(Format.money(payment.amount, currency: currency))
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                        if let frequencyText {
                            Text(frequencyText)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Button("Registrar pago") { paymentToMark = payment }
                            .buttonStyle(.borderedProminent)
                            .tint(.white)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    } else {
                        Text("Saldo pendiente")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(Format.money(liveAccount.balance, currency: currency))
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Cargos y abonos")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                        HStack(spacing: 12) {
                            Button("+ Cargo") { showingAddMovementKind = "cargo" }
                                .buttonStyle(.borderedProminent)
                                .tint(.white)
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                            Button("Abono") { showingAddMovementKind = "abono" }
                                .buttonStyle(.bordered)
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
                .listRowBackground(Color(hex: liveAccount.cardColor ?? "111111"))
            }

            Section {
                HStack {
                    Text("Tipo")
                    Spacer()
                    Text(liveAccount.isSubscription ? "Subscripción" : liveAccount.isRecurring ? "Pago recurrente" : "Cargos y abonos")
                        .foregroundStyle(.secondary)
                }
                if liveAccount.dueDay > 0 {
                    HStack {
                        Text("Día de vencimiento")
                        Spacer()
                        Text("Día \(liveAccount.dueDay)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Movimientos") {
                let items = store.accountMovements
                if items.isEmpty {
                    Text("Todavía no hay movimientos en esta cuenta.")
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { movement in
                    MovementRow(
                        movement: movement,
                        accountName: liveAccount.name,
                        currency: currency
                    )
                }
                .onDelete { indexSet in
                    Task {
                        for index in indexSet {
                            try? await store.deleteMovement(items[index])
                        }
                    }
                }
            }

            Section {
                Button("Eliminar cuenta", role: .destructive) {
                    showingDeleteConfirm = true
                }
            }
        }
        .navigationTitle(liveAccount.name)
        .task {
            if let id = account.id {
                store.startAccountMovements(accountId: id)
            }
        }
        .onDisappear {
            store.stopAccountMovements()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingEditCard = true } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $showingEditCard) {
            EditCardSheet(account: liveAccount)
        }
        .sheet(item: $paymentToMark) { payment in
            MarkPaymentSheet(payment: payment)
        }
        .sheet(isPresented: Binding(
            get: { showingAddMovementKind != nil },
            set: { if !$0 { showingAddMovementKind = nil } }
        )) {
            AddMovementView(
                preselectedAccountId: account.id,
                preselectedKind: showingAddMovementKind ?? "cargo"
            )
        }
        .alert("Eliminar cuenta", isPresented: $showingDeleteConfirm) {
            Button("Eliminar", role: .destructive) {
                Task {
                    try? await store.deleteAccount(liveAccount)
                    dismiss()
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borrará la cuenta con todos sus movimientos y pagos programados.")
        }
    }
}

private enum NewAccountKind: String, CaseIterable, Identifiable {
    case charges
    case recurring
    case subscription

    var id: String { rawValue }

    var label: String {
        switch self {
        case .charges: return "Cargos"
        case .recurring: return "Recurrente"
        case .subscription: return "Suscripción"
        }
    }
}

/// Formulario de nueva cuenta (mismos campos que la web).
struct AddAccountView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: NewAccountKind = .charges
    @State private var initialBalance = ""
    @State private var dueDay = 0
    @State private var categoriesText = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Cuenta") {
                    TextField("Nombre", text: $name)
                    Picker("Tipo", selection: $kind) {
                        ForEach(NewAccountKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if kind == .charges {
                    Section("Cargos") {
                        TextField("Saldo inicial", text: $initialBalance)
                            .keyboardType(.decimalPad)
                        Stepper("Día de vencimiento: \(dueDay == 0 ? "sin día" : "día \(dueDay)")",
                                value: $dueDay, in: 0...31)
                    }
                }
                Section("Categorías") {
                    TextField("Separadas por comas", text: $categoriesText)
                        .autocapitalization(.none)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Nueva cuenta")
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
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMessage = "Escribe un nombre para la cuenta"
            return
        }
        let balance = Double(
            initialBalance.replacingOccurrences(of: ",", with: ".")
        ) ?? 0
        let categories = categoriesText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        do {
            try await store.addAccount(
                name: trimmed,
                type: kind == .charges ? "charges" : "recurring",
                isSubscription: kind == .subscription,
                initialBalance: kind == .charges ? balance : 0,
                dueDay: kind == .charges ? dueDay : 0,
                categories: categories
            )
            dismiss()
        } catch {
            errorMessage = "No se pudo guardar la cuenta"
        }
    }
}

// MARK: - Hoja "Editar tarjeta" (WEB-INVENTORY §10)
// Color (20 muestras + crear color), interruptor Visible, campo Icono,
// campo sitio web, botones Editar datos / Eliminar cuenta / Guardar.
struct EditCardSheet: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let account: Account

    @State private var colorHex: String
    @State private var customColor: Color
    @State private var visible: Bool
    @State private var iconSlug: String
    @State private var iconDomain: String
    @State private var showingEditData = false
    @State private var showingDeleteConfirm = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var payment: ScheduledPayment? {
        store.scheduledPayments.first { $0.id == account.id }
    }

    init(account: Account) {
        self.account = account
        let current = (account.cardColor ?? "").isEmpty
            ? (account.isRecurring ? "38383d" : "242428")
            : (account.cardColor ?? "242428").lowercased()
        _colorHex = State(initialValue: current)
        _customColor = State(initialValue: Color(hex: current))
        _visible = State(initialValue: !account.hiddenFromHome)
        _iconSlug = State(initialValue: account.iconSlug ?? "")
        _iconDomain = State(initialValue: account.iconDomain ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                        ForEach(ThemePalette.swatches) { swatch in
                            colorDot(hex: swatch.hex, name: swatch.name)
                        }
                    }
                    HStack(spacing: 12) {
                        ColorPicker("Crear color", selection: $customColor, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 44, height: 44)
                        Text("Crear color")
                            .font(.subheadline)
                    }
                }
                Section {
                    Toggle(isOn: $visible) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Visible en el inicio")
                            Text("Si la apagas, sigue existiendo")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Icono") {
                    TextField("Netflix, Izzi, Telmex…", text: $iconSlug)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
                Section("O el sitio web") {
                    TextField("netflix.com", text: $iconDomain)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section {
                    Button("Editar datos") { showingEditData = true }
                    Button("Eliminar cuenta", role: .destructive) {
                        showingDeleteConfirm = true
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Tarjeta — \(account.name)")
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
            .onChange(of: customColor) { _, newColor in
                colorHex = Self.hexString(from: newColor)
            }
            .sheet(isPresented: $showingEditData) {
                if account.isRecurring, let payment {
                    EditPaymentSheet(account: account, payment: payment)
                } else {
                    EditChargeAccountSheet(account: account)
                }
            }
            .alert("Eliminar cuenta", isPresented: $showingDeleteConfirm) {
                Button("Eliminar", role: .destructive) {
                    Task {
                        try? await store.deleteAccount(account)
                        dismiss()
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se borrará la cuenta con todos sus movimientos y pagos programados.")
            }
        }
    }

    private func colorDot(hex: String, name: String) -> some View {
        let selected = colorHex.lowercased() == hex.lowercased()
        return Button {
            colorHex = hex
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 44, height: 44)
                .overlay(
                    Circle().stroke(
                        selected ? Color.calculaAccent : Color.primary.opacity(0.15),
                        lineWidth: selected ? 3 : 1
                    )
                )
                .overlay {
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

    private func save() async {
        guard let id = account.id else { return }
        isSaving = true
        defer { isSaving = false }
        let slug = iconSlug
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        let domain = iconDomain.trimmingCharacters(in: .whitespaces).lowercased()
        do {
            try await store.updateAccount(id: id, patch: [
                "cardColor": colorHex.lowercased(),
                "hiddenFromHome": !visible,
                "iconSlug": slug,
                "iconHex": account.iconHex ?? "",
                "iconDomain": domain,
            ])
            try await store.updatePaymentIcon(
                accountId: id,
                slug: slug,
                hex: account.iconHex ?? "",
                domain: domain
            )
            dismiss()
        } catch {
            errorMessage = "No se pudo guardar la tarjeta"
        }
    }

    /// Hex sin "#" (como lo guarda la web en `cardColor`).
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

// MARK: - Hoja "Editar pago" (WEB-INVENTORY §10)
// Nombre de la cuenta, nombre del pago, monto, frecuencia y próximo pago.
struct EditPaymentSheet: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let account: Account
    let payment: ScheduledPayment

    @State private var accountName: String
    @State private var paymentName: String
    @State private var amountText: String
    @State private var frequency: String
    @State private var nextPayment: Date
    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let frequencies = [
        "weekly", "every15", "monthly", "bimonthly",
        "quarterly", "semiannual", "annual", "custom",
    ]

    init(account: Account, payment: ScheduledPayment) {
        self.account = account
        self.payment = payment
        _accountName = State(initialValue: account.name)
        _paymentName = State(initialValue: payment.name)
        _amountText = State(initialValue: String(payment.amount))
        _frequency = State(initialValue: payment.frequency)
        _nextPayment = State(initialValue: payment.nextPayment ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Modifica la información de tu pago recurrente.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Editar pago") {
                    TextField("Nombre de la cuenta", text: $accountName)
                    TextField("Nombre del pago", text: $paymentName)
                    TextField("Monto", text: $amountText)
                        .keyboardType(.decimalPad)
                    Picker("Frecuencia", selection: $frequency) {
                        ForEach(Self.frequencies, id: \.self) { key in
                            Text(QuincenaEngine.frequencyLabel(key)).tag(key)
                        }
                    }
                    DatePicker("Próximo pago", selection: $nextPayment, displayedComponents: .date)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Editar pago")
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
        }
    }

    private func save() async {
        guard let accountId = account.id, let paymentId = payment.id else { return }
        let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
        guard !accountName.trimmingCharacters(in: .whitespaces).isEmpty,
              !paymentName.trimmingCharacters(in: .whitespaces).isEmpty,
              amount > 0 else {
            errorMessage = "Revisa el nombre y el monto"
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            // La web escribe {name, amount, frequency, nextPayment} (sin
            // customDays): el valor existente se conserva.
            try await store.updateAccount(id: accountId, patch: [
                "name": accountName.trimmingCharacters(in: .whitespaces),
            ])
            try await store.updateScheduledPayment(id: paymentId, patch: [
                "name": paymentName.trimmingCharacters(in: .whitespaces),
                "amount": amount,
                "frequency": frequency,
                "nextPayment": nextPayment,
            ])
            dismiss()
        } catch {
            errorMessage = "No se pudo guardar el pago"
        }
    }
}

// MARK: - Hoja "Editar cuenta" (WEB-INVENTORY §10)
// Nombre y día de pago de una cuenta de cargos.
struct EditChargeAccountSheet: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let account: Account

    @State private var name: String
    @State private var dueDay: Int
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(account: Account) {
        self.account = account
        _name = State(initialValue: account.name)
        _dueDay = State(initialValue: account.dueDay)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Cambia el nombre o el día en que se paga esta cuenta.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Editar cuenta") {
                    TextField("Nombre", text: $name)
                    Picker("Día de pago · opcional", selection: $dueDay) {
                        Text("Sin fecha").tag(0)
                        ForEach(1...31, id: \.self) { day in
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
            .navigationTitle("Editar cuenta")
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
        }
    }

    private func save() async {
        guard let id = account.id else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMessage = "Escribe un nombre para la cuenta"
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.updateAccount(id: id, patch: [
                "name": trimmed,
                "dueDay": dueDay,
            ])
            dismiss()
        } catch {
            errorMessage = "No se pudo guardar la cuenta"
        }
    }
}
