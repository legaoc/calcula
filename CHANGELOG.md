# Historial de versiones — Calcula

La app muestra este historial en Ajustes → Historial de versiones.
La versión actual también se ve en Ajustes, abajo del todo.

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
