import SwiftUI

// MARK: - Finanzas (MAP.md §3.4 y §4.8)
//
// Hero con el gasto del periodo y su delta vs el periodo anterior,
// gráfica de barras del periodo, presupuestos del mes y metas de ahorro.
// Reemplaza al marcador FinanceView de Placeholders.swift (ese archivo
// debe dejar de definir FinanceView para que el proyecto compile sin
// símbolos duplicados).

struct FinanceView: View {
    @EnvironmentObject private var store: DataStore

    @State private var period: FinancePeriod = .month
    @State private var showingNewBudget = false
    @State private var showingNewGoal = false

    private var currency: String { store.profile?.currency ?? "MXN" }

    private var bounds: PeriodBounds { FinanceCalc.bounds(for: period) }

    private var currentSpend: Double {
        FinanceCalc.sumSpend(store.financeMovements, from: bounds.start, to: bounds.end)
    }

    private var previousSpend: Double {
        FinanceCalc.sumSpend(store.financeMovements, from: bounds.prevStart, to: bounds.prevEnd)
    }

    /// "hoy" / "esta semana" / "este mes" / "este año", como la web.
    private var heroPeriodLabel: String {
        switch period {
        case .day: return "hoy"
        case .week: return "esta semana"
        case .month: return "este mes"
        case .year: return "este año"
        }
    }

    /// Etiqueta del periodo anterior para el delta ("que el mes pasado"…).
    private var previousPeriodLabel: String {
        switch period {
        case .day: return "ayer"
        case .week: return "la semana pasada"
        case .month: return "el mes pasado"
        case .year: return "el año pasado"
        }
    }

    /// "Nuevo gasto vs el año pasado" / "X% más que…" / "Sin cambios vs…",
    /// como `renderFinance` de la web.
    private var deltaText: String {
        if previousSpend == 0 {
            return currentSpend > 0
                ? "Nuevo gasto vs \(previousPeriodLabel)"
                : "Sin cambios vs \(previousPeriodLabel)"
        }
        let pct = (currentSpend - previousSpend) / previousSpend * 100
        if abs(pct) < 0.5 { return "Sin cambios vs \(previousPeriodLabel)" }
        let formatted = String(format: "%.0f%%", abs(pct))
        return pct > 0
            ? "\(formatted) más que \(previousPeriodLabel)"
            : "\(formatted) menos que \(previousPeriodLabel)"
    }

    private var deltaColor: Color {
        if previousSpend == 0 || currentSpend == previousSpend { return .secondary }
        return currentSpend > previousSpend ? .red : .green
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    heroCard
                    chartCard
                    budgetsSection
                    goalsSection
                }
                .padding()
            }
            .background(Color.calculaBackground)
            .navigationTitle("Finanzas")
            .sheet(isPresented: $showingNewBudget) {
                BudgetFormView()
            }
            .sheet(isPresented: $showingNewGoal) {
                GoalFormView()
            }
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gastado \(heroPeriodLabel)")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(Format.money(currentSpend, currency: currency))
                .font(.system(size: 38, weight: .bold, design: .default))
                .tracking(-1)

            Text(deltaText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(deltaColor)

            // Selector de periodo al final de la tarjeta, como la web;
            // el control segmentado es el patrón nativo de iOS.
            Picker("Periodo", selection: $period) {
                ForEach(FinancePeriod.allCases, id: \.self) { period in
                    Text(period.label).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.calculaCard)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    // MARK: - Gráfica

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comparativa")
                .font(.headline)

            let buckets = FinanceCalc.buckets(for: period, movements: store.financeMovements)
            let maxAmount = buckets.map(\.amount).max() ?? 0

            if maxAmount <= 0 {
                Text("Sin gastos en este periodo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 32)
            } else {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(buckets) { bucket in
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(bucket.isNow
                                      ? Color.calculaAccent
                                      : Color.gray.opacity(0.35))
                                .frame(height: max(4, bucket.amount / maxAmount * 110))
                            Text(bucket.label)
                                .font(.caption2)
                                .foregroundStyle(bucket.isNow ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 132)

                // Leyenda con el mínimo y el máximo, como la web.
                HStack {
                    Text(Format.money(0, currency: currency))
                    Spacer()
                    Text(Format.money(max(maxAmount, 1), currency: currency))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(Color.calculaCard)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    // MARK: - Presupuestos del mes

    private var budgetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Presupuestos del mes")
                .font(.title3.bold())

            if store.budgets.isEmpty {
                Text("Aún no tienes un tope del mes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.calculaCard)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 12) {
                    ForEach(store.budgets) { budget in
                        BudgetRow(budget: budget)
                    }
                }
            }

            Button("Nuevo presupuesto") {
                showingNewBudget = true
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Metas de ahorro

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Metas de ahorro")
                    .font(.title3.bold())
                Spacer()
                Button("Nueva meta") {
                    showingNewGoal = true
                }
                .font(.subheadline.weight(.semibold))
            }

            if store.goals.isEmpty {
                Text("Aún no tienes metas. Crea una para empezar a apartar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.calculaCard)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 12) {
                    ForEach(store.goals) { goal in
                        NavigationLink {
                            GoalDetailView(goal: goal)
                        } label: {
                            GoalRow(goal: goal)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
