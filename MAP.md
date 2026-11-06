# MAPA DE CALCULA — `psnlgastos-app/www/index.html`

> Fuente única: `~/workspace/psnlgastos-app/www/index.html` — **19.487 líneas, un solo archivo** (CSS en `<style>` líneas ~47–4670, HTML estático ~4670–4800, JS módulo ~4800–19487).
> Leído completo por secciones y verificado contra los `addDoc / setDoc / updateDoc / deleteDoc` y las funciones `render*` y de cálculo reales. Las referencias `Lxxxx` son líneas del archivo.
> Stack: Firebase JS SDK **11.10.0 por CDN** (`firebase-app.js`, `firebase-firestore.js`, `firebase-auth.js`), proyecto Firebase **`psnllega`**, sin backend propio, sin reglas de Firestore en este repo (no se pudieron verificar). Idioma UI: español (es-MX). PWA (`manifest.json`, `sw.js`) + Capacitor (app iOS, WebView).

---

## 1. MODELO DE DATOS FIRESTORE

### 1.1. Estructura general

- Raíz por usuario: **`users/{uid}/…`** — todo cuelga del UID de Firebase Auth. Helpers L5379–5385:
  - `userCol(name)` → `collection(db, "users", currentUser.uid, name)`
  - `userDoc(...parts)` → `doc(db, "users", currentUser.uid, ...parts)`
- **No hay subcolecciones anidadas** (todo es colección plana bajo `users/{uid}/` o documento en `settings/`).
- Colecciones bajo `users/{uid}/`: `accounts`, `movements`, `goals`, `budgets`, `scheduledPayments`.
- Documentos bajo `users/{uid}/settings/`: `profile`, `payroll`, `reminders` (un doc por nombre, sin colección de settings).
- Documento marcador: `users/{uid}/meta/ready`.
- **No existe** ninguna colección `recurring`, `recurringPayments`, `transactions`, `categories` ni `notifications`. Los pagos recurrentes viven en `scheduledPayments`; las categorías personalizadas viven dentro de `settings/profile.customCats`.
- Top-level (fuera de `users/`), solo leído en la migración legacy (ver §2): `meta/config`, y las colecciones legacy `accounts`, `movements`, `scheduledPayments`, `budgets`, `goals` y los docs `settings/{profile,payroll,reminders}` en la raíz de la BD.

### 1.2. `users/{uid}/accounts`

Creación en `openNewAccountModal()` L16422–16544 y en `finishOnboarding()` L6295–6312 (cuentas "Gastos"/"Ahorro" automáticas).

| Campo | Tipo JS | Obligatorio | Significado / valores |
|---|---|---|---|
| `name` | string | sí | Nombre visible ("Tarjeta Nu", "Netflix"). |
| `type` | string | sí | **Enum real: `"charges"` \| `"recurring"`**. OJO: en el wizard la opción "Sub" (`"subscription"`) **no se guarda como tal**: `storeType = type==="subscription" ? "recurring" : type` (L16405). Una suscripción es un `type:"recurring"` + `isSubscription:true`. |
| `isSubscription` | boolean | no (default ausente/`false`) | `true` solo si se creó como "Sub". Se lee en carrusel, calendario y `monthSpendByCategory`. |
| `iconSlug` | string | no (default `""`) | Slug de Simple Icons (ej. `"netflix"`). Vacío = sin icono de marca. |
| `iconHex` | string | no (default `""`) | Color hex de la marca, sin `#`. |
| `iconDomain` | string | no (default `""`) | Dominio para favicon de Google (`"netflix.com"`). Si hay `domain` y no `slug`, se usa favicon en vez de icono SVG. |
| `balance` | number | sí | Saldo pendiente (pesos). Para `charges` = saldo inicial del formulario; para `recurring` siempre `0`. **Se reescribe constantemente** (ver §4.7 y Dudas). Puede ser negativo = "saldo a favor". |
| `dueDay` | number | no (default `0`) | Día de pago mensual 1–31 para cuentas `charges`; `0` = "Sin fecha". Para `recurring` siempre `0`. |
| `createdAt` | Timestamp (serverTimestamp) | sí | Fecha de creación. |
| `sortOrder` | number | sí | Orden manual de tarjetas (0,1,2…). Lo asigna `nextAccountSortOrder()` = max+1. Sin él, `normalizeAccount()` pone `Number.MAX_SAFE_INTEGER`. |
| `categories` | string[] | no (default `[]`) | Categorías asociadas a la cuenta (elegidas con chips multi). Se usan como categoría por defecto del registro rápido. |
| `cardColor` | string | no | Hex sin `#` (ej. `"1a1a1e"`). Solo se escribe en las cuentas de onboarding, en `openAccountStyleModal()` / `openHomeCardsModal()` (`updateDoc {cardColor}`) y nunca en `openNewAccountModal()` — las cuentas creadas a mano **no tienen `cardColor`** y caen al fondo por defecto del CSS. |
| `hiddenFromHome` | boolean | no (default ausente = visible) | `true` = oculta del carrusel de inicio (pero sigue existiendo y aparece en quincenas/calendario). Solo se escribe vía `updateDoc {hiddenFromHome}`. |

Normalización al leer — `normalizeAccount()` L7364–7378: `type ||= "charges"`, `balance = Number(balance||0)`, `dueDay = Number(dueDay||0)`, `sortOrder` finito o `MAX_SAFE_INTEGER`, `categories` array o `[]`. **No normaliza** `cardColor`, `hiddenFromHome`, `isSubscription` ni `icon*`.

Consulta — `subscribeAccounts()` L9983–10070: `query(userCol("accounts"), orderBy("createdAt","asc"))`, luego orden en cliente con `sortAccounts()` (por `sortOrder` y desempate por `createdAt`). Es la suscripción que marca `initialized = true` y dispara `dismissSplash()`.

### 1.3. `users/{uid}/movements`

Creación solo vía `queueMovement()` L7324–7362 (la usan el registro rápido, el modal de movimiento y el pago de recurrente). **No hay edición de movimientos.**

| Campo | Tipo JS | Obligatorio | Significado / valores |
|---|---|---|---|
| `accountId` | string | sí | Id del doc en `accounts`. |
| `type` | string | sí | **Enum: `"cargo"` \| `"abono"` \| `"pago"`**. Se normaliza con `movementKind()` = `trim().toLowerCase()`. |
| `amount` | number | sí | Monto positivo, con 2 decimales (`parseMoneyInput`). El signo se deriva del tipo, no del valor. |
| `note` | string | sí (puede ser `""`) | Descripción libre, max 80 caracteres en el formulario rápido. En pagos programados es automático: `` `Pago: ${payment.name \|\| account.name}` ``. |
| `createdAt` | Timestamp (serverTimestamp) | sí | Fecha del movimiento; es la fecha que se muestra y por la que se ordena/filtra todo. |
| `category` | string | no | Categoría (`BUDGET_CATS` o personalizada). **Solo la escribe el registro rápido** (`extra:{category}` en `openQuickMovementModal()`). El modal de movimiento por cuenta (`openMovementModal()`) **no la escribe** → esos movimientos quedan sin categoría y caen en `"otros"` en presupuestos. |
| `scheduledPaymentId` | string | no | Id del doc en `scheduledPayments`. **Solo** en movimientos `type:"pago"` creados por `openPayScheduledModal()` L17244–17260. No se usa para ninguna consulta (no hay `where` sobre él). |

Semántica de tipos (L5492–5503, L7385–7392, L13900–13926):
- `cargo` → gasto: `movementDelta = +amount`; en UI se muestra con prefijo `+`, icono `↗`, clase `amount-cargo`. `isSpendMovement()` = `cargo` o `pago`.
- `abono` → pago a la cuenta de cargos (reduce saldo): `movementDelta = -amount`; prefijo `-`, icono `↓`, `amount-abono`.
- `pago` → pago de un recurrente: `movementDelta = 0` (no mueve ningún saldo); prefijo `-`, icono `✓`, `amount-pago`. Solo existe para el historial.

Consultas (tres suscripciones distintas sobre la **misma colección**, ver Dudas):
1. `subscribeAccountMovements(accountId)` L10306–10383: `query(userCol("movements"), where("accountId","==",accountId))` **sin `orderBy`**; orden en cliente por `createdAt` desc. Solo activa con una cuenta abierta.
2. `subscribeAllMovements()` L10415–10464: `query(userCol("movements"), orderBy("createdAt","desc"), limit(40))`; en cliente `applyAllMovements()` vuelve a ordenar desc y hace `.slice(0,40)`. Si esa query falla, reintenta con `onSnapshot(userCol("movements"))` sin orden ni límite. Alimenta "Últimos movimientos" del inicio (se muestran los primeros 10).
3. `subscribeBalanceSync()` L10466–10512: `onSnapshot(userCol("movements"))` **sin filtro, sin orden, sin límite** — descarga TODOS los movimientos. Construye `financeMovements` (todos los docs, sin slice) y `movementTotals` por cuenta; es la fuente de `sumSpend()` / presupuestos / gráfica de Finanzas.

Borrado — `openDeleteMovementModal()` L17302–17470: `deleteDoc(userDoc("movements", id))` y, solo si `type` es `cargo`/`abono`, revierte el `balance` de la cuenta (`cargo` resta, `abono` suma). Borrar un `pago` no toca saldos.

### 1.4. `users/{uid}/scheduledPayments`

Un doc por pago recurrente/suscripción. Se crea **junto con** su cuenta `type:"recurring"` en `openNewAccountModal()` L16468–16540; también lo crea `openDeferStudio(null)` para diferir una cantidad suelta (L19041). **No hay borrado individual**: solo se borran en cascada al eliminar la cuenta.

