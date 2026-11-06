# Historial de versiones — Calcula

La app muestra este historial en Ajustes → Historial de versiones.
La versión actual también se ve en Ajustes, abajo del todo.

## 1.2.3 — 2026-11-06 — Saludo en Inicio que se convierte en logo, como la web
- Inicio: el encabezado ahora saluda ("Buenos días" / "Buenas tardes" / "Buenas noches" + primer nombre del perfil, frase en regular y nombre en negrita y más grande) y a los 2.4 s se desvanece para dar paso al logo "Calcula" con su animación de entrada, como la web. Si no hay nombre, muestra el logo directo. Si la app vuelve de segundo plano tras 25 s o más, el saludo se reproduce de nuevo.
- El logo ya no va en la barra de navegación (ahí se veía dentro de una burbuja): ahora es una fila propia dentro del contenido, con el logo desnudo directo sobre el fondo y los botones circulares de buscar y ajustes a la derecha, como en la web.

## 1.2.2 — 2026-11-06 — Logo real de Calcula en el encabezado y en el ícono de la app
- Inicio: el encabezado ya no dice "Inicio"; muestra el wordmark "Calcula" de la web arriba a la izquierda, junto a los botones de buscar y ajustes. Se ve bien en claro y en oscuro (se tiñe con el color del sistema).
- Ícono de la app: ya no es la "C" dorada; ahora es el ícono real de Calcula (la "C" ornamentada en gris claro sobre negro).
- Acceso y onboarding: la pantalla de acceso muestra el wordmark "Calcula" en lugar del texto, y el asistente de 4 pasos también lo lleva arriba.

## 1.2.1 — 2026-11-06 — Huecos del inventario de la web (inicio, cuenta, calendario, ajustes)
- Inicio: "Próximos pagos" con flecha ↗ (o "!" roja si está vencido), nombre, cuenta, fecha ("En 2 días · 8 nov 2026"), monto y botón "Pagar" por fila; aviso ámbar "Por pagar" con una línea por pago ("En 2 días · Pago semanal · $216.00").
- Hoja "Marcar pago": monto, "Programado para 8 nov 2026" y botones "Cancelar" / "Marcar como pagado" (crea el movimiento y avanza el próximo pago, como la web).
- Hoja "Tu Nómina" (Inicio y Quincena): Primera quincena Día 1–15; Segunda quincena Último día del mes / Día 16, 17, 18, 20, 25, 28, 30; Guardar persiste en el perfil.
- Diferir: sección "Reparte el dinero que te sobra" con "Por quincena" (suma de lo que se puede diferir) y "Diferido" (suma de lo ya diferido), y tabla Q1–Q5 "Reparto sujeto a cambios" con parte igual por quincena y "Quedo" restante. La web muestra repartos desiguales ($18.10 / $296.60) con una fórmula que no está en el código de la web disponible; aquí el reparto es en partes iguales.
- Detalle de cuenta: héroe oscuro con "Registrar pago" (recurrente/subscripción) y "+ Cargo" / "Abono" (cargos y abonos); hoja "Editar tarjeta" (color con cuadrícula de 20 colores + crear color, interruptor Visible, Icono, sitio web, Editar datos / Eliminar cuenta / Guardar); hojas "Editar pago" (nombre de la cuenta, nombre del pago, monto, frecuencia, próximo pago) y "Editar cuenta" (nombre y día de pago opcional).
- Calendario: puntos con el color de la tarjeta de cada cuenta (el rojo/azul/gris de las capturas son los colores de las tarjetas de Jesus), puntos ya filtrados por el filtro activo, texto "Elige un día — No hay pagos este día" al cambiar de mes sin día seleccionado y botón "Volver arriba" al hacer scroll.
- Ajustes: acordeón de 7 filas (Cuentas, Dinero, Apariencia, Recordatorios, Exportar, Sistema, Cerrar sesión) con subfilas como la web; "Modo nocturno" (clave calcula-dark, igual que la web); Recordatorios con antelación 1/2 días, avisos en la app y "Agregar a Calendario" (.ics); Exportar CSV del mes y de la quincena; Sistema con "Actualizar app", Sincronización y Face ID. "Acceso para Atajos" sigue omitido (copia un token sensible).
- Editor de perfil de 4 pasos (frecuencia, moneda, colores, cuentas + nombre) ahora también edita el perfil desde Ajustes → Dinero → Mi perfil, con "Guardar" en vez de "Empezar".

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
