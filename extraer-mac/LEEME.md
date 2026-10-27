# Extraer Mac: recursos, medidas y capturas de una Mac encendida

Hecho para el iMac con **Monterey (12)**; sirve en otras versiones. Repite lo
que GobCorp-Mac sacó del iMac con macOS 27 (Golden Gate, `referencias/macos27-20261014`)
y lo que `paquete.sh` toma del disco de Catalina. Monterey **no** reemplaza a
Catalina: es una referencia más.

**Nada de lo que sale de aquí va a un repo.** Son archivos de Apple: van a
`~/.local/share/mint-macos/referencias/monterey-<fecha>/` en la computadora con Linux.

## Qué saca

| Carpeta | Qué |
|---|---|
| `recursos/sistema/` | Un `.tar` por carpeta del sistema (Applications, CoreServices, PreferencePanes, Extensions, Frameworks, PrivateFrameworks, /Applications): `.icns`, `.car`, PDF, PNG, TIFF, plists, strings, `.loctable`, `.xml`, `.toolbar` y nib en inglés (y ExtensionKit, los paneles de Settings). Sin fuentes; binarios solo los de los paneles de Settings y de System Settings, para leer sus vistas SwiftUI. Si un `.tar` pasa de 3.9 GB sale partido (`.tar.aa`, `.tar.ab`) porque la memoria es FAT32. |
| `recursos/car/` | Los `.car` de SystemAppearance (Aqua, DarkAqua, Vibrant…) |
| `recursos/iconos/` | CoreTypes, cada app de /System/Applications, cada `.prefPane` y Finder, Dock, Control Center, Spotlight, Siri, loginwindow |
| `recursos/car-inventario/` | `assetutil -I` de cada `.car` de `car/` e `iconos/` (la ruta con `__` en vez de `/`): el inventario de Apple para comparar lo que saca `tema/iconos/car.py`. Los PNG de los `.car` no se sacan aquí; se sacan en la Mac mini con car.py, a `referencias/`. |
| `recursos/cursores/`, `recursos/sonidos/` | Cursores de HIServices; sonidos de alerta y de interfaz |
| `recursos/fondos/` | Los fondos de fábrica y el que tienes puesto |
| `recursos/cuenta/` | La foto de la cuenta y los botones Restart, Shut Down y Sleep del login |
| `medidas/` | `medidas.json` (pantalla, barra, fuentes, colores en claro y oscuro, barra de título, semáforos), `pantalla.txt`, `ajustes-ui.txt`; `acentos/<color>.json` y `acentos/resumen.txt` del bloque 18 |
| `capturas/` | PNG en claro y oscuro, `NN-area-estado-modo.png`, mismos números que macOS 27 |
| `videos/` | Lupa del Dock, Control Center, Spotlight, Mission Control, minimizar, Notification Center y Launchpad |
| `recursos/car-sacado/` | Paso `car`: el contenido de cada `.car` de `car/` e `iconos/` convertido con el CoreUI de la Mac (`car-mac.js`, JXA), con los nombres de `tema/iconos/car.py`: PNG de los mapas de bits, PDF/SVG con sus PNG, JSON de efectos, degradados, multisize, colores y pilas de capas, y los `.caar` (con `.caml` si se puede). `cuenta.tsv` por `.car` y `cuenta-total.tsv` con lo que no salió y su motivo. Es de Apple: no va a ningún repo. |
| `iconos-simbolicos/Mint-Macos-<versión>/` | Paso `simbolos`: un `<nombre>-symbolic.svg` por glifo vectorial (los SF Symbols de CoreGlyphs, leídos en `/System`, y los de las apps), el más cercano a regular mediano, sin fill, con xmlns y centrado en una caja cuadrada, en `scalable/<contexto>/` con su `index.theme`. El nombre sale de `simbolos-freedesktop.tsv` (SF Symbol → Icon Naming Spec 0.8.90, con alias de `name_aliases.strings`); lo que no está en la tabla va con su nombre en `scalable/sf/`. `simbolos.tsv` dice de dónde salió cada uno y `descartados.tsv` los que no (con partes en blanco, con imagen o degradado…). Es de Apple: el migrador lo instala en `~/.local/share/icons/`; no va a ningún repo. |
| `estado-sistema/` | Foto de solo lectura antes de empezar y al devolver: Login Items (por System Events), `launchctl print-disabled` de `system` y de la sesión, y `sharing -l`. `diferencias.txt` sale vacío si nada cambió. `sfltool dumpbtm` no va: pide root. |
| `herramientas/` | Los guiones con que se sacó y `capturas.log`, la bitácora |

