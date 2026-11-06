import SwiftUI

/// Búsqueda global (como la web, MAP.md §3.6): cuentas, movimientos,
/// metas y presupuestos por nombre, nota, categoría, cantidad o fecha.
/// Los resultados se actualizan en vivo (máx. 40, como la web) y al
/// tocar uno se abre su detalle.
struct SearchView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                if trimmedQuery.isEmpty {
                    hintView
                } else if sections.isEmpty {
                    emptyView
                } else {
                    resultsList
                }
            }
            .navigationTitle("Buscar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .navigationDestination(for: SearchDestination.self) { destination in
                destinationView(for: destination)
            }
        }
        .onAppear { searchFocused = true }
    }

    private var currency: String {
        store.profile?.currency ?? "MXN"
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Buscar cuentas, movimientos, metas…", text: $query)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($searchFocused)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color.calculaCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
    }

    private var hintView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Busca cuentas, movimientos, metas y presupuestos por nombre, nota, categoría, cantidad o fecha.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Text("Sin resultados para \"\(trimmedQuery)\".")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsList: some View {
        List {
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.rows) { result in
                        rowView(for: result)
                    }
                }
            }
        }
    }

    /// Secciones con resultados (máx. 40 en total, como la web).
    private var sections: [SearchSection] {
        let q = trimmedQuery
        guard !q.isEmpty else { return [] }
        var found: [SearchSection] = []
        var total = 0
        func take(_ rows: [SearchResult], title: String) {
            guard total < 40, !rows.isEmpty else { return }
            let slice = Array(rows.prefix(40 - total))
            found.append(SearchSection(title: title, rows: slice))
            total += slice.count
        }
        take(
            store.accounts.filter { matches($0.name, q) }.map { .account($0) },
            title: "Cuentas"
        )
        take(
            store.financeMovements.filter { movementMatches($0, q) }.map { .movement($0) },
            title: "Movimientos"
        )
        take(
            store.goals.filter { matches($0.name, q) }.map { .goal($0) },
            title: "Metas"
        )
        take(
            store.budgets.filter { matches($0.name, q) || matches($0.category, q) }
                .map { .budget($0) },
            title: "Presupuestos"
        )
        return found
    }

    @ViewBuilder
    private func destinationView(for destination: SearchDestination) -> some View {
        switch destination {
        case .account(let id):
            if let account = store.accounts.first(where: { $0.id == id }) {
                AccountDetailView(account: account)
            } else {
                Text("Cuenta no encontrada")
                    .foregroundStyle(.secondary)
            }
        case .goal(let id):
            if let goal = store.goals.first(where: { $0.id == id }) {
                GoalDetailView(goal: goal)
            } else {
                Text("Meta no encontrada")
                    .foregroundStyle(.secondary)
            }
        case .budget(let id):
            if let budget = store.budgets.first(where: { $0.id == id }) {
                BudgetDetailView(budget: budget)
            } else {
                Text("Presupuesto no encontrado")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rowView(for result: SearchResult) -> some View {
        switch result {
        case .account(let account):
            NavigationLink(value: SearchDestination.account(id: account.id ?? "")) {
                SearchRow(
                    title: account.name,
                    subtitle: account.isSubscription ? "Subscripción" : account.isRecurring ? "Pago recurrente" : "Cargos y abonos",
                    trailing: Format.money(account.balance, currency: currency)
                )
            }
        case .movement(let movement):
            NavigationLink(value: SearchDestination.account(id: movement.accountId)) {
                SearchRow(
                    title: movement.note.isEmpty
                        ? accountName(for: movement.accountId)
                        : movement.note,
                    subtitle: "\(accountName(for: movement.accountId)) · \(Format.date(movement.createdAt))",
                    trailing: (movement.balanceDelta >= 0 ? "+" : "−")
                        + Format.money(abs(movement.amount), currency: currency)
                )
            }
        case .goal(let goal):
            NavigationLink(value: SearchDestination.goal(id: goal.id ?? "")) {
                let status = FinanceCalc.goalStatus(goal: goal)
                SearchRow(
                    title: goal.name,
                    subtitle: "\(Format.money(goal.saved, currency: currency)) de \(Format.money(goal.target, currency: currency))",
                    trailing: "\(status.pct)%"
                )
            }
        case .budget(let budget):
            NavigationLink(value: SearchDestination.budget(id: budget.id ?? "")) {
                SearchRow(
                    title: budget.name,
                    subtitle: budget.category,
                    trailing: Format.money(budget.amount, currency: currency)
                )
            }
        }
    }

    private func accountName(for id: String) -> String {
        store.accounts.first { $0.id == id }?.name ?? "Cuenta"
    }

    // MARK: - Coincidencias

    /// Comparación sin acentos ni mayúsculas (para nombres en español).
    private func normalized(_ text: String) -> String {
        text.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "es_MX")
        )
    }

    private func matches(_ text: String, _ query: String) -> Bool {
        normalized(text).contains(normalized(query))
    }

    private func movementMatches(_ movement: Movement, _ query: String) -> Bool {
        if matches(movement.note, query) { return true }
        if let category = movement.category, matches(category, query) { return true }
        if let account = store.accounts.first(where: { $0.id == movement.accountId }),
           matches(account.name, query) { return true }
        if matches(movement.type, query) { return true }
        if amountMatches(movement.amount, query: query) { return true }
        if dateMatches(movement.createdAt, query: query) { return true }
        return false
    }

    /// Cantidad exacta (como la web) o por texto formateado ("1,500").
    private func amountMatches(_ amount: Double, query: String) -> Bool {
        let cleaned = query
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        if let number = Double(cleaned), number > 0 {
            return abs(amount - number) < 0.005
        }
        return normalized(Format.money(amount)).contains(normalized(query))
    }

    /// Fecha como la muestra la app ("5 dic 2026") o numérica ("05/12/2026").
    private func dateMatches(_ date: Date?, query: String) -> Bool {
        guard let date else { return false }
        let q = normalized(query)
        if normalized(Format.date(date)).contains(q) { return true }
        return normalized(Self.numericDateFormatter.string(from: date)).contains(q)
    }

    private static let numericDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()
}

/// Destino al tocar un resultado (por id, para resolver el objeto vivo).
private enum SearchDestination: Hashable {
    case account(id: String)
    case goal(id: String)
    case budget(id: String)
}

private enum SearchResult: Identifiable {
    case account(Account)
    case movement(Movement)
    case goal(Goal)
    case budget(Budget)

    var id: String {
        switch self {
        case .account(let account): return "account-\(account.id ?? "")"
        case .movement(let movement): return "movement-\(movement.id ?? "")"
        case .goal(let goal): return "goal-\(goal.id ?? "")"
        case .budget(let budget): return "budget-\(budget.id ?? "")"
        }
    }
}

private struct SearchSection: Identifiable {
    var title: String
    var rows: [SearchResult]

    var id: String { title }
}

private struct SearchRow: View {
    let title: String
    let subtitle: String
    let trailing: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(trailing)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
    }
}
