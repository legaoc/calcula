import SwiftUI

// MARK: - Presupuestos (MAP.md §1.6 y §4.6)
//
// Presupuestos mensuales por categoría: se reinician solos porque el
// cálculo siempre es del mes en curso. La web no tiene edición ni
// borrado de presupuestos; el borrado por swipe aquí es una decisión
// consciente (añadida a petición expresa para la versión nativa).

struct BudgetsView: View {
    @EnvironmentObject private var store: DataStore

    @State private var showingNewBudget = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.budgets.isEmpty {
                    ContentUnavailableView(
                        "Sin presupuestos",
                        systemImage: "chart.pie",
                        description: Text("Crea un presupuesto para seguir tu gasto del mes por categoría.")
                    )
                } else {
                    List {
                        ForEach(store.budgets) { budget in
                            BudgetRow(budget: budget)
                        }
                        .onDelete(perform: delete)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.calculaBackground)
            .navigationTitle("Presupuestos")
            .toolbar {
                Button {
                    showingNewBudget = true
                } label: {
                    Label("Nuevo presupuesto", systemImage: "plus")
                }
            }
            .sheet(isPresented: $showingNewBudget) {
                BudgetFormView()
            }
            .alert("Algo salió mal", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let budgets = offsets.map { store.budgets[$0] }
        Task {
            do {
                for budget in budgets {
                    try await store.deleteBudget(budget)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Fila de presupuesto

struct BudgetRow: View {
    @EnvironmentObject private var store: DataStore

    let budget: Budget

    private var currency: String { store.profile?.currency ?? "MXN" }

    var body: some View {
        let spent = FinanceCalc.monthSpendByCategory(
            store.financeMovements,
            category: budget.category,
            accounts: store.accounts
        )
        let status = FinanceCalc.budgetStatus(budget: budget, spent: spent)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(budget.name)
                    .font(.headline)
                Spacer()
                Text("\(status.pct)%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(barColor(for: status.level))
            }

            Text(categoryLabel(for: budget.category))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("\(Format.money(status.spent, currency: currency)) / \(Format.money(status.cap, currency: currency))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ProgressView(value: min(1, status.cap > 0 ? status.spent / status.cap : 0))
                .tint(barColor(for: status.level))
        }
        .padding(.vertical, 4)
    }

    /// Nivel "hot" (≥100%) rojo, "warn" (≥80%) naranja; si no, acento.
    private func barColor(for level: String) -> Color {
        switch level {
        case "hot": return .red
        case "warn": return .orange
        default: return Color.calculaAccent
        }
    }

    /// Etiqueta visible de la categoría: "all" → Todas, "subs" →
    /// Suscripciones, "otros" → Otros, id personalizado → su label, y
    /// cualquier otro valor se muestra tal cual.
    private func categoryLabel(for category: String) -> String {
        switch category {
        case "all": return "Todas"
        case "subs": return "Suscripciones"
        case "otros": return "Otros"
        default:
            if let custom = store.profile?.customCats.first(where: { $0.id == category }) {
                return custom.label
            }
            return category
        }
    }
}

// MARK: - Detalle de presupuesto (destino de la búsqueda global)

/// Las tarjetas de presupuesto no tenían pantalla de detalle en la app;
/// esta es mínima: la misma fila de la lista y eliminar.
struct BudgetDetailView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let budget: Budget

    @State private var showingDeleteConfirm = false

    var body: some View {
        List {
            Section {
                BudgetRow(budget: budget)
            }
            Section {
                Button("Eliminar presupuesto", role: .destructive) {
                    showingDeleteConfirm = true
                }
            }
        }
        .navigationTitle(budget.name)
        .alert("Eliminar presupuesto", isPresented: $showingDeleteConfirm) {
            Button("Eliminar", role: .destructive) {
                Task {
                    try? await store.deleteBudget(budget)
                    dismiss()
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borrará el presupuesto.")
        }
    }
}

// MARK: - Formulario de alta de presupuesto

struct BudgetFormView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var amount: Double = 0
    @State private var category: String = "all"
    @State private var errorMessage: String?

    /// Opciones del picker: fijas ("all", "subs", "otros") + categorías
    /// de las cuentas + categorías personalizadas del perfil (el `id`
    /// como valor y el `label` como texto visible).
    private var categoryOptions: [(value: String, label: String)] {
        var options: [(value: String, label: String)] = [
            ("all", "Todas"),
            ("subs", "Suscripciones"),
            ("otros", "Otros"),
        ]
        let accountCats = Set(store.accounts.flatMap(\.categories))
        for cat in accountCats.sorted() where !options.contains(where: { $0.value == cat }) {
            options.append((cat, cat))
        }
        for custom in store.profile?.customCats ?? [] {
            if !options.contains(where: { $0.value == custom.id }) {
                options.append((custom.id, custom.label))
            }
        }
        return options
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Presupuesto") {
                    TextField("Nombre", text: $name)
                    TextField("Tope mensual", value: $amount, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                }

                Section("Categoría") {
                    Picker("Categoría", selection: $category) {
                        ForEach(categoryOptions, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                }

                Section {
                    Text("El gasto se mide solo con los movimientos de este mes. Al 80% la barra se pone naranja y al 100% roja.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Nuevo presupuesto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") {
                        Task { await save() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || amount <= 0)
                }
            }
            .alert("Algo salió mal", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() async {
        do {
            try await store.addBudget(
                name: name.trimmingCharacters(in: .whitespaces),
                amount: amount,
                category: category
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
