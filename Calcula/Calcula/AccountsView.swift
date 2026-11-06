import SwiftUI

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
                            Text(account.isRecurring ? "Recurrente" : "Cargos")
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

/// Detalle de una cuenta: saldo, datos y sus movimientos.
struct AccountDetailView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss
    let account: Account

    @State private var showingAddMovement = false
    @State private var showingDeleteConfirm = false

    /// La cuenta viva del listener, para que el saldo se actualice solo.
    private var liveAccount: Account {
        store.accounts.first { $0.id == account.id } ?? account
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Saldo")
                    Spacer()
                    Text(Format.money(liveAccount.balance, currency: store.profile?.currency ?? "MXN"))
                        .font(.title3.bold())
                }
                HStack {
                    Text("Tipo")
                    Spacer()
                    Text(liveAccount.isRecurring ? "Recurrente" : "Cargos")
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
                    Text("Sin movimientos todavía.")
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { movement in
                    MovementRow(
                        movement: movement,
                        accountName: liveAccount.name,
                        currency: store.profile?.currency ?? "MXN"
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
                Button { showingAddMovement = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddMovement) {
            AddMovementView(preselectedAccountId: account.id)
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