| Campo | Tipo JS | Obligatorio | Significado / valores |
|---|---|---|---|
| `accountId` | string | sí | Id de su cuenta `recurring`. Relación 1:1 en la práctica (el código siempre usa `.find(p => p.accountId===account.id)`, el primero). |
| `name` | string | sí | Nombre del pago ("Internet", "Netflix"). Puede diferir del nombre de la cuenta. |
| `amount` | number | sí | Monto de cada cobro. |
| `frequency` | string | sí | **Enum: `"weekly"` \| `"every15"` \| `"monthly"` \| `"bimonthly"` \| `"quarterly"` \| `"semiannual"` \| `"annual"` \| `"custom"`** (objeto `frequencies` L7434–7486: weekly=7 días, every15=15 días, monthly=1 mes, bimonthly=2, quarterly=3, semiannual=6, annual=12, custom=días libres). |
| `customDays` | number | no (default `30`) | Solo tiene efecto con `frequency:"custom"`. Se escribe siempre (30 por defecto). |
| `nextPayment` | Timestamp | sí | Próxima fecha de cobro. Se construye con `Timestamp.fromDate(new Date(dateString+"T12:00:00"))` (mediodía local para evitar problemas de zona horaria). Al pagar, avanza con `nextOccurrence()`. |
| `active` | boolean | sí (`true`) | Siempre `true` en todo el código: **ninguna UI lo pone en `false`**. |
| `kind` | string | sí | **Enum: `"payment"` \| `"subscription"`**. Duplica a `isSubscription` (ver Dudas). |
| `isSubscription` | boolean | sí | `true` si es suscripción. Duplica a `kind`. |
| `iconSlug` / `iconHex` / `iconDomain` | string | no (`""`) | Copia de los de la cuenta; se mantienen sincronizados en `openAccountStyleModal()` (`savePatch` actualiza ambos docs si cambia un icono). |
| `createdAt` | Timestamp (serverTimestamp) | sí | |
| `splitQuincenas` | number | no (default `1`) | En cuántas quincenas se reparte el pago (plan de diferir clásico). 1 = se paga completo. Clamp 1–12 (`getSplitCount()` L8377). |
| `splitParts` | number | no | Nuevo nombre del mismo concepto, escrito por `openDeferStudio()` junto a `splitUnit`. Se lee con fallback: `Number(payment.splitParts) \|\| Number(payment.splitQuincenas) \|\| 1` (L10985, L18898). |
| `splitUnit` | string | no | **Enum: `"week"` \| `"fortnight"` \| `"month"`**. Solo lo escribe `openDeferStudio()`. Si falta, se infiere `"fortnight"` cuando `splitQuincenas>1`. |
| `deferCustom` | boolean | no | `true` solo en los pagos creados por "Diferir una cantidad" (sin cuenta real: `accountId = accounts[0]?.id || ""`, `frequency:"annual"`, `kind:"payment"`). |

Actualizaciones: `updateDoc {nextPayment}` al pagar; `updateDoc {name, amount, frequency, nextPayment}` al editar (OJO: el edit **no** escribe `customDays`); `updateDoc {splitQuincenas}` en `openDeferPaymentModal()`; `updateDoc {splitParts, splitUnit, splitQuincenas}` en `openDeferStudio()`.

Consulta — `subscribeSchedules()` L10073–10136: `query(userCol("scheduledPayments"), where("active","==",true))`, orden en cliente por `nextPayment` asc (sin fecha = `Infinity`, al final). **No hay `orderBy` en Firestore.**

### 1.5. `users/{uid}/goals`

Creación/edición en `openGoalModal()` L6392–6565.

| Campo | Tipo JS | Obligatorio | Significado |
|---|---|---|---|
| `name` | string | sí | Nombre ("Viaje", "Enganche"). |
| `target` | number | sí | Meta total a ahorrar. |
| `saved` | number | sí | Apartado acumulado. `0` al crear; editable solo en el modal de edición; `openGoalAddModal()` hace `updateDoc {saved: saved + amount}` (L6860). |
| `cadence` | string | sí | **Enum: `"weekly"` \| `"fortnightly"` \| `"monthly"`** (aportaciones). Default: `profile.income` si es uno de esos tres, si no `"fortnightly"`. |
| `deadline` | Timestamp | sí | Fecha objetivo (`Timestamp.fromDate(new Date(dateString+"T12:00:00"))`). Al crear debe ser futura; al editar no se valida. |
| `createdAt` | Timestamp (serverTimestamp) | sí | Solo al crear. |

Consulta — `subscribeGoals()` L10286–10304: `onSnapshot(userCol("goals"))` sin orden ni filtro. Borrado: `deleteDoc` desde el modal y desde el menú nativo (`deleteGoalFromMenu()` L5201).

### 1.6. `users/{uid}/budgets`

Creación en `openBudgetModal()` L6326–6380. **No hay edición ni borrado en ninguna UI.**

| Campo | Tipo JS | Obligatorio | Significado |
|---|---|---|---|
| `name` | string | sí | Nombre libre ("Casa", "super"). |
| `amount` | number | sí | Tope mensual. |
| `category` | string | sí | Id de categoría de `BUDGET_CATS` o personalizada; default `"all"`. Un presupuesto por categoría en la práctica, pero nada impide duplicados (no hay validación). |
| `createdAt` | Timestamp (serverTimestamp) | sí | |

Consulta — `subscribeBudgets()` L10270–10284: `onSnapshot(userCol("budgets"))` sin orden ni filtro.

### 1.7. `users/{uid}/settings/profile`

Doc único `settings/profile`. Escrituras con `setDoc(..., {merge:true})` en: `finishOnboarding()` L6281, `addCustomCategory()` L5796 (solo `customCats`), y edición de perfil (reusa el onboarding con `editingProfile=true`).

| Campo | Tipo JS | Default en código | Significado / valores |
|---|---|---|---|
| `name` | string | `""` (o `displayName` de Auth) | Nombre para el saludo. |
| `income` | string | `"fortnightly"` | **Enum: `"daily"` \| `"weekly"` \| `"fortnightly"` \| `"monthly"`** (`INCOME_OPTIONS` L5577). Cadencia de ingresos; alimenta `incomeUnit()`, `periodsUntil()` y la cadencia por defecto de metas. |
| `currency` | string | `"MXN"` | **Enum: `"MXN"` \| `"USD"`**. |
| `colors` | string[] | `["111111"]` | Hasta 3 hex sin `#` elegidos en onboarding; `colors[0]` → `--accent`, `colors[1]` (o el mismo) → `--accent-2` (`applyTheme()` L5584). |
| `wants` | string[] | `[]` | **Enum de valores: `"charges"` \| `"savings"` \| `"subs"` \| `"recurring"`** (`WANT_OPTIONS` L5573). Solo se usa en `finishOnboarding()` para crear las cuentas "Gastos" (si `charges`) y "Ahorro" (si `savings`, con el segundo color). `"subs"` y `"recurring"` no crean nada. |
| `customCats` | objeto[] | `[]` | Categorías propias: `{id: string (slug), label: string}`. El `id` se genera con `slugCat()` (minúsculas, sin acentos, `-` como separador; si colisiona se añade sufijo `Date.now().toString(36)`). |
| `onboardingDone` | boolean | `false` | `true` = mostrar la app; `false` = mostrar el onboarding de 4 pasos. |

Lectura — `subscribeProfile()` L10223–10268: `onSnapshot(userDoc("settings","profile"))`; si no existe, perfil local por defecto con `onboardingDone:false`. OJO: si `editingProfile` está activo, el snapshot entrante **no** marca `onboardingDone` (para no cerrar el editor).

### 1.8. `users/{uid}/settings/payroll`

Doc único. Escritura con `setDoc` (sin merge, sobreescribe) en `openPayrollSettingsModal()` L18831.

| Campo | Tipo JS | Default | Significado |
|---|---|---|---|
| `payday1` | number | `15` | Día de la primera quincena, clamp 1–15 (`getPayrollSettings()` L8082). El select solo ofrece 1–15. |
| `payday2` | number | `30` | Día de la segunda quincena, clamp 16–31. Cuando `payday2LastDay` es true se guarda `30` como placeholder. |
| `payday2LastDay` | boolean | `true` | `true` = segunda quincena el último día del mes. |
| `updatedAt` | Timestamp (serverTimestamp) | — | Solo se escribe al guardar; no se lee nunca. |

### 1.9. `users/{uid}/settings/reminders`

Doc único. Escritura con `setDoc(..., {merge:true})` en `saveReminderSettings()` L9960–9981.

| Campo | Tipo JS | Default | Significado |
|---|---|---|---|
| `enabled` | boolean | `true` | Avisos dentro de la app activos. `data.enabled!==false` al leer. |
| `daysBefore` | number | `2` | Antelación en días. Se clamp a 1–7 en `reminderWindow()` (L9673); la UI solo alterna 1 ↔ 2. |

### 1.10. `users/{uid}/meta/ready` y `meta/config` (top-level)

- `users/{uid}/meta/ready`: `{ at: Timestamp (serverTimestamp) }`. Solo existe como marcador "migración hecha" (ver §2). No se lee su contenido.
- `meta/config` (top-level, fuera de `users/`): se lee `{ ownerUid: string }` en `ensureUserSpace()` L11882. Es el único campo usado: si `ownerUid === user.uid`, el usuario es el dueño legacy y se migran sus datos viejos.

### 1.11. Resumen de consultas (para replicar listeners en Swift)

| Suscripción | Colección/doc | Query Firestore | Orden |
|---|---|---|---|
| `subscribeAccounts` | `accounts` | `orderBy("createdAt","asc")` | Cliente: `sortOrder`, luego `createdAt` |
| `subscribeSchedules` | `scheduledPayments` | `where("active","==",true)` | Cliente: `nextPayment` asc |
| `subscribePayroll` | `settings/payroll` | doc directo | — |
| `subscribeReminders` | `settings/reminders` | doc directo | — |
| `subscribeProfile` | `settings/profile` | doc directo | — |
| `subscribeBudgets` | `budgets` | colección completa | Ninguno (orden no definido) |
| `subscribeGoals` | `goals` | colección completa | Ninguno |
| `subscribeAccountMovements` | `movements` | `where("accountId","==",id)` | Cliente: `createdAt` desc |
| `subscribeAllMovements` | `movements` | `orderBy("createdAt","desc"), limit(40)` (+ fallback sin orden) | Cliente: desc + slice 40 |
| `subscribeBalanceSync` | `movements` | colección completa, sin límite | — (agrega por `accountId`) |

`startData()` L11915 arranca las 9 suscripciones; `stopData()` L11932 las cancela todas y vacía los arrays en memoria. Cada `onSnapshot` llama a `renderAppOnly()` (re-render completo del HTML).

---

## 2. FLUJO DE AUTH

