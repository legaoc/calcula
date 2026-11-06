import SwiftUI

/// Búsqueda global (como la web, MAP.md §3.6): cuentas, movimientos,
/// metas y presupuestos por nombre, nota, categoría, cantidad o fecha.
/// Los resultados se actualizan en vivo (máx. 40, como la web) y al
/// tocar uno se abre su detalle.
/// Desde la 1.2.4 es una vista incrustada en Inicio: el campo vive en la
/// píldora expandible del encabezado (`HomeView.searchPill`) y esta vista
/// solo muestra las sugerencias, el estado vacío o los resultados en
/// línea, sin hoja desde abajo. El destino de cada resultado lo registra
/// Inicio con `navigationDestination(for: SearchDestination.self)`.
struct SearchView: View {
    @EnvironmentObject private var store: DataStore

    /// Texto de búsqueda (lo escribe el campo de la píldora del encabezado).
    @Binding var query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if trimmedQuery.isEmpty {
                hintView
            } else if sections.isEmpty {
                emptyView
            } else {
                resultsList
            }
        }
    }

    private var currency: String {
        store.profile?.currency ?? "MXN"
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
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
        .frame(maxWidth: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Text("Sin resultados para \"\(trimmedQuery)\".")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }

    /// Resultados en línea (sin `List`: esta vista vive dentro del
    /// `ScrollView` de Inicio, así que usa un `LazyVStack` con
    /// encabezados de sección y separadores, como el resto de Inicio).
    private var resultsList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(sections) { section in
                Text(section.title)
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .padding(.bottom, 4)
                ForEach(section.rows) { result in
                    rowView(for: result)
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                    if result.id != section.rows.last?.id {
                        Divider().padding(.leading, 16)
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

/// Vista de destino al tocar un resultado de búsqueda: resuelve el objeto
/// vivo por id. La registra Inicio con
/// `.navigationDestination(for: SearchDestination.self)`.
struct SearchDestinationView: View {
    @EnvironmentObject private var store: DataStore

    let destination: SearchDestination

    var body: some View {
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
}

/// Destino al tocar un resultado (por id, para resolver el objeto vivo).
enum SearchDestination: Hashable {
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
