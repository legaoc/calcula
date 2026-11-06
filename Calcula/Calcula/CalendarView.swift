import SwiftUI

// MARK: - Calendario (MAP.md §3.5 y §4.9)
// Mes navegable, filtros con contador, rejilla L–D con puntos de color
// por evento y lista de pagos del día seleccionado.

struct CalendarView: View {
    @EnvironmentObject private var store: DataStore

    @State private var displayedMonth: Date = {
        let now = Date()
        let comps = Calendar.current.dateComponents([.year, .month], from: now)
        return Calendar.current.date(from: comps) ?? now
    }()
    /// Día seleccionado; `nil` = ninguno (al cambiar de mes no queda
    /// ningún día seleccionado, como la web).
    @State private var selectedDay: Date? = Calendar.current.startOfDay(for: Date())
    @State private var category: CalendarCategory = .all
    @State private var showBackToTop = false

    // MARK: - Categorías de evento (eventCategory en la web)

    enum CalendarCategory: String, CaseIterable, Identifiable {
        case all
        case subs
        case weekly
        case charges

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "Todas"
            case .subs: return "Suscripciones"
            case .weekly: return "Semanales"
            case .charges: return "Cargos"
            }
        }
    }

    private struct CalendarEvent: Identifiable {
        let id: String
        let date: Date
        let name: String
        let kindLabel: String
        let amount: Double
        let hex: String
        let category: CalendarCategory
    }

    private let calendar = Calendar.current

    private var currency: String { store.profile?.currency ?? "MXN" }

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))
            ?? displayedMonth
    }

    private var monthEnd: Date {
        let days = calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
        return calendar.date(byAdding: .day, value: days - 1, to: monthStart) ?? displayedMonth
    }

    /// Eventos del mes visible: recurrentes por occurrencesInRange +
    /// cargos con dueDay (el día dueDay del mes, limitado al último día).
    private var allEvents: [CalendarEvent] {
        var events: [CalendarEvent] = []
        for payment in store.scheduledPayments {
            let account = store.accounts.first { $0.id == payment.accountId }
            let hex = account?.cardColor ?? "111111"
            let category: CalendarCategory
            if payment.isSubscription {
                category = .subs
            } else if payment.frequency == "weekly" || payment.frequency == "every15" {
                category = .weekly
            } else {
                category = .all
            }
            for date in QuincenaEngine.occurrencesInRange(payment, from: monthStart, until: monthEnd) {
                events.append(CalendarEvent(
                    id: "\(payment.id ?? "")-\(date.timeIntervalSince1970)",
                    date: date,
                    name: payment.name,
                    kindLabel: kindLabel(for: category),
                    amount: payment.amount,
                    hex: hex,
                    category: category
                ))
            }
        }
        let year = calendar.component(.year, from: displayedMonth)
        let month = calendar.component(.month, from: displayedMonth)
        let lastDay = QuincenaEngine.lastDayOfMonth(year: year, month: month)
        for account in store.accounts where account.type == "charges" {
            guard account.dueDay >= 1, account.balance > 0 else { continue }
            let day = min(account.dueDay, lastDay)
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else { continue }
            events.append(CalendarEvent(
                id: "charge-\(account.id ?? "")-\(year)-\(month)",
                date: date,
                name: account.name,
                kindLabel: "Cargo",
                amount: account.balance,
                hex: account.cardColor ?? "111111",
                category: .charges
            ))
        }
        return events.sorted { $0.date < $1.date }
    }

    private var filteredEvents: [CalendarEvent] {
        category == .all ? allEvents : allEvents.filter { $0.category == category }
    }

    private var eventsByDay: [Date: [CalendarEvent]] {
        Dictionary(grouping: filteredEvents) { QuincenaEngine.startOfDay($0.date) }
    }

    private func count(for category: CalendarCategory) -> Int {
        category == .all ? allEvents.count : allEvents.filter { $0.category == category }.count
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth).capitalized
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
    }

    /// Desplazamiento del día 1 con lunes primero (L–D).
    private var firstDayOffset: Int {
        let weekday = calendar.component(.weekday, from: monthStart)
        return (weekday + 5) % 7
    }

    private var selectedDayEvents: [CalendarEvent] {
        guard let selectedDay else { return [] }
        return eventsByDay[QuincenaEngine.startOfDay(selectedDay)] ?? []
    }

    private var isSelectedDayToday: Bool {
        guard let selectedDay else { return false }
        return calendar.isDateInToday(selectedDay)
    }

    /// Próximo pago programado (para mostrarlo si hoy no hay pagos).
    private var nextPayment: ScheduledPayment? {
        store.scheduledPayments.first { $0.nextPayment != nil }
    }

    /// Día del próximo pago dentro del mes visible (la web lo marca con
    /// un anillo, `is-next`): el primer pago programado, si cae este mes.
    private var nextPaymentDay: Int? {
        guard let next = store.scheduledPayments.compactMap(\.nextPayment).min() else { return nil }
        let comps = calendar.dateComponents([.year, .month, .day], from: next)
        let monthComps = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard comps.year == monthComps.year, comps.month == monthComps.month else { return nil }
        return comps.day
    }

    /// Etiqueta de la fila de pagos, como la web: "Subscripción" /
    /// "Pago semanal" / "Cargo" ("Pago recurrente" para el resto).
    private func kindLabel(for category: CalendarCategory) -> String {
        switch category {
        case .subs: return "Subscripción"
        case .weekly: return "Pago semanal"
        case .charges: return "Cargo"
        case .all: return "Pago recurrente"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                    // Mes navegable + filtros (una tarjeta, como la web).
                    VStack(spacing: 12) {
                        HStack {
                            Button {
                                changeMonth(by: -1)
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.headline)
                                    .padding(8)
                            }
                            Spacer()
                            Text(monthTitle)
                                .font(.title3.bold())
                            Spacer()
                            Button {
                                changeMonth(by: 1)
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.headline)
                                    .padding(8)
                            }
                        }

                        // Filtros con contador ("Todas 6", como la web).
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(CalendarCategory.allCases) { option in
                                    Button {
                                        category = option
                                    } label: {
                                        Text("\(option.label) \(count(for: option))")
                                            .font(.subheadline.bold())
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                category == option
                                                    ? Color.calculaAccent
                                                    : Color(.tertiarySystemFill)
                                            )
                                            .foregroundStyle(
                                                category == option ? .white : .primary
                                            )
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.calculaCard)
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                    // Rejilla L–D (lunes primero), en su propia tarjeta.
                    VStack(spacing: 8) {
                        HStack {
                            ForEach(["L", "M", "M", "J", "V", "S", "D"], id: \.self) { letter in
                                Text(letter)
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                            spacing: 8
                        ) {
                            ForEach(0..<firstDayOffset, id: \.self) { _ in
                                Color.clear.frame(height: 44)
                            }
                            ForEach(1...daysInMonth, id: \.self) { day in
                                dayCell(day: day)
                            }
                        }
                    }
                    .padding()
                    .background(Color.calculaCard)
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                    // Pagos del día seleccionado (una tarjeta, como la web).
                    VStack(alignment: .leading, spacing: 8) {
                        if let selectedDay {
                            Text("Pagos del \(calendar.component(.day, from: selectedDay))")
                                .font(.headline)
                            if selectedDayEvents.isEmpty {
                                if isSelectedDayToday, let nextPayment {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Sin pago en ese día.")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        if let nextDate = nextPayment.nextPayment {
                                            Text("Próximo pago: \(Format.shortDate(nextDate)) · \(nextPayment.name) · \(Format.money(nextPayment.amount, currency: currency))")
                                                .font(.subheadline)
                                        }
                                    }
                                } else {
                                    Text("No hay pagos este día")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                ForEach(selectedDayEvents) { event in
                                    eventRow(
                                        name: event.name,
                                        kindLabel: event.kindLabel,
                                        amount: event.amount
                                    )
                                }
                            }
                        } else {
                            // Al cambiar de mes no queda ningún día
                            // seleccionado (como la web).
                            Text("Elige un día")
                                .font(.headline)
                            Text("No hay pagos este día.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.calculaCard)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                }
                .padding()
                .id("calendarTop")
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ScrollOffsetKey.self,
                            value: geometry.frame(in: .named("calendarScroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "calendarScroll")
            .background(Color.calculaBackground)
            .onPreferenceChange(ScrollOffsetKey.self) { minY in
                showBackToTop = minY < -200
            }
            .overlay(alignment: .bottom) {
                if showBackToTop {
                    Button("Volver arriba") {
                        withAnimation { proxy.scrollTo("calendarTop", anchor: .top) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.calculaAccent)
                    .padding(.bottom, 16)
                }
            }
            }
            .navigationTitle("Calendario")
        }
    }

    private func changeMonth(by value: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = newMonth
        // Al cambiar de mes no queda ningún día seleccionado (como la web).
        selectedDay = nil
    }

    @ViewBuilder
    private func dayCell(day: Int) -> some View {
        let year = calendar.component(.year, from: displayedMonth)
        let month = calendar.component(.month, from: displayedMonth)
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? displayedMonth
        let dayStart = QuincenaEngine.startOfDay(date)
        let events = eventsByDay[dayStart] ?? []
        let isSelected = selectedDay.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
        let isToday = calendar.isDateInToday(date)
        let isNext = nextPaymentDay == day
        Button {
            selectedDay = dayStart
        } label: {
            VStack(spacing: 4) {
                Text("\(day)")
                    .font(.subheadline)
                    .fontWeight(isToday || isSelected ? .bold : .regular)
                    // Día seleccionado: relleno del sistema con texto
                    // invertido, visible en modo claro y oscuro (la web
                    // hace lo mismo: claro en oscuro, oscuro en claro).
                    .foregroundStyle(isSelected ? Color(.systemBackground) : .primary)
                    .frame(width: 30, height: 30)
                    .background(
                        isSelected
                            ? Color.primary
                            : isToday
                                ? Color.primary.opacity(0.1)
                                : Color.clear
                    )
                    .clipShape(Circle())
                    // Día del próximo pago: anillo, como `is-next` de la web.
                    .overlay {
                        if isNext && !isSelected {
                            Circle().stroke(Color.primary, lineWidth: 2)
                        }
                    }
                // Puntos con el color de la tarjeta de la cuenta, como
                // `accountDotColor` de la web (en las capturas de Jesus se
                // ven rojo/azul/gris porque así son sus tarjetas:
                // Elektra #e22400, Telmex #01c7fc, Apple #242428).
                // Los puntos ya se filtran por el filtro activo
                // (`eventsByDay` viene de `filteredEvents`).
                HStack(spacing: 2) {
                    if events.count > 4 {
                        ForEach(Array(events.prefix(3)), id: \.id) { event in
                            Circle()
                                .fill(Color(hex: event.hex))
                                .frame(width: 6, height: 6)
                        }
                        Text("+")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(events) { event in
                            Circle()
                                .fill(Color(hex: event.hex))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                .frame(height: 8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .buttonStyle(.plain)
    }

    /// Fila de pago del día: nombre + tipo y monto (la fecha va en el
    /// título "Pagos del N", como la web).
    @ViewBuilder
    private func eventRow(name: String, kindLabel: String, amount: Double) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                Text(kindLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.money(amount, currency: currency))
                .font(.headline)
        }
        .padding(.vertical, 4)
    }
}

/// Desplazamiento vertical del contenido del calendario (para mostrar el
/// botón "Volver arriba" al hacer scroll; iOS 17 no tiene
/// `onScrollGeometryChange`).
private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
