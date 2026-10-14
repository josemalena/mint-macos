# Reglas del proyecto

## Siempre revisar las capturas antes de diseñar o dar algo por terminado

Regla de José (13-10-2026). Antes de diseñar, implementar o aprobar cualquier pieza
que imita macOS (ventanas, menús, diálogos, preferencias, barra lateral, atajos):

1. **Mira las capturas de referencia** en `~/Desktop/SS`. Son las de su Mac con
   Catalina, de octubre de 2026 en adelante. Busca la de esa pantalla y repasa
   **todo** lo que muestra, no solo lo que se pidió: opciones, casillas, orden,
   textos, estados apagados.
2. **Compara el resultado** con la captura, mirando la pantalla de verdad: una
   captura del resultado al lado de la de referencia.
3. **Si no hay captura** de esa pantalla, pídesela a José. No la reconstruyas de memoria.
4. **Las capturas no entran al repo:** tienen contenido de Apple. Se citan por
   nombre de archivo («Screen Shot 2026-10-10 at 12.37.35 PM»).

Caso que la originó: «Applications» se agregó a la barra lateral de Fynder y la
papelera se quitó. La captura de Finder ▸ Settings ▸ Sidebar enseña que en macOS
los dos son **casillas que el usuario prende o apaga**, con Recents, Desktop,
Documents, Downloads, Movies, Music, Pictures y Home en Favorites, y Macintosh HD,
External disks, Network y Trash en Locations.

## Turno de pantalla antes de tocar la sesión de José

Regla de José (13-10-2026). Antes de cualquier `xdotool`, `wmctrl`, clic o ventana
nueva sobre su pantalla (`:0`):

1. **Toma el turno:** `~/.local/bin/gui-lock tomar <sesión> [segundos]`. Si lo tiene
   otra sesión, espera; `gui-lock estado` dice quién lo tiene. Vence solo, a los
   120 s por defecto.
2. **Verifica el foco antes de cada tecla:** que la ventana activa sea la que vas a
   probar. El turno coordina a las sesiones, pero no sabe si José está usando la
   computadora.
3. **Suéltalo al terminar:** `gui-lock soltar`.

Lo que se pueda probar en una pantalla aislada (Xephyr o Xvfb) va ahí y no necesita
turno. Caso que la originó: un `xdotool` de prueba mandó dos Ctrl+C a la terminal de
otra sesión.