Las capturas cubren: escritorio y barra; menús Apple, File, Edit, View, Go,
Window y Help; Control Center; Notification Center; el Dock (normal, menú
contextual, Options, la pila Downloads en Fan, Grid y List, lupa y a la
izquierda); el Finder (íconos, lista, columnas, galería, Quick Look, activa e
inactiva, semáforos, menú contextual de un archivo, de una app y del escritorio,
el rectángulo de selección en una ventana y en el escritorio, Get Info y las
cuatro pestañas de Preferences); Spotlight; Launchpad; System Preferences
(todos los paneles con todas sus pestañas, las categorías de Keyboard ▸
Shortcuts, Modifier Keys y Hot Corners con su menú abierto, Screen Saver Options,
Notifications con una app; desde macOS 13, System Settings: cada fila de la barra
lateral, el panel llevado hasta abajo y sus subpáginas y hojas, ver más abajo); alertas y diálogos (Save, Save expandido, Open,
«¿guardar cambios?», la clave de administrador, que se cancela sola); About
This Mac con sus pestañas; Force Quit; la barra de ⇧⌘5; ⌘Tab; Mission Control
y la primera pantalla de Migration Assistant; y los Stacks del escritorio (bloque 17, de
Mojave en adelante): las pilas cerradas, una abierta y Group Stacks By. Para eso pone en el
Desktop unos archivos `extraer-pila-*` (imágenes, PDF y capturas) que borra al terminar, y deja
«Use Stacks» como estaba. Estas capturas llevan la versión en el nombre
(`17-stacks-cerradas-macos<versión>-<modo>.png`). Solo ese bloque: `BLOQUES="17" bash extraer.sh capturas`.

El bloque 18 corre una vez, después de las dos tandas, por cada acento (multicolor, azul, morado,
rosa, rojo, naranja, amarillo, verde y gris). Cambia `AppleAccentColor`, `AppleHighlightColor` y
`AppleAquaColorVariant` con `defaults write -g`, y luego hace tres cosas:

- Desde un proceso nuevo relee `controlAccentColor`, `selectedContentBackgroundColor`,
  `selectedTextBackgroundColor` y `keyboardFocusIndicatorColor`, en claro y en oscuro.
- Captura una ventanita con controles de acento en cada apariencia (`18-acento-<color>-claro.png` y
  `-oscuro.png`).
- Solo con `ACENTO_FINDER=1`, captura la ventana del Finder, que ya estaba abierta
  (`18-acento-<color>-finder-claro.png`), para ver si las apps abiertas toman el color en caliente.
  En 12.7.6 no lo tomaron: las nueve salieron iguales. Los nombres de las notificaciones se confirman
  con `osascript -l JavaScript herramientas.js escuchar-colores 30` mientras se cambia el acento a
  mano.

Los tres valores originales vuelven al terminar el bloque y también en la salida del guion, aunque
muera a mitad. Si el color releído no cambia, se anota y sigue; no reinicia nada.

Las cadenas de `AppleHighlightColor` son las de uso común, sin leer de System Settings. La prueba es
lo releído. Para correr solo ese bloque: `BLOQUES="18" bash extraer.sh capturas`.

## Pantalla bloqueada

«capturas» y «videos» necesitan la sesión en la consola y la pantalla abierta. Al empezar, antes
de cada tanda, de los acentos y de los videos, el guion lo mira en `IOConsoleUsers` (`ioreg`, sin
root) y, si está bloqueada o la sesión no está en la consola, para con salida 3 y un aviso; lo que
haya tocado se devuelve igual. Mientras corre, `caffeinate -dimsu` evita que la pantalla se
apague o se bloquee por reposo, sin cambiar ningún ajuste guardado.

## Pasos

1. Córrelo desde la memoria TRANSPORTE. **La salida va al disco local**
   (`~/extraer-salida/macos<versión>-<fecha>`), porque la memoria escribe lento;
   el último paso, `entregar`, comprime todo en `macos<versión>-<Mac>-<fecha>.tar.gz`
   con su `.sha256`, copia ese único archivo a la carpeta del guion en la memoria
   y verifica la suma sobre la copia. Si pasa de 4 GB va partido (FAT32).
2. **Los permisos se piden todos al principio.** El primer paso del guion
   (`permisos`) dispara de una vez los diálogos de Automatización (System
   Events, Finder, System Preferences, TextEdit, Terminal), Accessibility y
   Screen Recording. Dale **OK** a cada uno y, en System Preferences ▸ Security
   & Privacy ▸ Privacy (desde macOS 13: System Settings ▸ Privacy & Security), marca **Terminal** en **Accessibility** y en **Screen
   Recording** (el candado pide tu clave). El guion espera hasta 10 minutos a
   que estén. Si Screen Recording se acaba de conceder, cierra Terminal y lo
   vuelve a abrir solo con los pasos que faltan. Después de eso no hace falta
   volver a la Mac.
3. Abre `Extraer Mac.applescript` con **Script Editor** y dale a **▶ Run**.
   Escoge qué sacar y dale a **Empezar**. Se abre Terminal y empieza.
   Sin Script Editor: en Terminal, `bash extraer.sh` (todo, con permisos primero) o
   `bash extraer.sh permisos recursos medidas`.
4. **No toques el iMac mientras corren las capturas.** Mueve el ratón, abre
   menús y cambia entre claro y oscuro. Avisa con notificaciones en cada parte.
5. Al terminar, el modo, el Dock y el Finder vuelven a como estaban. La carpeta
   `~/Muestra` la crea para las capturas y la quita si no existía antes.
