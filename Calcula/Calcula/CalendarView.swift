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
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var category: CalendarCategory = .all

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
                    kindLabel: payment.isSubscription ? "Suscripción" : "Pago recurrente",
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
        eventsByDay[QuincenaEngine.startOfDay(selectedDay)] ?? []
    }

    private var isSelectedDayToday: Bool {
        calendar.isDateInToday(selectedDay)
    }

    /// Próximo pago programado (para mostrarlo si hoy no hay pagos).
    private var nextPayment: ScheduledPayment? {
        store.scheduledPayments.first { $0.nextPayment != nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Mes navegable
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

                    // Filtros con contador
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(CalendarCategory.allCases) { option in
                                Button {
                                    category = option
                                } label: {
                                    Text("\(option.label) (\(count(for: option)))")
                                        .font(.subheadline.bold())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            category == option
                                                ? Color.calculaAccent
                                                : Color.calculaCard
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

                    // Rejilla L–D (lunes primero)
                    VStack(spacing: 8) {
                        HStack {
                            ForEach(["L", "M", "X", "J", "V", "S", "D"], id: \.self) { letter in
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

                    // Pagos del día seleccionado
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pagos del \(Format.date(selectedDay))")
                            .font(.headline)
                        if selectedDayEvents.isEmpty {
                            if isSelectedDayToday, let nextPayment {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Hoy no hay pagos. El próximo es:")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    eventRow(
                                        name: nextPayment.name,
                                        kindLabel: nextPayment.isSubscription ? "Suscripción" : "Pago recurrente",
                                        amount: nextPayment.amount,
                                        date: nextPayment.nextPayment
                                    )
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
                                    amount: event.amount,
                                    date: event.date
                                )
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color.calculaBackground)
            .navigationTitle("Calendario")
        }
    }

    private func changeMonth(by value: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = newMonth
        selectedDay = calendar.date(from: calendar.dateComponents([.year, .month], from: newMonth)) ?? newMonth
    }

    @ViewBuilder
    private func dayCell(day: Int) -> some View {
        let year = calendar.component(.year, from: displayedMonth)
        let month = calendar.component(.month, from: displayedMonth)
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? displayedMonth
        let dayStart = QuincenaEngine.startOfDay(date)
        let events = eventsByDay[dayStart] ?? []
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(date)
        Button {
            selectedDay = dayStart
        } label: {
            VStack(spacing: 4) {
                Text("\(day)")
                    .font(.subheadline)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(isSelected ? .white : (isToday ? Color.calculaAccent : .primary))
                    .frame(width: 30, height: 30)
                    .background(isSelected ? Color.calculaAccent : Color.clear)
                    .clipShape(Circle())
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

    @ViewBuilder
    private func eventRow(name: String, kindLabel: String, amount: Double, date: Date?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(kindLabel)
                    if let date {
                        Text("·")
                        Text(Format.date(date))
                    }
                }
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
