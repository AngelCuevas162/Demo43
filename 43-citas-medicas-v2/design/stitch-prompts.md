# Prompts para Google Stitch — Citas Médicas v2 (3 pantallas)

Pega primero el **bloque de estilo** y luego cada pantalla, en este orden, dentro del MISMO proyecto de Stitch
para que las tres se vean iguales. Exporta cada una como HTML y guárdalas en `priv/`:

| Pantalla | Archivo | Ruta |
|---|---|---|
| 1. Agenda | `priv/index.html` | `/` |
| 2. Médicos y consultorios | `priv/medicos.html` | `/medicos` |
| 3. Panel de control | `priv/panel.html` | `/panel` |

---

## Bloque de estilo (pégalo al inicio de CADA prompt)

```text
Design system for a web app called "Citas Médicas", a medical appointment management tool for a clinic receptionist. All visible text in Spanish. Calm healthcare look: light gray-blue background (#f4f7fa), white rounded cards (16px radius, soft shadow), teal primary color #0b6e8a, green for success/confirmed, amber for warnings/reminders, red for cancel/errors. Font: Plus Jakarta Sans. Desktop-first, responsive. Use plain HTML with Tailwind classes and DO NOT write any JavaScript logic. Every screen has the same top navigation bar: logo "Citas Médicas" on the left and three links on the right: "Agenda" (href="/"), "Médicos" (href="/medicos"), "Panel" (href="/panel"). Highlight the link of the current screen. Keep all element ids and name attributes EXACTLY as specified.
```

---

## Pantalla 1 — Agenda (`/`)

```text
Screen 1: "Agenda de citas".

Top: page title "Agenda de citas" with subtitle "Sin traslapes · con recordatorios a 48 h y 2 h". On the right, a select with id="filtro-estado" and options: Todas, Programadas, Confirmadas, Canceladas, Por reagendar.

Card "Nueva cita" with a form id="f", two-column grid, fields (use exactly these name attributes):
- select name="medico" id="sel-medico" with placeholder "Selecciona un médico" and 3 sample options
- input name="paciente" text, required, placeholder "Nombre del paciente"
- input name="inicio" type="datetime-local", required
- select name="duracion_min" with options 15, 30 (default), 45, 60 (labels "15 min", "30 min", ...)
- select name="consultorio" with options "Automático" (default, value empty), C1, C2, C3, C4
- input name="motivo" text, optional, full width
- primary button "Agendar cita" (type submit)
Small helper text under the form: "Si eliges Automático, el sistema asigna el primer consultorio libre."

Right below the form, an empty div id="msg" for success (green) and error (red) messages.

Card "Citas programadas" with a table whose tbody has id="citas". Columns: #, Paciente, Médico, Consultorio, Inicio, Duración, Estado, Acciones. The Estado column shows a colored pill (Programada = blue, Confirmada = green, Cancelada = gray, Por reagendar = amber). The Acciones column has two small buttons: "Confirmar" (green) and "Cancelar" (red). Include 3 sample rows in the tbody so the design is visible.
```

---

## Pantalla 2 — Médicos y consultorios (`/medicos`)

```text
Screen 2: "Médicos y consultorios". Same navigation bar and style as the Agenda screen.

Title "Médicos y consultorios" and subtitle "Disponibilidad, bajas y lista de espera".

Section "Médicos": an empty-looking grid container id="medicos" (responsive 3 columns) showing 3 sample cards. Each card has: initials avatar, doctor name (e.g. "Dra. Ana Torres"), specialty (e.g. "Medicina general"), a status pill ("Disponible" green or "De baja" red), the text "5 citas activas", and one button: "Dar de baja (enfermo)" in red outline, or "Reincorporar" in green for a doctor that is de baja. Include one sample card in "De baja" state.

An empty div id="resumen-baja" (a highlighted info banner, amber) where a message like "Se reasignaron 15 citas, 2 quedaron por reagendar" will appear after marking a doctor as de baja.

Section "Consultorios": grid container id="consultorios" (4 columns) with 4 sample cards C1, C2, C3, C4. Each card shows the room name, a pill "Libre" (green) or "En uso" (amber), and "N citas activas".

Section "Lista de espera": a card with a form id="fe" with input name="paciente" (placeholder "Nombre del paciente"), select name="medico" id="sel-medico-espera" (placeholder "Médico que prefiere") and a button "Agregar a la lista". Below it, a list container id="espera" with 2 sample items (patient name, preferred doctor, time since request). Caption: "Cuando se cancela una cita, el hueco se ofrece automáticamente al primero de la lista."

An empty div id="msg" under the page title for success/error messages.
```

---

## Pantalla 3 — Panel de control (`/panel`)

```text
Screen 3: "Panel de control". Same navigation bar and style as the previous screens.

Title "Panel de control" and subtitle "Indicadores, recordatorios y simulación".

Row of 5 KPI cards, each with a big number, a label and a small icon. Give the big-number element these ids:
- id="kpi-total" label "Citas totales"
- id="kpi-confirmadas" label "Confirmadas"
- id="kpi-noshow" label "Tasa de no-show" (shown as a percentage, e.g. 18%)
- id="kpi-espera" label "En lista de espera"
- id="kpi-pendientes" label "Por reagendar"

Card "Ocupación por médico": a container id="ocupacion" with 5 sample horizontal progress bars (doctor name on the left, bar in teal, number of citas on the right).

Card "Recordatorios enviados": a container id="recs" with 4 sample rows. Each row shows: a type chip ("48 h" or "2 h"), the patient name, the message text in small gray, and a status chip: "Entregado" (green), "Reintentando" (amber) or "Fallido" (red).

Card "Simulación del escenario": short description "10 médicos, 4 consultorios, 200 solicitudes simultáneas, 20 % de no-show y un médico enfermo." Three buttons: id="btn-sim" "Correr simulación" (primary), id="btn-caos" "Prueba de caos" (amber outline), id="btn-limpiar" "Limpiar agenda" (red outline). Below, an empty result container id="sim-resultado" styled as a light card with a placeholder text "Aquí aparecerá el resultado".

An empty div id="msg" under the title for success/error messages.
```
