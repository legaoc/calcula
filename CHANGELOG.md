# Historial de versiones — Calcula

La app muestra este historial en Ajustes → Historial de versiones.
La versión actual también se ve en Ajustes, abajo del todo.

## 1.2 — 2026-11-06 — Detalle de tarjetas como la web, con interfaz nativa de iOS
- Tarjeta de cuenta: tipo ("Subscripción" / "Pago recurrente" / "Cargos y abonos"), "Próximo pago" con la cantidad grande, frecuencia y fecha ("Cada mes · 31 oct"), estado ("Apartar $X esta quincena", "Pagar el día X · esta quincena", "Cuenta liquidada"…) y "Toca para ver movimientos".
- Tarjeta de quincena: cantidad grande con "de tu nómina", acciones "Pagar ahora" y "Apartar" con sus cantidades, lista compacta con insignia (Pagar / Vencido / Apartar N/M) y el mensaje "No te toca pagar ni apartar nada aquí." cuando no hay nada.
- Detalle de meta: anillo con % junto a "Juntado $X de $Y", fichas Resta / Cada quincena / Fecha y botones Compartir y Apartar.
- Calendario: filtros con conteo ("Todas 6"), días L M M J V S D, día seleccionado y día del próximo pago marcados, y "Pagos del 30" con nombre y tipo.
- Finanzas: héroe con "Gastado…", comparativa ("Nuevo gasto vs el año pasado"), selector Día/Semana/Mes/Año y gráfica "Comparativa" con mínimo y máximo.
- Diferir: "Reparte un pago", botón "Diferir una cantidad" y filas con fecha corta y cuenta ("30 sep · Apple").

## 1.1 — 2026-11-06 — Reordenar tarjetas y búsqueda global
- Reordenar tarjetas con el dedo: en Ajustes → Orden de tarjetas ya no hay que tocar "Editar", se arrastra directo y el orden se guarda en la nube.
- Búsqueda global: buscador en Inicio que encuentra cuentas, movimientos, metas y presupuestos por nombre, nota, categoría, cantidad o fecha, y al tocar un resultado abre su detalle.

## 1.0 — Primera versión nativa
- App 100% nativa en SwiftUI, sin WebView.
- Inicio de sesión y registro con correo y contraseña (Firebase Auth).
- Cuentas: crear, ver saldo y eliminar.
- Movimientos: agregar ingresos y gastos, ver y eliminar.
- Quincenas, metas, presupuestos, nómina y recordatorios.
- Ajustes: Face ID para bloquear la app, avisos fuera de la app, vibración.
- Menú al mantener presionado una cuenta, movimiento o meta.
- Sincronización con la nube (Firebase Firestore, proyecto psnllega).
- Corrección de compilación: se quitó el producto FirebaseFirestoreSwift, que no existe en firebase-ios-sdk 11.x (su código vive en FirebaseFirestore).