- **Firebase Auth, email + contraseña, sin proveedores sociales, sin recuperación de contraseña en la UI** (no hay "olvidé mi contraseña" en el código).
- SDK: `firebase-auth.js` 11.10.0. Persistencia (L5373–5377): `browserLocalPersistence` en web, **`inMemoryPersistence` en la app nativa** (porque IndexedDB "se atora" en WKWebView) → en la app nativa la sesión **no sobrevive a cerrar la app por completo**; hay que volver a entrar.
- **Login** — `renderLogin()` L11971: formulario correo + contraseña (mínimo 6 caracteres validado en cliente). `signInWithEmailAndPassword` con `withTimeout(..., 20000, "El inicio de sesión agotó el tiempo")` (L12037). Errores mapeados en `authErrorMessage()` L11829: `email-already-in-use`, `invalid-credential`/`wrong-password`/`user-not-found` → "Correo o contraseña incorrectos", `weak-password` → "Usa al menos 6 caracteres", `invalid-email`, `operation-not-allowed`.
- **Registro** — `renderSignup()` L12067, wizard de 3 pasos (`signupStep`, `signupDraft={name,email,password}`): 1) nombre (obligatorio), 2) correo (debe contener `@`), 3) contraseña (≥6). Al final `createUserWithEmailAndPassword` + `updateProfile(cred.user, {displayName: name})` y `profile.name = name` en memoria. Sin verificación de correo.
- **`onAuthStateChanged`** L12311–12347 (el punto de entrada real de la app):
  1. `currentUser = user; authReady = true`.
  2. Si no hay usuario → `stopData()` y `renderLogin()` (cuando el splash ya pasó).
  3. Si hay usuario → `ensureUserSpace(user)` con timeout de **15 s** (`withTimeout`, L12322). Si falla o agota el tiempo → **no bloquea**: entra igual con datos locales y toast "No se pudo preparar tu cuenta, entrarás con tus datos locales"; se reintentará en el próximo inicio.
  4. `applyCloudSyncPreference()` → `startData()` (9 suscripciones) → `scheduleFirstDataWatchdog()` (20 s, ver abajo).
  5. Si es app nativa + Face ID activo + no desbloqueado en esta sesión → `nativeLocked = true` (pantalla de bloqueo, §7).
  6. Si el splash ya pasó → `renderAppOnly()`.
- **`ensureUserSpace(user)`** L11873–11913:
  1. Lee `users/{uid}/meta/ready`. Si existe → `return true` (nada más que hacer).
  2. Si no existe: lee `meta/config` (top-level). Si `config.ownerUid === user.uid` → **migración legacy**: copia con `writeBatch` (lotes de 400) las colecciones top-level `accounts`, `movements`, `scheduledPayments`, `budgets`, `goals` a `users/{uid}/<misma>` conservando los mismos IDs (`copyLegacyCollection()` L11853), y copia los docs `settings/{profile,payroll,reminders}` top-level a `users/{uid}/settings/...`. Los datos legacy **no se borran**.
  3. Escribe `users/{uid}/meta/ready = {at: serverTimestamp()}` y `return true`.
- **Cierre de sesión**: `signOut(auth)` desde Ajustes → `onAuthStateChanged` con `user=null` → `stopData()` (vacía todo, resetea `nativeLocked`, `firstDataWatchdogDone`, etc.) → login.
- **Watchdog de primeros datos** — `scheduleFirstDataWatchdog()` L5354: a los **20 s** de arrancar, si `initialized` sigue falso (el primer `onSnapshot` de cuentas no llegó), pinta la app con lo que haya en local y muestra "Sin conexión con la nube, mostrando los datos guardados en el teléfono". Es un parche al problema de Firestore sin respuesta.
- **Watchdog de arranque** (script clásico al final del body, L19420+): si a los **12 s** el módulo no puso la clase `calcula-booted` (el import de Firebase del CDN murió), oculta el splash y muestra "No se pudo cargar Calcula. Revisa tu conexión a internet y recarga la página."
- **Token para Atajos** — `copyAuthToken()` L12276 (Ajustes → Sistema → "Acceso para Atajos"): copia al portapapeles `API_KEY=<apiKey>\nREFRESH_TOKEN=<refreshToken del usuario>` con el texto "Copiado. Este acceso no caduca". En Swift: es un dato sensible; no replicar el copiado literal sin revisar con Jesus (ver Dudas).
- **Splash**: mínimo 3.400 ms (900 ms con `prefers-reduced-motion`), máximo forzado 7.000 ms (`setTimeout(dismissSplash, 7000)`). Luego `paintAfterSplash()`: sin usuario → login; sin `initialized` → skeleton; si no → app. Si no es app standalone y no se ha saltado, se muestra el "install coach" de iOS ("Agregar a inicio") antes de pintar.

---

## 3. PANTALLAS Y NAVEGACIÓN

No hay router ni URLs: todo es **un solo render** (`renderApp()` L12794) con estado en variables de módulo. La navegación es por `currentTab` + pantallas superpuestas (`openAccountId`, `openQuincenaKey`) + modales (`.overlay`, `createModal()`).

### 3.1. Tabbar (siempre visible salvo onboarding, cuenta abierta, quincena abierta o modal)

`renderTabbar()` L10832. 4 pestañas + botón central `+` (FAB duplicado: hay también un `#fab` fijo que abre lo mismo):
- **Inicio** (`tab-home`, `currentTab="home"`) — icono casa.
- **Diferir** (`tab-quincena`, `currentTab="quincena"`) — icono calendario. OJO: la pestaña se llama "Diferir", no "Quincenas".
- **`+`** (`quick-add`) — abre el Registro rápido (no cambia de tab).
- **Finanzas** (`tab-finance`, `currentTab="finance"`) — icono gráfica.
- **Calendario** (`tab-calendar`, `currentTab="calendar"`) — icono calendario con puntos.

`switchTab(tab)` L12732: cambia `currentTab`, re-renderiza y sube arriba (`goTop`). No hay pestaña de "Cuentas" ni de "Movimientos" como tal.

### 3.2. Inicio (`currentTab="home"`, `renderApp()` L12860+)

- **Topbar** (`renderTopbar()` L10783): saludo animado ("Buenos días/tardes/noches, {primer nombre}" 2.400 ms, luego logo `calcula-wordmark.png`; se repite si la app estuvo oculta >25 s o con `pageshow`), botón buscar (lupa) y botón ajustes (engrane).
- **Total pendiente**: suma de `max(0, balance)` solo de cuentas `type:"charges"` (L12890). Subtítulo: "N cuentas". Si no hay cuentas: estado vacío con botón "Crear cuenta".
- **Banner de recordatorios** (`renderReminderBanner()`): lista "Por pagar" (ver §4.6).
- **Carrusel de tarjetas** (`renderCarousel()` L12949): una tarjeta por cuenta visible (`hiddenFromHome!==true`), deslizable (drag horizontal, dots, flechas ‹ › en modo reordenar). Cada tarjeta muestra: nombre, tipo ("Subscripción" / "Pago recurrente" / "Cargos y abonos"), saldo o próximo pago, estado ("Pagar el día X · esta quincena", "Cuenta liquidada", "Tienes saldo a favor", "Apartar $X esta quincena"…). Tocar una tarjeta abre su pantalla de cuenta. En modo reordenar (flechas) se puede cambiar el orden y guardar/cancelar (ver §7).
- **"Para estar al día"** (`renderQuincenas()` L13713): dos tarjetas de quincena — **Esta quincena** (fondo oscuro, `is-current`) y **Siguiente quincena** — cada una con: "Nómina del {fecha}", "Cubre {rango}", "{fromPayroll} de tu nómina", "Pagar ahora {toPay}" / "Apartar {toSetAside}", y la lista compacta de ítems. Tocar abre la pantalla de quincena. Botón "Nómina" → modal de nómina.
- **Próximos pagos** (`renderUpcoming()` L13762): los primeros 5 `scheduledPayments` (ordenados por `nextPayment`), con icono `!` si vencido o `↗`, fecha y botón "Pagar".
- **Últimos movimientos** (`renderHomeMovements()` L14013): los primeros 10 de `allMovements` (con nombre de cuenta, sin botón de borrar).
- Extras: pull-to-refresh (arrastrar desde arriba en Inicio recarga la página), botón flotante "Volver arriba" (solo al final de la página y en Inicio), búsqueda global (ver §3.7).

### 3.3. Diferir (`currentTab="quincena"`, `renderDeferTab()` L10955)

- Hero: "Reparte un pago" + texto explicativo.
- Botón "Diferir una cantidad" → `openDeferStudio(null)` (crea un `scheduledPayments` nuevo, §4.5).
- Lista de todos los `scheduledPayments` con `nextPayment`, ordenados por fecha: nombre, fecha corta, cuenta, monto y, si ya tiene plan, "Apartas en N quincenas/semanas/meses". Tocar uno → `openDeferStudio(id)`.

### 3.4. Finanzas (`currentTab="finance"`, `renderFinance()` L11229)

- Hero: "Gastado {hoy/esta semana/este mes/este año}" = `sumSpend` del periodo; delta vs periodo anterior ("% más/menos que…", "Sin cambios", "Nuevo gasto").
- Selector de periodo: Día / Semana / Mes / Año (`financePeriod`, default `"month"`).
- Gráfica de barras (`financeBuckets()`): día/semana → 7 barras por día (etiqueta día de semana, 1 letra); mes → una barra cada 1–2 días (etiqueta número de día); año → 12 barras por mes. Altura proporcional al máximo; la barra actual marcada `is-now`.
- **Presupuestos del mes** (`renderBudgetList()`): tarjeta por presupuesto con categoría, %, `gastado / tope` y barra (`.meter` con niveles `warn` ≥80% y `hot` ≥100%). Botón "Nuevo presupuesto".
- **Metas de ahorro** (`renderGoalList()`): tarjeta por meta con `ahorrado / objetivo`, "N {quincenas} · $X c/u" y barra de %. Botones "Apartar" y "Editar" por meta; "Nueva meta". Tocar la tarjeta → detalle de meta (anillo de %, "Juntado / de / Resta / Cada X / Fecha", botones Compartir / Apartar / Editar).

### 3.5. Calendario (`currentTab="calendar"`, `renderCalendar()` L9333)

