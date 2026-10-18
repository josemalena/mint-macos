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

## Los datos del arranque: un programa y un archivo

Regla de José (18-10-2026): lo que no cambia con el sistema corriendo (modelo,
número de serie, procesador, memoria, gráficos, sistema) lo lee **solo**
`mint-macos-equipo` al arrancar, y lo escribe en `/run/mint-macos/equipo.json`
(0640 root:users, porque lleva la serie). Nadie más vuelve a leer
`/sys/class/dmi`, `/proc/cpuinfo` ni `lspci`. Si el archivo no está, esas filas
no salen; no se adivinan. Las pantallas y los discos se leen al usarse, porque
cambian. Campos: cabecera de `rust/equipo/src/main.rs`.

## Instalar no es activar

Un residente (mac-ventanas, mac-preferencias…) atiende con el código que tiene
en memoria. Después de instalar un binario nuevo, `nativo/instalar.sh` avisa de
los residentes que arrancaron antes que él, y `--reiniciar` los reinicia. Una
prueba sobre la sesión de José sin ese paso prueba el código viejo (18-10-2026:
⇧⌘5 seguía sin arrastre).

## Pruebas: Xvfb, y Xephyr solo dentro del Dell

Regla de José (18-10-2026): nada se abre en el monitor LEN (HDMI-3), donde él
trabaja. `pruebas/correr.sh` usa Xvfb (1600×1200, no se ve); `--ver` abre Xephyr
a 1280×1000 en +0+0, dentro del Dell (HDMI-1). Cualquier otro Xephyr de prueba,
igual: en el Dell y de un tamaño que quepa.

## Lo que se cambió en la sesión de José (con su vuelta atrás)

- **Flathub de usuario** (`flatpak remote-add --user flathub`, 18-10-2026): «Get»
  del App Store instala Flatpak sin clave. El de sistema sigue.
- **Actualizaciones partidas como en Catalina**: las apps (Flatpak y los paquetes
  de APT con ficha de app) van en Updates del App Store; lo demás de APT, en
  Software Update; los núcleos y Timeshift, en Update Manager (Advanced…). El
  salto de versión de Mint se detecta y se hace con las herramientas de Mint.
  Detalle: `rust/tienda/DBUS.md`.
- **Sin el escudo de mintupdate** y **System Reports por notificaciones** en vez de
  mintreport-tray (`avisos/instalar.sh`): vuelta atrás en `settings/LEEME.md`.
- **Solaar sin ícono** en la barra; sigue corriendo para reponer sus ajustes
  (`tema/solaar-barra.sh`, `--con-icono` es la vuelta atrás).
