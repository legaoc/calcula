import SwiftUI

/// Pestañas iguales que la web: Inicio, Diferir, [+] , Finanzas, Calendario.
/// El botón central abre el registro rápido de movimiento.
enum Tab: String, Hashable {
    case inicio
    case diferir
    case agregar
    case finanzas
    case calendario
}

struct ContentView: View {
    @State private var selection: Tab = .inicio
    @State private var previousTab: Tab = .inicio
    @State private var showingAdd = false

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Inicio", systemImage: "house.fill") }
                .tag(Tab.inicio)
            DiferirView()
                .tabItem { Label("Diferir", systemImage: "calendar") }
                .tag(Tab.diferir)
            Color.clear
                .tabItem { Label("Agregar", systemImage: "plus.circle.fill") }
                .tag(Tab.agregar)
            FinanceView()
                .tabItem { Label("Finanzas", systemImage: "chart.pie.fill") }
                .tag(Tab.finanzas)
            CalendarView()
                .tabItem { Label("Calendario", systemImage: "calendar.badge.clock") }
                .tag(Tab.calendario)
        }
        .onChange(of: selection) { _, newValue in
            if newValue == .agregar {
                showingAdd = true
                selection = previousTab
            } else {
                previousTab = newValue
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddMovementView()
        }
    }
}