- Mes navegable (‹ ›), título "mes año" en español.
- Filtros con contador: Todas / Subscripciones / Semanales / Cargos (categorías de `eventCategory()`).
- Rejilla L–D (lunes primero, `firstDow = (getDay()+6)%7`); cada día muestra hasta 4 puntos de color (color de la tarjeta de la cuenta; 5+ → 3 puntos + "+").
- Debajo: "Pagos del {día}" con nombre, tipo y monto; si es hoy y no hay pagos, muestra el próximo pago; si no, "No hay pagos este día".
- Los eventos vienen de `getCalendarEvents()` (recurrentes por `occurrencesInRange` + cargos con `dueDay`).

### 3.6. Pantallas superpuestas (no son tabs)

- **Pantalla de cuenta** (`renderAccountScreen()` L14271, `openAccountScreen()` L14067): se abre tocando una tarjeta, desde búsqueda o desde el menú nativo. Cubre toda la pantalla (el tabbar se oculta, clase `body.account-open`). Hero con el color de la tarjeta, monto grande (saldo o próximo pago), pista de frecuencia/día de pago, botones: recurrente → "Registrar pago"; cargos → "+ Cargo" y "Abono"; lápiz → modal de estilo de tarjeta. Debajo: lista completa de movimientos de esa cuenta (con botón × para borrar). Se cierra con ← o con gesto de borde izquierdo (deslizar desde x<28). Al abrir se suscribe `subscribeAccountMovements(id)`; al cerrar se cancela.
- **Pantalla de quincena** (`renderQuincenaScreen()` L14141, `openQuincenaScreen(which)`): "Esta quincena" o "Siguiente quincena". Hero con `fromPayroll`, "Pagar ahora" / "Apartar". Dos secciones: "Pagos de esta quincena" (ítems `isDue`, con marca circular para pagar/abonar y botón "Pagar"/"Abonar"/"Diferir") y "Apartar" (ítems futuros). Botón "···" → nómina. Misma lógica de cierre por gesto que la cuenta.
- **Onboarding** (`renderOnboarding()` L11091): 4 pasos si `profileLoaded && !profile.onboardingDone`: 1) ¿Cada cuándo te pagan? (burbujas daily/weekly/fortnightly/monthly), 2) ¿En qué moneda? (MXN/USD), 3) Elige tus colores (paleta de 20 + color propio, máx. 3), 4) ¿Qué cuentas quieres? (burbujas multi: charges/savings/subs/recurring) + nombre opcional. Barra inferior Atrás/Siguiente/Empezar. "Cancelar" en el paso 0 también termina el onboarding (guarda lo que haya). Reutilizado como editor de perfil (`editingProfile=true`, con botón "Toca aquí para salir del editor").
- **Login / Registro**: ver §2.
- **Búsqueda global** (`openSearch()` L12515, capa `#searchLayer` fija): busca por texto o monto exacto en cuentas (nombre), pagos (nombre o monto), metas (nombre) y movimientos (nota, categoría, cuenta, tipo o monto); máx. 40 resultados. Tocar un resultado abre la cuenta o la meta correspondiente.

### 3.7. Ajustes (modal, `openSettingsModal()` L11322)

Secciones acordeón (una abierta a la vez): **Cuentas** (Nueva cuenta / Tarjetas del inicio / Orden de tarjetas), **Dinero** (Mi perfil / Nuevo presupuesto / Nueva meta), **Apariencia** (Modo nocturno), **Recordatorios** (Activar / Antelación 1–2 días / Avisos en la app / Agregar a Calendario / Avisos fuera de la app), **Exportar** (CSV mes / CSV quincena), **Sincronización** (estado + interruptor nube + "Sincronizar ahora"), **Seguridad** (Bloquear con Face ID), **Sistema** (Actualizar app / Acceso para Atajos). Al final: "Cerrar sesión". Cada fila ejecuta su acción directamente (ver §5 y §7).

### 3.8. Modales (todos vía `createModal()`, hoja inferior redondeada; Esc o tocar fuera cierra, salvo wizard)

- Nueva cuenta (wizard 5 pasos), Registro rápido (FAB / `+`), Agregar cargo / Registrar abono, Marcar pago (pago recurrente), Eliminar movimiento, Eliminar cuenta (con borrado en cascada por batches de 450), Nueva meta (wizard 4 pasos), Detalle de meta, Apartar a meta, Nuevo presupuesto, Editar pago / Editar cuenta de cargos, Tarjeta (color/icono/visibilidad/editar/eliminar), Tarjetas del inicio, Organizar cuentas, Tu nómina, Diferir (studio: unidad + nº de pagos + vista previa) y Diferir pago (clásico, en quincenas), confirmación genérica (`askConfirm()`), toast (`showToast()`, 3.200 ms).

---

## 4. REGLAS DE NEGOCIO

### 4.1. Fechas y formato

- `dateValue(v)` (L6959): acepta `Timestamp` de Firestore (`.toDate()`), `Date` o string/number (`new Date(v)`); inválido → `null`. Es el conversor universal.
- `formatDate` (L6984): `es-MX`, día numérico + mes corto + año ("5 dic 2026"). `formatShortDate`: día + mes corto. `goalDateLabel`: día + mes largo + año. `paydayLabel`: día + mes corto.
- `dateDescription(v)` (L8051): relativo por días: "Vencido ayer / Vencido hace N días", "Hoy", "Mañana", "En N días" (<7), si no fecha corta.
- `daysUntil(v)`: días enteros entre hoy (00:00) y la fecha (00:00), redondeado.
- Todas las fechas de entrada de formularios se construyen como `new Date(dateString+"T12:00:00")` (mediodía local) para que la zona horaria no mueva el día. Las fechas de `nextPayment` se guardan como `Timestamp.fromDate`.
- `startOfDay(v)`: fecha a las 00:00 locales. `lastDayOfMonth(y,m)`: `new Date(y, m+1, 0).getDate()`.
- Moneda — `money(value)` (L5476): `Intl.NumberFormat` con `currency: profile.currency==="USD" ? "USD" : "MXN"`, locale `en-US` para USD y `es-MX` para MXN, siempre 2 decimales. Entrada de montos: `parseMoneyInput()` acepta `$`, comas de miles y coma decimal, redondea a centavos; `formatMoneyInput()` agrupa miles con comas (`10,000.00`); `bindMoneyInput()` formatea mientras se escribe (inputmode decimal, máx. 2 decimales).

### 4.2. Quincenas / nómina

- Config: `settings/payroll` → `getPayrollSettings()` (L8082): `payday1` clamp 1–15 (default 15), `payday2` clamp 16–31 (default 30), `payday2LastDay` default `true`.
- `makePayday(y, m, which)` (L8132): quincena 1 = día `payday1` (limitado al último día del mes); quincena 2 = último día del mes si `payday2LastDay`, si no día `payday2` (limitado al último día).
- `getQuincenaWindows(now)` (L8178): genera los días de pago de 15 meses (de -4 a +10 meses respecto al mes actual), los ordena, quita duplicados, y forma ventanas `[payday_i, payday_{i+1})`. **Una "quincena" es el periodo que empieza en un día de pago y termina en el siguiente** (el dinero de esa nómina cubre hasta la siguiente).
- `getCurrentAndNextWindows()` (L8261): ventana actual = la que contiene a hoy (`start <= hoy < end`); si no hay, la primera que termina después de hoy. Devuelve `{current, next, windows, currentIndex}`.
- Etiquetas: `windowRangeLabel` = "15 dic – 30 dic"; `paydayLabel` = "15 dic".
- **No hay monto de nómina en ningún sitio**: la app nunca pregunta cuánto se gana; "de tu nómina" es solo `fromPayroll` = suma de lo que hay que pagar/apartar en esa ventana (ver §4.3). No hay salario, deducciones ni ingreso registrado.

### 4.3. Plan de quincena (el cálculo central) — `buildQuincenaPlan(window, context)` L8644–8942

Para cada ventana, con `today = startOfDay(hoy)`:

1. **Pagos recurrentes** (`scheduledPayments`, solo con cuenta existente y `amount>0`): se expanden sus ocurrencias con `occurrenceDates()` (desde `nextPayment`, avanzando con `nextOccurrence()` según frecuencia, máx. 24 ocurrencias, hasta el final de la última ventana conocida).
2. Cada ocurrencia se asigna a su ventana (`findWindowIndex`). Si está **vencida** (`due < hoy`), solo contribuye a la ventana actual (y se marca `overdue`). Si no, contribuye a las últimas `split` ventanas antes de su vencimiento: `startIndex = max(currentIndex, dueIndex-(split-1))`, donde `split = getSplitCount(payment)` (1–12, de `splitQuincenas`). El aporte por quincena es **`share = amount / nº de ventanas contribuyentes`** (reparto equitativo, sin intereses ni redondeo especial).
3. Un ítem es **`isDue`** si su vencimiento cae dentro de esta ventana (o si está vencido y esta es la ventana actual). Si no, es "apartar": se muestra `share` con etiqueta `Apartar {installment}/{split}`.
4. **Cuentas de cargos** (`type:"charges"` con `balance>0` y `dueDay`): `resolveChargeDue()` busca el último vencimiento (si cayó en la ventana actual → `overdue:true`) o el próximo; el saldo completo (`balance`) entra como un ítem `kind:"charges"` con `share = amount = balance`, `split:1`, en su ventana objetivo. Si la cuenta no tiene `dueDay`, **no aparece en ninguna quincena** (aunque tenga saldo).
5. Totales del plan: `toPay` = suma de `amount` de ítems `isDue`; `toSetAside` = suma de `share` de ítems no vencidos; `fromPayroll` = suma de **todos** los `share` (= `toPay + toSetAside` solo si cada ítem vencido tiene `share == amount`, que es el caso general: en un ítem `isDue` de pago recurrente, `share` es la parte de esa quincena, no el total — ver Dudas).
6. Orden: primero los `isDue`, luego por fecha de vencimiento.
7. `compactQuincenaItems()` (L8430) agrupa por pago/cuenta para la vista compacta de la tarjeta (suma `share`, cuenta `dueCount`, conserva `unitAmount`).
8. `isNextPayable(item)` (L8481): un ítem recurrente vencido solo se puede pagar si su `due` es el `nextPayment` actual del pago (evita pagar la 2ª ocurrencia antes que la 1ª). Si no, el botón sale bloqueado ("Paga el anterior primero").

