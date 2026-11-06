# Calcula — versión 100% nativa en Swift (SwiftUI)

Reescritura nativa de la app de gastos "Calcula" (antes un solo `index.html`
con Capacitor). Usa el mismo proyecto Firebase **`psnllega`** y el mismo
modelo de datos Firestore que la versión web, así que no se pierde ningún
dato: cuentas, movimientos, metas, presupuestos, nómina y recordatorios
viven en `users/{uid}/...` igual que antes.

La versión HTML (`legaoc/psnlgastos-app`) sigue como respaldo hasta que
esta versión Swift esté completa y probada.

## Estructura

```
Calcula/                  Proyecto Xcode (SwiftUI, iOS 17+)
  Calcula.xcodeproj/      project.pbxproj + Firebase por SPM
  Calcula/
    CalculaApp.swift      Arranque, FirebaseApp.configure(), raíz
    Models.swift          Account, Movement, Goal, Budget, ScheduledPayment
    AuthViewModel.swift   Login / registro email+contraseña
    DataStore.swift       Listeners Firestore + CRUD (cuentas, movimientos)
    Theme.swift           Colores y formato MXN / es_MX
    LoginView.swift       Login y registro
    ContentView.swift     TabView: Inicio, Diferir, +, Finanzas, Calendario
    HomeView.swift        Total, tarjetas de cuentas, movimientos recientes
    AccountsView.swift    Lista, detalle y alta de cuentas
    AddMovementView.swift Registro rápido de movimiento
    Placeholders.swift    Diferir / Finanzas / Calendario (etapa 2) + Ajustes
    BiometricLock.swift   Face ID / Touch ID + pantalla de bloqueo
    NotificationService.swift  Avisos locales de pagos programados
    GoogleService-Info.plist  Config de Firebase (ver abajo)
    Assets.xcassets/      Icono + color de acento
.github/workflows/build-ipa.yml  Compila el IPA sin firma en GitHub Actions
MAP.md                    Mapa completo de la app web (datos, pantallas, reglas)
```

## Estado (etapa 2 — app completa)

Hecho:
- Login / registro con nombre y onboarding de 4 pasos (cadencia,
  moneda, colores, cuentas; crea "Gastos"/"Ahorro").
- Inicio: total pendiente, banner "Por pagar", tarjetas de cuentas,
  "Para estar al día" (esta quincena y la siguiente), "Próximos pagos"
  (5, con Pagar), últimos 10 movimientos, menú al mantener presionado
  y hápticos.
- Cuentas: lista, detalle con sus movimientos, alta, ocultar, reordenar,
  borrar en cascada. Movimientos: alta rápida, borrado con ajuste de
  saldo (cargo suma, abono resta, pago no mueve saldos).
- Diferir y quincenas: plan completo (reparto por quincenas, vencidos,
  cargos por día de pago), pagar/abonar/diferir, studio de diferir.
- Finanzas: gastado por periodo con delta, gráfica de barras,
  presupuestos (warn ≥80%, hot ≥100%), metas (anillo, apartar, editar,
  compartir como imagen).
- Calendario mensual con filtros y puntos por día.
- Ajustes completos: perfil, modo nocturno, recordatorios (avisos fuera
  de la app + exportar ICS), exportar CSV (mes/quincena),
  sincronización (interruptor nube + "Sincronizar ahora"), Face ID,
  historial de versiones, versión del Bundle, cerrar sesión.
- IPA sin firma en GitHub Actions (artefacto `Calcula-IPA`).

Pendiente: búsqueda global, saludo animado, pull-to-refresh, reordenar
tarjetas por drag (existe por lista), "Acceso para Atajos" (omitido a
propósito, dato sensible) y la decisión del saldo (§8.1 de MAP.md).
Ver MAP.md §13.

## Firebase: listo

El `GoogleService-Info.plist` de `Calcula/Calcula/` es el **real**,
descargado de la consola de Firebase por Jesus: app iOS ya registrada
con bundle ID `com.legaoc.psnlgastos` en el proyecto `psnllega`
(GOOGLE_APP_ID `1:666775333115:ios:6501c150c0a14a8e8f685e`). No hay que
hacer nada más: `FirebaseApp.configure()` lo encuentra como recurso del
target. Si algún día cambia el proyecto o el bundle, se reemplaza ese
archivo por el nuevo de la consola.

## Versiones

La versión empieza en **1.0**. Funciones nuevas → 1.1, 1.2…; solo
arreglos → 1.0.1, 1.0.2… Cada release lleva su git tag (`v1.0`, `v1.1`…).
Al subir de versión: actualizar `CHANGELOG.md` (fecha + cambios) y
`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` en el proyecto. Los tags
se crean al subir el release por el navegador (desde aquí no se pueden
crear: la API de GitHub da 403 de escritura). La app muestra su versión
en Ajustes y el historial de versiones leyendo el `CHANGELOG.md` del
bundle, sin red.

## Compilar

- En Xcode 16+: abrir `Calcula/Calcula.xcodeproj`, elegir el esquema
  `Calcula` y compilar (las dependencias de Firebase se resuelven por SPM).
- En GitHub Actions: cada push a `main` compila el IPA sin firma y lo sube
  como artefacto `Calcula-IPA` (se instala con FlareStore / AltStore).