6. **A mano, al final: Migration Assistant.** Ábrelo y saca con **⇧⌘4 y luego
   Espacio** (solo la ventana) cada pantalla hasta la de escoger qué migrar.
   **No migres nada.** Al darle a Continue te pide la clave y cierra todas las
   apps; por eso no va en el guion. Guárdalas en `capturas/` con el nombre
   `14-migration-assistant-NN-oscuro.png`.
7. Al final busca en la memoria `extraer-mac/macos<versión>-<Mac>-<fecha>.tar.gz`
   y su `.sha256`. Expulsa la memoria y tráela.

## Tiempo, más o menos

- Recursos: 1 a 3 minutos en disco local.
- Medidas: menos de un minuto.
- Capturas: unos 20 minutos por modo, 40 en total (System Preferences se lleva la mitad).
- Videos: 2 minutos.
- Entregar: 2 minutos de compresión y 15 a 40 de copia a la memoria (2.3 GB a menos de 2 MB/s).

## System Settings (macOS 13 en adelante)

El bloque 08 no usa el diccionario de AppleScript (en Sequoia solo publicaba 6
paneles y sus anclas no abrían nada): recorre la barra lateral fila por fila,
captura cada panel (y otra vez llevado al fondo, `-fin`) y entra a sus
subpáginas, un nivel, hasta `SUBMAX` por panel (25). Solo pulsa botones con
AXIdentifier de System Settings (`com.apple.systempreferences.<panel>.<algo>` o
`com.apple.settings.<algo>`), que no sean de la barra lateral, ni del semáforo,
del scroll o de la búsqueda, y cuyo último tramo no empiece con un verbo de
acción (turnOn, reset…). **Por omisión va en seco** (`AJ_SECO=1`): anota en la
bitácora «pulsaría …» y no pulsa nada; con `AJ_SECO=0` pulsa de verdad.
De la cuenta, Wallet, Passwords, Internet Accounts, Game Center y Family se
captura el panel pero no sus subpáginas; con `AJENA=1` esas filas ni se abren.
El árbol de Accessibility de cada panel queda en `herramientas/arbol-ajustes/`
para afinar la próxima versión. La parte de System Preferences del bloque 16
no corre (la cubre el 08). La hoja Save desplegada sale con la preferencia
`NSNavPanelExpandedStateForSaveMode`, que se devuelve como estaba. **Sin probar
en una Mac** al escribirlo (26-10-2026).

## Catalina

Sirve igual. Diferencias que el guion ya contempla: no hay Control Center (la
captura 03 y el video 02 se saltan), el reloj y Notification Center viven en
SystemUIServer, y System Preferences tiene sus propios paneles. Las ventanas
sueltas salen a 1x si la pantalla no es Retina.

Pendiente: el video 06 falla porque `item_barra "Clock"` no existe en Catalina.
Ahí el Notification Center es el ícono del extremo derecho de la barra.

## Fase C (Monterey, 27-10-2026)

`bash extraer.sh fase-c` (o «Fase C en Monterey.command») corre `fase-c.sh`: la lista de Dev-Dock en `referencias/trabajo-samana-20261026/LISTA-CAPTURAS-FASE-C.md`. Va en cinco secciones, que se pueden elegir con `FASE="A D"`:

- **A**, controles: apretado (mouseDown sostenido y soltar fuera), puntero encima, foco con Tab e inactivo.
- **B**, ventanas y Dock sobre fondo liso blanco, negro y gris, con «Reduce transparency» apagado y encendido.
- **C**, los videos que faltaban.
- **D**, las hojas de System Preferences.
- **E**, datos.

Más cosas:

- Los controles se buscan en apps de Apple (System Preferences, Finder, TextEdit) con `herramientas.js ui`, porque una ventana creada desde osascript queda inactiva.
- Lo que cambia (fondo, Reduce transparency, Full Keyboard Access, volumen, acento, Dock y modo) se devuelve en `devolver()`.
- Lo que no se puede hacer de forma fiable queda en `fase-c/no-hecho.txt`.
- Al final, `fase-c/tubo.txt` lista los paquetes de menos de 100 MB (van por scp) y `fase-c/transporte.txt` los más grandes (van a la memoria TRANSPORTE).
- Por ssh no corre: si System Events da -600, el guion para con el aviso.
- **Sin probar en una Mac todavía.**

## Lo que no puede

- La pantalla de login y la de bloqueo: screencapture no corre ahí. Van con el celular.
- Lo que dependa de la ruta exacta de un control en Accessibility (la lista de
  Shortcuts, el botón de Save expandido, las pestañas de About This Mac) se
  intenta por varias rutas; si ninguna sirve, sale en `capturas.log` y esa
  captura falta. Los clics van a elementos con nombre; solo el menú del escritorio
  y los rectángulos de selección van por coordenadas, sacadas del tamaño de la pantalla.
- Corrido en el iMac con Monterey 12.7.6 el 2026-10-15 (CVRPC0187). Lo que falle queda en `capturas.log`.