**Motor duplicado (ver Dudas):** existe un segundo motor, `buildSavePlan()` L9014 + `saveIndexesForDue()` L8992 + `getMonthSavePlans()` L9122, que reparte cada pago solo entre la quincena anterior y la del vencimiento (`[dueIndex-1, dueIndex]`), y un estado `quincenaMonth` con acción `quincena-month`. **Nada de eso se usa en ningún render**: `getMonthSavePlans` no tiene llamadas y no hay UI que emita `quincena-month`.

### 4.4. Pagar / abonar

- **Pagar recurrente** (`openPayScheduledModal()` L17102): crea un movimiento `type:"pago"` (no mueve saldos) con `scheduledPaymentId`, y avanza `nextPayment` con `nextOccurrence()` (según frecuencia). Si hay varias ocurrencias vencidas, paga la próxima (`isNextPayable`); el texto muestra "Pago N de M" si aplica.
- **Abono a cuenta de cargos** (`openMovementModal(id, "abono")`): movimiento `type:"abono"` → `queueMovement()` resta el monto del `balance` de la cuenta.
- **Cargo** (`type:"cargo"`): suma al `balance`.
- `queueMovement()` (L7324): `addDoc(movements, {...})` y, solo para `cargo`/`abono`, `updateDoc(accounts/{id}, {balance: nuevo})` calculado en cliente desde el `balance` en memoria (sin transacción; ver Dudas).
- Al borrar un movimiento se revierte el `balance` del mismo modo (L17409).

### 4.5. Diferir (dos UIs, un mismo campo)

- **Regla de elegibilidad** — `canDeferPayment()` (L9652): solo si el vencimiento está **más allá de la quincena siguiente** (`dueIndex > currentIndex+1`). Si toca esta quincena o la siguiente: "Este pago ya toca esta quincena o la siguiente. No se puede diferir."
- **Diferir clásico** — `openDeferPaymentModal()` (L19069): elige en cuántas quincenas (1, 2, 3, 4, 6) con vista previa de `splitPreview()` (L9545: si está vencido, todo esta quincena; si `dueIndex <= currentIndex+1`, "No se puede diferir"). Guarda solo `updateDoc {splitQuincenas: n}`.
- **Diferir studio** — `openDeferStudio(paymentId?)` (L18880): unidad Semanas/Quincenas/Meses + nº de pagos (2, 3, 4, 6, 8, 12). `deferPlan(amount, due, parts, unit)` (L10926): reparte `amount/parts` en fechas hacia atrás desde el vencimiento (`week` = -7 días por paso, `month` = -1 mes, `fortnight` = -15 días), máx. 24 partes, mín. 2; si la primera fecha cae antes de hoy → error "Eso empezaría antes de hoy". Guarda `updateDoc {splitParts, splitUnit, splitQuincenas: unit==="fortnight" ? parts : 1}`. Sin pago existente ("Diferir una cantidad") crea un `scheduledPayments` nuevo con `frequency:"annual"`, `customDays:30`, `kind:"payment"`, `isSubscription:false`, `deferCustom:true`, `accountId` = primera cuenta (o `""`).
- Efecto real del diferir: solo cambia `splitQuincenas`/`splitParts`/`splitUnit`, que `buildQuincenaPlan()` usa para repartir el `share` entre quincenas. No crea movimientos ni aparta dinero de verdad.

### 4.6. Presupuestos

- `monthSpendByCategory(category)` (L6032): suma `spendAmount()` (solo `cargo` y `pago`) de `allMovements` (o `financeMovements`) con `createdAt` dentro del mes actual; categoría = `movement.category || "otros"`; `"all"` suma todo; `"subs"` suma además los movimientos cuya cuenta sea `isSubscription` o `type:"recurring"`.
- `budgetStatus(budget)` (L6054): `{spent, cap, pct: min(100, round(spent/cap*100)), level}`; `level = "hot"` si pct ≥ 100, `"warn"` si ≥ 80, `""` si no. El modal dice "Al 80% te aviso", pero **no hay ninguna notificación ni aviso al llegar al 80%**: solo cambia el color de la barra.
- Los presupuestos son mensuales y se reinician solos porque el cálculo siempre es del mes en curso. No hay arrastre ni historial.

### 4.7. Metas

- `goalStatus(goal)` (L6078): `saved`, `target`, `left = max(0, target-saved)`, `periods = periodsUntil(deadline, cadence)`, `each = left/periods`, `pct = min(100, round(saved/target*100))`.
- `periodsUntil(deadline, cadence)` (L6065): días restantes (mín. 1) → `daily` = días; `weekly` = ceil(días/7); `monthly` = ceil(días/30); resto (fortnightly) = ceil(días/15).
- `goalTips()` (L6105): textos ("Llevas el X% · faltan $Y", "Aparta $Z cada quincena…", aviso si quedan ≤2 periodos, sugerencia de alargar 2 periodos más). Si `left<=0`: "Ya juntaste el monto…".
- "Apartar" solo suma al campo `saved` (no crea movimiento ni mueve dinero de ninguna cuenta). El anillo de detalle usa `stroke-dashoffset = 201 * (1 - pct/100)` (radio 32).
- Compartir: `shareGoalCard()` → `drawGoalShareImage()` dibuja un PNG 1080×1350 en canvas (fondo `#111114`, anillo, 4 datos, marca `calcula-wordmark.png` invertida) y usa `navigator.share({files})` o descarga el PNG.

### 4.8. Totales y saldos

- **Total de Inicio** = suma de `max(0, balance)` de cuentas `charges` (los negativos no restan).
- **Saldo de cuenta** = campo `balance` en Firestore. Hay **dos escritores** que compiten (ver Dudas): (a) `queueMovement()` / borrado de movimiento: ajuste incremental en cliente; (b) `applyBalanceSync()` (L7394): recomputa `balance = Σ movementDelta` por cuenta (cargo +, abono −, pago 0) desde `subscribeBalanceSync()` y lo sobrescribe con `updateDoc` si difiere ≥ $0.01 (con guarda `lastSyncedBalance` para no reescribir lo mismo). Las cuentas `recurring` se saltan en (b).
- **Gastado en Finanzas** (`sumSpend`, L5546): suma `spendAmount` (cargo + pago, **no abono**) de `financeMovements` en el periodo. Periodos (`periodBounds()` L5505): día = hoy 00:00–mañana; semana = lunes–domingo (lunes = `(getDay()+6)%7`); mes = día 1–día 1 del mes siguiente; año = 1 ene–1 ene. Siempre se compara también con el periodo anterior para el delta.
- **Exportar CSV** (`exportMovements()` L6164): columnas Fecha, Cuenta, Tipo, Monto, Nota, Categoría; filas del mes o de la quincena actual; archivo `calcula-mes.csv` / `calcula-quincena.csv` con BOM UTF-8.

### 4.9. Pagos recurrentes y programados (cálculo de fechas)

- `nextOccurrence(date, frequency, customDays=30)` (L7904) / `prevOccurrence` (L7970): `days` → suma días; `months` → suma meses conservando el día (limitado al último día del mes destino); `custom` → suma `customDays`; frecuencia desconocida → ±7 días.
- `occurrenceDates(payment, until)` (L8335): ocurrencias desde `nextPayment` hasta `until`, máx. 24, normalizadas a las 12:00.
- `occurrencesInRange(payment, from, until)` (L9161): como el anterior pero buscando también hacia atrás (máx. 40 pasos en cada dirección), para el calendario.
- **Vencido** = `nextPayment < ahora` (`isOverdue()`). En quincenas, un vencido se cobra completo en la ventana actual (no se divide).

### 4.10. Recordatorios

- `upcomingReminderItems()` (L9686): si `reminderSettings.enabled` es falso → `[]`. Si no, junta: (a) `scheduledPayments` con `0 <= días hasta nextPayment <= daysBefore`; (b) cuentas `charges` con saldo > 0 y `dueDay`, con su próximo vencimiento en ventana; (c) la próxima nómina (`context.current.payday`) si cae en ventana. Orden por días, luego nombre. IDs: `"pay-"+id`, `"charge-"+id`, `"payroll-"+timestamp`.
- `reminderWindow()` = clamp(`daysBefore`, 1, 7), default 2.
- Dentro de la app: `renderReminderBanner()` en Inicio + `maybeNotifyReminders()` (L9934): toast "Pagos por venir" **una vez al día por combinación** (guarda `calcula-reminded` = stamp de ítems + fecha; ver §5). `requestReminderPermission()` (L9925) no pide permiso de verdad: solo muestra "Los avisos salen dentro de Calcula, no en el iPhone" y llama a `maybeNotifyReminders()`.
- Fuera de la app: notificaciones locales nativas (§7) y exportar `.ics` — `buildPaymentsCalendar()` (L9824): eventos 6 meses hacia adelante (recurrentes por `occurrenceDates` + cargos 8 ocurrencias), con alarma `TRIGGER:-P{daysBefore}D`, archivo `calcula-pagos.ics`, `PRODID:-//Calcula//STUDI05//ES`.

---

## 5. ESTADO SOLO-LOCAL (localStorage y memoria)

### 5.1. Claves de `localStorage` (todas string `"1"`/`"0"` o valor directo)

| Clave | Dónde | Significado |
|---|---|---|
| `calcula-cloud-sync` | L4914, L4963 (`CLOUD_SYNC_KEY`) | `"0"` = nube apagada (`disableNetwork(db)`; los datos se guardan solo en el caché local de Firestore). Cualquier otro valor (incluido ausente) = sincronizar. Interruptor en Ajustes → Sincronización. |
| `calcula-faceid-lock` | L5222, L5226 (`FACEID_KEY`) | `"1"` = bloqueo con Face ID activo. |
| `calcula-reminders` | L5276, L5280 (`NATIVE_REMINDERS_KEY`) | `"1"` = notificaciones locales nativas activas. |
| `calcula-dark` | L5441, L11683 | `"1"` = modo oscuro (`body.dark`). |
| `calcula-install-skip` | L7166, L7184 | `"1"` = el usuario descartó el coach "Agregar a inicio" (no volver a mostrarlo). |
| `calcula-reminded` | L9945, L9948 | Stamp `id-fecha|id-fecha-YYYYMMDD` del último toast de recordatorios mostrado; evita repetir el aviso el mismo día para los mismos ítems. |

