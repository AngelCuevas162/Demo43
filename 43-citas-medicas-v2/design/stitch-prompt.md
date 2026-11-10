Design a clean, modern, responsive web app (desktop-first, works on mobile) called "Citas Médicas": a medical appointment scheduler for a clinic receptionist. All visible text must be in Spanish. Style: calm healthcare look, white and soft-gray background, teal (#0b6e8a) as primary color, rounded cards, generous spacing, readable sans-serif font.

Single page with these sections, top to bottom:

1. Header with the title "Agenda de citas médicas" and a short subtitle "Sin traslapes · con recordatorios".

2. A card "Nueva cita" containing a form with id="f" and these fields (use exactly these name attributes):
   - Paciente (input name="paciente", text, required)
   - Médico (input name="medico", text, required)
   - Fecha y hora (input name="inicio", type="datetime-local", required)
   - Duración en minutos (input name="duracion_min", type="number", min 5, max 240, default 30)
   - Motivo (input name="motivo", text, optional)
   - A primary button "Agendar cita"

3. An empty div with id="msg" right below the form, where success (green) and error (red) messages will be shown.

4. A card "Citas programadas" with a table with columns: #, Paciente, Médico, Inicio, Fin, Acciones. The table body must have id="citas" (leave it empty or with one sample row).

5. A card "Recordatorios" with a bell icon and an empty container div with id="recs" where reminder notices will be listed (each one a soft yellow pill/banner).

Keep it a single HTML screen, no login, no navigation menu. Use plain HTML (Tailwind classes are fine) and do not add any JavaScript logic.