No hay ninguna otra clave: ni token, ni último tab, ni cuenta seleccionada, ni borradores de formularios. Todo lo demás es Firestore o memoria volátil.

### 5.2. Estado solo en memoria (se pierde al recargar; variables de módulo L5389–5460)

- Datos: `accounts`, `scheduledPayments`, `movements` (de la cuenta abierta), `allMovements` (últimos 40), `financeMovements` (todos, de `subscribeBalanceSync`), `budgets`, `goals`, `profile`, `payrollSettings`, `reminderSettings`, `movementTotals`, `lastSyncedBalance`.
- UI: `currentTab` (`"home"`), `financePeriod` (`"month"`), `selectedIndex` (tarjeta del carrusel), `openAccountId`, `openQuincenaKey`, `quincenaMonth`, `calendarMonth`, `calendarCategory` (`"all"`), `calendarSelected`, `onboardStep`, `editingProfile`, `authView` (`"login"`), `signupStep`, `signupDraft`, `greetingPhase`, `darkMode`, `submitting`, `modal`, `initialized`, `profileLoaded`, `dataStarted`, `authReady`.
- Nativo: `nativeLocked`, `nativeLockAttempted`, `nativeUnlockedThisSession`, `nativeRemindersStamp`, `cloudSyncEnabled`, `syncInSync`.
- Caché de Firestore: en web `persistentLocalCache` con `persistentMultipleTabManager` (IndexedDB, multi-pestaña); **en app nativa `initializeFirestore` sin caché persistente** (caché en memoria) porque IndexedDB se atasca en WKWebView — por eso también la Auth es `inMemoryPersistence` en nativo.

---

## 6. DISEÑO

- **Paleta (no hay dorado ni beige en esta app; es monocromo + colores de tarjeta elegidos por el usuario)**:
  - Variables CSS (`:root`, L47–51): `--accent:#111111` (negro, se sobrescribe con el color del perfil vía `applyTheme()`), `--accent-2:#3f3f46`, `--skeleton-color:#e6e6ea`.
  - Fondo claro: `#e7e7ee` con 3 gradientes radiales (`--accent` 32%, `--accent-2` 24%, `rgba(210,230,255,.22)`). Texto `#111`. Secundario `#8b8b91`, `#6b6b73`, `#999`, `#888`.
  - Fondo oscuro (`body.dark`, L3140+): `#111114` con gradientes `rgba(90,110,170,.22)` y `rgba(90,50,80,.18)`; texto `#f5f5f7`; secundarios `#c9c9d1`; superficies `rgba(22,22,28,.82)` / `rgba(255,255,255,.08)`.
  - Botón primario: fondo `#111` / texto blanco en claro; invertido en oscuro (`#f5f5f7` / `#111`). Peligro: `#d22` / `#d63a3a` (claro), fondo `#3a1d1d` + texto `#ff8d8d` (oscuro). Éxito/abono: `#159447`.
  - Tarjetas de cuenta: gradiente `linear-gradient(145deg, #<cardColor>, #<cardColor oscurecido 45%>)` + brillo radial blanco 16% (`cardPaint()`, L7300; `shadeHex(hex, .45)`). Por defecto `#242428 → #080808`; recurrentes `#38383d → #151517`. Texto blanco.
  - "Vidrio líquido" solo en oscuro y solo en superficies flotantes (L4625+): topbar, `.tabbar-pill` y `.modal` con `backdrop-filter: blur(20–32px) saturate(180–200%)`, borde claro y brillo interior. Explícitamente no se aplica a tarjetas ni listas (rendimiento).
- **Tipografía**: `-apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", Inter, Arial, sans-serif`. Total grande: 38px, peso 750, tracking -1.8px. Nombre de tarjeta: 18px/700. Títulos de sección: peso 700. Tabbar: 9px/750. Sin fuentes externas (todo sistema).
- **Layout**: `.app` máx. **680px** centrado, padding lateral 18px + safe-areas; fondo con overscroll desactivado; zoom bloqueado (`maximum-scale=1, user-scalable=no`, más listeners anti-doble-tap y anti-gesto).
- **Topbar**: 54px, marca a la izquierda (saludo o wordmark), 2 botones circulares 42px (`icon-btn`, fondo blanco, sombra suave) a la derecha.
- **Tabbar**: fija abajo (`bottom: max(10px, safe-area)`), píldora `width: min(470px, 100%-20px)`, `border-radius:999px`, fondo `rgba(255,255,255,.58)` + `blur(28px) saturate(190%)`, borde blanco 55%, sombra. Items 50px con icono 18px + etiqueta 9px; activo = fondo blanco 72% + sombra. Botón central `+` de 48px, fondo `--accent`, sombra.
- **Tarjetas de cuenta**: `min-height:230px`, `border-radius:29px`, padding 23px, sombra `0 18px 40px rgba(0,0,0,.16)` + brillo interior. Carrusel a pantalla completa con peek 0 (una tarjeta visible), dots, flechas de reordenar.
- **Heroes y tarjetas de contenido** (`.finance-hero`, `.finance-card`, `.period-switch`, `.quincena-card`): fondo blanco 50% + blur 24px, borde blanco 55%, radio grande (la quincena actual es oscura: fondo oscuro con texto claro). Modales: hoja inferior, radio 28px, `max-height:90vh`.
- **Colores de tema elegibles** (`THEME_COLORS`, L7273, 20 swatches con nombre): Grafito `1a1a1e`, Carbón `242428`, Piedra `3f3f46`, Azul noche `1e3a5f`, Petróleo `164e63`, Mar `0b3d4a`, Bosque `0f3d2e`, Musgo `14532d`, Olivo `365314`, Vino `4a1c2c`, Cereza `7a1f1f`, Terracota `9a3412`, Cacao `3b2d1a`, Café `5c4033`, Uva `2d1b4e`, Índigo `312e81`, Medianoche `1e1b4b`, Tinta `0f172a`, Pizarra `334155`, Malva `6b2d5b` (+ color personalizado con `<input type=color>`).
- **Splash**: SVG de `calcula-logo.png` (1100×454) con filtro de contorno/brillo + crédito "diseñado por STUDI05".
- **Iconos**: SVG inline propios (casa, gráfica, calendario, lupa, engrane, lápiz) + iconos de marca vía Simple Icons CDN (`cdn.simpleicons.org`, `cdn.jsdelivr.net/npm/simple-icons@14`) convertidos a trazo (`toOutlineSvg`) o favicon de Google (`google.com/s2/favicons`, fallback DuckDuckGo).
- **Skeleton**: bloques grises con animación `skeleton-effect-wave` (librería `skeleton-elements@4.0.1` por CDN) mientras `initialized` es falso.

---

## 7. FUNCIONES NATIVAS A REPLICAR (capa Capacitor)

Todo el bloque "CAPA NATIVA" (L5000–5377) solo actúa si `window.Capacitor.isNativePlatform()` es true; en web/PWA cada función es no-op (los plugins se registran con fallback `web` que no hace nada). Plugins registrados con `Capacitor.registerPlugin`: `NativeMenu`, `Biometrics`, `Haptics`, `LocalNotifications` (nombres exactos de plugin Swift a respetar).

### 7.1. Menú al mantener presionado (long-press)

- Detección (L5078–5143): `touchstart` sobre `.account-card`, `.movement` o `.plan-card` (no sobre botones/inputs, no con modal abierto, no con búsqueda abierta). Temporizador de **550 ms**; si el dedo se mueve >12px o se levanta, se cancela. Al disparar: `hapticLight()` + `showNativeMenu()`. `contextmenu` (Safari) se previene en esas tarjetas; el click siguiente se suprime 1.200 ms (`suppressNextClick`).
- `showNativeMenu(title, x, y, items)` (L5057): llama a `NativeMenu.showMenu({title, x, y, items})` con timeout de **30 s** (si el usuario descarta sin elegir, Swift no resuelve). Devuelve `selectedId` o `null`.
- Menús exactos (`fireNativeMenuForCard()` L5144):
  - **Cuenta** (`.account-card`): Ver movimientos (`view`, `list.bullet`) / Editar datos (`edit`, `pencil`) / Personalizar tarjeta (`style`, `paintpalette`) / Eliminar cuenta (`delete`, `trash`, `destructive:true`).
  - **Movimiento** (`.movement`): Ver cuenta (`view`, `eye`) / Eliminar movimiento (`delete`, `trash`, destructivo).
  - **Meta** (`.plan-card`, solo metas — los presupuestos usan la misma clase pero `goals.find` no los encuentra y el menú no se abre): Editar (`edit`, `pencil`) / Apartar (`add`, `plus.circle`) / Compartir tarjeta (`share`, `square.and.arrow.up`) / Eliminar meta (`delete`, `trash`, destructivo; con confirmación previa `askConfirm`).
- En web no hay equivalente: las mismas acciones existen como botones (lápiz, ×, "Editar", etc.). El menú nativo es solo un atajo.

### 7.2. Bloqueo con Face ID

- Flag: `calcula-faceid-lock` en localStorage (`faceIdLockEnabled()` / `setFaceIdLockEnabled()`).
- Activación (Ajustes → Seguridad): solo en app nativa; primero intenta `NativeBiometrics.authenticate({reason: "Desbloquea Calcula"})` para confirmar que el dispositivo puede desbloquear; si OK, guarda el flag.
- Al arrancar con sesión y flag activo: `nativeLocked = true` → `renderNativeLockScreen()` (L5245): pantalla "Tu app está bloqueada. Usa Face ID para desbloquearla." + botón Desbloquear; intenta desbloquear automáticamente una vez (`nativeLockAttempted`). `attemptNativeUnlock()` (L5229): si `result.success` → `nativeLocked=false`, `nativeUnlockedThisSession=true`, re-render. Al cerrar sesión se resetea todo (`nativeLocked=false`, `nativeLockAttempted=false`, `nativeUnlockedThisSession=false`).
- No hay fallback con código: si Face ID falla, solo toast "No se pudo desbloquear".

### 7.3. Notificaciones locales de pagos programados

- Flag: `calcula-reminders` en localStorage. Interruptor en Ajustes → Recordatorios → "Avisos fuera de la app" (solo nativo; al activar pide `NativeLocalNotifications.requestPermissions()` y exige `result.display === "granted"`).
- `scheduleNativeReminders(force)` (L5304): usa los mismos ítems que `upcomingReminderItems()` pero **forzando `reminderSettings.enabled = true`** (los avisos nativos no dependen del interruptor de avisos dentro de la app). Si el stamp `id:días` no cambió y no es forzado, no hace nada.
- Estrategia: **cancela todas las pendientes** (`cancelNativeReminders()` → `getPending()` + `cancel({notifications})`) y reprograma. Cada notificación: `id = hashNotificationId("calcula-"+item.id)` (hash djb2, `5381`, `+1`, valor absoluto), `title = nombre del pago`, `body = "{Hoy|Mañana|En N días} · {monto}"`, `schedule.at = día del vencimiento a las 09:00 locales`. Solo se programan las futuras (`at > ahora`).
- Se dispara desde `maybeNotifyReminders()` (al recibir snapshots de pagos/recordatorios) y al activar el interruptor.

### 7.4. Hápticos

- `hapticLight()` (L5046): `NativeHaptics.impact({style:"LIGHT"})` solo en nativo; errores silenciados. Se llama al disparar el menú de long-press, al crear/apartar meta y al registrar movimientos desde algunos modales. No hay otros estilos de háptico en el código.

### 7.5. Otros comportamientos nativos/web a replicar

- Service worker (`sw.js`) solo se registra en web (`if ("serviceWorker" in navigator && !isNativeApp())`).
- "Actualizar app" (`forceAppUpdate()` L11799): desregistra service workers + borra cachés y recarga con `?v=timestamp`.
- Pull-to-refresh: solo en Inicio, desde arriba del todo (≥62px de arrastre → `location.reload()`).
- Compartir meta (canvas + `navigator.share`, §4.7), exportar CSV e ICS (§4.8, §4.10), copiar refresh token (§2).
- Búsqueda global, install coach iOS, saludo animado, reordenar tarjetas (drag + flechas + guardar con `updateDoc {sortOrder}` por tarjeta, o batch en `persistAccountOrder()` para el modal Organizar).

---

## 8. DUDAS / NO DETERMINADO

1. **Saldo inicial vs `applyBalanceSync()` (posible bug, verificar antes de replicar tal cual).** `applyBalanceSync()` (L7394) pone `balance = Σ movementDelta` (cargo +, abono −). Una cuenta `charges` creada con saldo inicial X y sin movimientos tiene Σ=0, por lo que el sync la pondría a 0. El código no crea ningún movimiento inicial por el saldo. No se pudo determinar leyendo el archivo si en la práctica el saldo inicial sobrevive (depende del orden de llegada de los snapshots: `subscribeAccounts` llama a `applyBalanceSync()` con `movementTotals` posiblemente vacío, y `subscribeBalanceSync` lo vuelve a llamar al llegar los movimientos). En Swift hay que decidir: ¿el saldo es un campo independiente o siempre la suma de movimientos? No replicar a ciegas.
2. **Dos motores de quincena.** `buildQuincenaPlan()` (el usado) vs `buildSavePlan()` + `getMonthSavePlans()` + `quincenaMonth` + acción `quincena-month`: el segundo no tiene llamadas ni UI que lo invoque. No se sabe si es código muerto de una versión anterior o una vista mensual planeada. Tampoco se sabe cuál es el "correcto" para el futuro: difieren en el reparto (el usado reparte entre las últimas N quincenas; el otro solo entre la quincena anterior y la del vencimiento).
3. **Campos duplicados sin autoridad clara.** `scheduledPayments.kind` vs `isSubscription` (siempre coherentes en escritura, pero se leen ambos en distintos sitios); `splitQuincenas` vs `splitParts` + `splitUnit` (el studio escribe los tres, el modal clásico solo `splitQuincenas`; la lectura usa `splitParts || splitQuincenas`); `account.type:"subscription"` no existe en BD aunque la UI lo ofrece (se guarda como `recurring`). En Swift conviene un solo modelo canónico y migrar/mapear en lectura.
4. **Tres suscripciones sobre `movements`.** `subscribeAccountMovements` (por cuenta, sin `orderBy`), `subscribeAllMovements` (global, `limit(40)`) y `subscribeBalanceSync` (global, sin límite) leen la misma colección a la vez; `financeMovements` (para Finanzas/presupuestos) y `allMovements` (para Inicio) pueden divergir (uno sin límite, el otro con 40). Además `subscribeBalanceSync` descarga todos los movimientos siempre: con muchos datos será pesado.
5. **Categoría de movimientos inconsistente.** El registro rápido escribe `category`; el modal por cuenta no. Los movimientos sin categoría cuentan como `"otros"` en presupuestos y en la búsqueda. No se sabe si es intencional.
6. **Movimiento `type:"pago"` no mueve saldos.** `movementDelta("pago") = 0` y `queueMovement` no actualiza `balance` para `pago`. En una cuenta `recurring` es irrelevante (su `balance` es 0 y se excluye del sync), pero si alguna vez un `pago` apuntara a una cuenta `charges`, el sync lo ignoraría. Tampoco hay validación que impida crear movimientos `pago` fuera de `openPayScheduledModal`.
7. **`active` en `scheduledPayments` siempre `true`.** No hay UI para pausar/eliminar un pago sin eliminar su cuenta. No se sabe si `active:false` es un estado legacy o previsto.
8. **Presupuestos sin editar ni borrar.** Solo crear y ver. No se sabe si es intencional (MVP) o un olvido; en Swift habrá que decidir la UX.
9. **Sin reglas de Firestore ni índices en el repo.** Las queries usan `where("accountId","==",…)` sin `orderBy` (para evitar índices compuestos, presumiblemente) y ordenan en cliente. No se pudo verificar qué índices existen ni las reglas de seguridad (lectura/escritura por usuario). No asumir que el cliente web actual es la única fuente de verdad de permisos.
10. **`createdAt` puede ser `null` transitoriamente** (serverTimestamp pendiente). El orden por `createdAt` y `dateValue(null)=null` tratan ese caso como 0/`Infinity` según el sitio; no hay manejo explícito de "pendiente de servidor" en la UI.
11. **Relación cuenta ↔ pago asumida 1:1.** Todo el código usa `.find(p => p.accountId===account.id)` (el primer match). Nada impide en BD que una cuenta tenga varios `scheduledPayments`, pero la UI solo mostraría/operaría el primero. El borrado en cascada de cuenta sí borra todos los de esa cuenta.
12. **Fechas sin zona horaria explícita.** Todo es hora local del dispositivo (mediodía local al guardar, `startOfDay` local al comparar). No hay campo de zona horaria ni UTC; dos dispositivos en zonas distintas verían los mismos Timestamps con distinto día local.
13. **Moneda.** Solo MXN/USD, sin tipo de cambio ni moneda por cuenta: `money()` usa la moneda global del perfil para todo. No hay símbolo por cuenta.
14. **El `ownerUid` de `meta/config` y el contenido legacy.** Se sabe que existe y para qué se lee, pero no su valor ni si la migración legacy sigue siendo relevante (los datos legacy top-level no se borran tras migrar).
15. **Qué es `STUDI05`.** Aparece en el splash ("diseñado por STUDI05") y en el `PRODID` del ICS (`-//Calcula//STUDI05//ES`). No hay más información en el archivo (autor/estudio, contacto).
16. **Sin manejo de errores de red en escrituras salvo toast.** Los `addDoc/updateDoc` fallidos solo muestran "No se pudo guardar/registrar" (o el `error.message`); no hay reintentos ni cola offline más allá del caché de Firestore. El `syncToast` añade "Se subirá al volver la conexión" si `!navigator.onLine`, pero eso es solo texto: lo que realmente reintenta es el SDK.
17. **`openAccountMenuModal()` es solo un alias** de `openAccountStyleModal()` (L17872). La acción `edit-account` existe en el dispatcher pero ningún botón visible la emite (la edición se alcanza desde el modal de estilo → "Editar datos"). Igual que `goal-share` (existe en el dispatcher pero el botón de compartir vive en el detalle de meta con `data-goal-act`).
18. **No se pudo determinar el comportamiento real en iOS** (Capacitor/Swift) leyendo solo este archivo: los plugins `NativeMenu`, `Biometrics`, `Haptics` y `LocalNotifications` son `registerPlugin` con nombres que el lado Swift debe implementar; su implementación no está en este repo. Tampoco está aquí el `capacitor.config` ni el proyecto Xcode.

---

## 9. VEREDICTO: LA VÍA WEBVIEW / CAPACITOR QUEDÓ DESCARTADA (5 nov 2026, 23:05 CST)

Jesus probó el IPA #25 con la corrección dirigida al almacenamiento
(persistencia de Auth en memoria, caché de Firestore en memoria, sin
service worker en la app nativa) y siguió saliendo exactamente el mismo
mensaje: "No se pudo conectar con Firebase".

Conclusión por evidencia: el problema NO era IndexedDB ni el service
worker. El WebView (WKWebView) de la app simplemente no logra completar
la petición a Firebase Auth en su teléfono, aunque Safari sí entra con el
mismo correo en calculaby.legaoc.pro. La causa raíz dentro del WebView
quedó sin determinar (se agotaron las hipótesis de almacenamiento y de
intercepción de red), y Jesus decidió olvidar por completo la versión
HTML y esperar la app Swift real.

Consecuencia: la app Swift DEBE usar el SDK nativo de Firebase para iOS
(FirebaseAuth + FirebaseFirestore por SPM), sin WebView ni puente web
para datos. Nada de la capa web se reutiliza para datos; solo el modelo
de datos Firestore y el diseño.

## 10. FIREBASE iOS: APP REGISTRADA, PLIST REAL EN EL PROYECTO

Jesus registró la app iOS en la consola de Firebase (proyecto `psnllega`,
bundle ID `com.legaoc.psnlgastos`) y pasó el `GoogleService-Info.plist`
real. Está en `Calcula/Calcula/GoogleService-Info.plist` como recurso del
target (GOOGLE_APP_ID `1:666775333115:ios:6501c150c0a14a8e8f685e`).
`FirebaseApp.configure()` lo encuentra sin más pasos. Si cambia el
proyecto o el bundle, reemplazar ese archivo por el nuevo de la consola.
La API key no se reproduce en este documento.

## 11. DEL MAPA A SWIFT: DECISIONES DE LA ETAPA 1

- **Movimiento "pago"**: `balanceDelta = 0`; crear o borrar un `pago` no
  toca saldos (igual que la web, §1.3 y §8.6).
- **Total de Inicio**: suma de `max(0, balance)` solo de cuentas
  `type:"charges"`, incluyendo las ocultas (igual que la web, §4.8).
- **Movimientos**: el listener global es `orderBy(createdAt desc),
  limit(40)` como `subscribeAllMovements`; el inicio muestra los
  primeros 10. El detalle de cuenta usa su propia suscripción por
  `accountId` (sin límite), como `subscribeAccountMovements`.
- **Registro**: pide nombre (paso 1 del wizard web) y crea
  `settings/profile` con valores por defecto e `onboardingDone: false`.
  El wizard completo de onboarding (4 pasos) es etapa 2; la app Swift
  no bloquea nada por `onboardingDone`.
- **Saldo inicial vs sync (§8.1)**: en Swift el saldo es el campo
  `balance` y se ajusta de forma incremental al crear/borrar
  movimientos, como `queueMovement`. No se replica `applyBalanceSync`
  (reescribir el saldo desde la suma de movimientos borraría el saldo
  inicial de una cuenta sin movimientos); queda pendiente decidirlo
  con Jesus.
- **Moneda**: `Format.money` usa la moneda global del perfil
  (MXN es-MX / USD en-US), como `money()` en la web.
- **Notificaciones (etapa 1)**: solo pagos programados dentro de la
  ventana `daysBefore` de `settings/reminders`, título = nombre del
  pago, cuerpo = "Hoy|Mañana|En N días · monto", a las 09:00 del día
  del vencimiento. Los avisos de cuentas de cargos y de nómina
  (`upcomingReminderItems`) son etapa 2.
- **Face ID**: al activar se verifica primero que el dispositivo puede
  desbloquear (como la web). Si la biometría no está disponible, se
  ofrece el código del dispositivo (la web no tenía ese fallback).
- **`sortOrder` ausente**: la web lo normaliza a `MAX_SAFE_INTEGER`
  (al final); en Swift un documento sin `sortOrder` decodifica como 0.
  No ocurre en la práctica (todas las rutas de creación lo escriben).

## 12. VERSIONES Y TAGS

- La versión empieza en **1.0** (`MARKETING_VERSION` 1.0,
  `CURRENT_PROJECT_VERSION` 1 en el proyecto Xcode).
- Funciones nuevas → 1.1, 1.2…; solo arreglos → 1.0.1, 1.0.2…
- Cada release lleva su git tag (`v1.0`, `v1.1`…). **Los tags NO se
  pueden crear desde Muse**: la API de GitHub da 403 de escritura
  (igual que con repos y archivos). Los tags se crean al momento de
  subir el release por el navegador, con la sesión de Jesus.
- Al subir de versión: actualizar `CHANGELOG.md` (fecha + cambios) y
  `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` en el proyecto.
- La app muestra su versión en Ajustes (leída del Bundle:
  `CFBundleShortVersionString` + `CFBundleVersion`,
  "Calcula 1.0 (build 1)") y la sección Ajustes → Historial de
  versiones lee el `CHANGELOG.md` incluido en el bundle (sin red).

## 13. ETAPA 2 COMPLETADA — APP COMPLETA EN SWIFT (5 nov 2026)

Todo lo de las secciones 1–8 está implementado en Swift salvo lo listado
en "Pendiente" abajo. Archivos en `Calcula/Calcula/`:

- **Auth y onboarding**: login/registro con nombre (`LoginView`,
  `AuthViewModel`), onboarding de 4 pasos (`OnboardingView`: cadencia,
  moneda, colores, cuentas; crea "Gastos"/"Ahorro").
- **Inicio** (`HomeView`): total pendiente, banner "Por pagar",
  tarjetas de cuentas, "Para estar al día" (esta quincena y la
  siguiente, con `QuincenaCard`), "Próximos pagos" (5, con Pagar),
  últimos 10 movimientos, menú al mantener presionado.
- **Cuentas y movimientos**: lista, detalle, alta, ocultar, reordenar,
  borrar en cascada; registro rápido; borrado con ajuste de saldo.
- **Diferir y quincenas** (`DiferirView`, `QuincenaView`,
  `QuincenaEngine`): plan de quincena completo, pagar/abonar/diferir,
  studio de diferir (semanas/quincenas/meses).
- **Finanzas** (`FinanceView`, `GoalsView`, `BudgetsView`,
  `FinanceCalc`): hero con delta, gráfica de barras, presupuestos
  (warn/hot), metas (anillo, apartar, editar, compartir como imagen).
- **Calendario** (`CalendarView`): mes navegable, filtros, puntos por
  día, pagos del día.
- **Ajustes** (`SettingsView`): cuentas, perfil, modo nocturno,
  recordatorios (incl. ICS), exportar CSV, sincronización
  (interruptor nube + "Sincronizar ahora"), Face ID, historial de
  versiones, versión del Bundle, cerrar sesión.
- **Versiones** (§12): `VersionHistory` lee el `CHANGELOG.md` del bundle.

### Pendiente / no implementado (consciente)

- **Búsqueda global** (§3.6): no implementada en Swift.
- **Saludo animado** ("Buenos días, {nombre}") y **pull-to-refresh**: no
  implementados.
- **Reordenar tarjetas por drag** en el carrusel: existe "Orden de
  tarjetas" (lista con onMove); el drag directo no.
- **"Acceso para Atajos"** (copiar API key + refresh token): omitido a
  propósito (dato sensible; revisar con Jesus antes de replicarlo).
- **Decisión abierta (§8.1)**: si el saldo es campo independiente o
  suma de movimientos (no se replica `applyBalanceSync` a ciegas).
- **Reglas e índices de Firestore**: no verificables desde este repo.
- La etiqueta de rango de quincena en Swift usa `Format.date`
  ("15 dic 2026 – 30 dic 2026"); la web usa formato corto sin año.

## 14. FIX DE COMPILACIÓN: `FirebaseFirestoreSwift` NO EXISTE EN firebase-ios-sdk 11.x (6 nov 2026)

- **Error de CI**: `error: Missing package product 'FirebaseFirestoreSwift'
  (in target 'Calcula' from project 'Calcula')`. La anotación de
  "Code Signing Error" vista antes era una lectura errónea: el log
  tiene cero coincidencias de "Code Signing".
- **Causa**: el proyecto pide firebase-ios-sdk >= 11.0.0. En 11.x el
  producto `FirebaseFirestoreSwift` ya no existe (verificado en el
  `Package.swift` de la 11.0.0: cero ocurrencias; en la 10.29.0 existe).
  En 11.x el código Swift de Firestore (`@DocumentID`, Codable) vive
  dentro del producto `FirebaseFirestore` (target Firestore/Swift/Source),
  así que basta con `import FirebaseFirestore`.
- **Cambios**:
  - `Calcula/Calcula.xcodeproj/project.pbxproj`: eliminada por completo
    la referencia al producto `FirebaseFirestoreSwift` (su
    `XCSwiftPackageProductDependency` 00000000000000000000104B, su
    `PBXBuildFile` 00000000000000000000104A y sus menciones en
    `packageProductDependencies` y en la fase Frameworks). El paquete
    firebase-ios-sdk y los productos `FirebaseAuth` y `FirebaseFirestore`
    quedan intactos. Verificado: cero menciones restantes, llaves y
    paréntesis balanceados, sin IDs huérfanos.
  - `DataStore.swift`, `Models.swift`, `NotificationService.swift`:
    quitada la línea `import FirebaseFirestoreSwift` (queda
    `import FirebaseFirestore`).

## 15. FIX DE COMPILACIÓN: 5 ERRORES SWIFT DEL RUN #11 (6 nov 2026)

El run #11 falló con exit code 65 (3 failures reportadas; 5 errores
localizados en el código). Ya no sale el error de `FirebaseFirestoreSwift`
(§14, arreglado). Cambios, solo lo necesario, sin cambiar comportamiento:

1. **GoalsView.swift** — `ShareLink(item: image, ...)` con `UIImage` no
   compila (UIImage no es Transferable). Nuevo `private struct
   ShareableImage: Transferable` que exporta la imagen como PNG
   (`DataRepresentation(contentType: .png)`; `import
   UniformTypeIdentifiers` agregado) y `ShareLink(item:
   ShareableImage(image: image), preview: SharePreview(goal.name,
   image: Image(uiImage: image)))`. El botón sigue compartiendo la
   imagen de la meta.
2. **OnboardingView.swift:213 y BiometricLock.swift:64** —
   `.foregroundStyle(.calculaAccent)` no compila (con la sintaxis de
   punto el compilador lo busca en ShapeStyle, no en Color). Cambiado a
   `.foregroundStyle(Color.calculaAccent)` en los dos archivos; grep
   confirma cero usos restantes de `.foregroundStyle(.calcula*)` en
   todo el proyecto.
3. **NotificationService.swift** — agregado `import SwiftUI` (`@AppStorage`
   es de SwiftUI; el archivo solo importaba Foundation, FirebaseFirestore
   y UserNotifications).
4. **DataStore.swift** — `syncDeregister` declarado como `(() -> Void)?`
   pero `db.addSnapshotsInSyncListener` devuelve `ListenerRegistration`.
   Declarado ahora como `ListenerRegistration?` y su uso en
   `stopListening()` cambiado de `syncDeregister?()` a
   `syncDeregister?.remove()` (únicos usos: líneas 37, 162, 182, 193).
5. **HomeView.swift** — el compilador no verificaba el tipo del banner
   "Por pagar" en tiempo razonable. La fila del `ForEach` se extrajo a
   la subvista `private struct DueReminderRow` (título y detalle ya
   calculados); el `body` de Inicio quedó más ligero.

Verificado: cero patrones que fallaban (grep), llaves y paréntesis
balanceados en los 6 archivos editados, otros ShareLink del proyecto
(String y URL) no afectados. Sin compilador Swift en Linux: la prueba
real es el siguiente run de GitHub Actions.
