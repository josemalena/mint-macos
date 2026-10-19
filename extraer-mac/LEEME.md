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
| `recursos/cursores/`, `recursos/sonidos/` | Cursores de HIServices; sonidos de alerta y de interfaz |
| `recursos/fondos/` | Los fondos de fábrica y el que tienes puesto |
| `recursos/cuenta/` | La foto de la cuenta y los botones Restart, Shut Down y Sleep del login |
| `medidas/` | `medidas.json` (pantalla, barra, fuentes, colores en claro y oscuro, barra de título, semáforos), `pantalla.txt`, `ajustes-ui.txt` |
| `capturas/` | PNG en claro y oscuro, `NN-area-estado-modo.png`, mismos números que macOS 27 |
| `videos/` | Lupa del Dock, Control Center, Spotlight, Mission Control, minimizar, Notification Center y Launchpad |
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
Notifications con una app); alertas y diálogos (Save, Save expandido, Open,
«¿guardar cambios?», la clave de administrador, que se cancela sola); About
This Mac con sus pestañas; Force Quit; la barra de ⇧⌘5; ⌘Tab; Mission Control
y la primera pantalla de Migration Assistant; y los Stacks del escritorio (bloque 17, de
Mojave en adelante): las pilas cerradas, una abierta y Group Stacks By. Para eso pone en el
Desktop unos archivos `extraer-pila-*` (imágenes, PDF y capturas) que borra al terminar, y deja
«Use Stacks» como estaba. Estas capturas llevan la versión en el nombre
(`17-stacks-cerradas-macos<versión>-<modo>.png`). Solo ese bloque: `BLOQUES="17" bash extraer.sh capturas`.

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
   & Privacy ▸ Privacy, marca **Terminal** en **Accessibility** y en **Screen
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

## Catalina

Sirve igual. Diferencias que el guion ya contempla: no hay Control Center (la
captura 03 y el video 02 se saltan), el reloj y Notification Center viven en
SystemUIServer, y System Preferences tiene sus propios paneles. Las ventanas
sueltas salen a 1x si la pantalla no es Retina.

## Lo que no puede

- La pantalla de login y la de bloqueo: screencapture no corre ahí. Van con el celular.
- Lo que dependa de la ruta exacta de un control en Accessibility (la lista de
  Shortcuts, el botón de Save expandido, las pestañas de About This Mac) se
  intenta por varias rutas; si ninguna sirve, sale en `capturas.log` y esa
  captura falta. Los clics van a elementos con nombre; solo el menú del escritorio
  y los rectángulos de selección van por coordenadas, sacadas del tamaño de la pantalla.
- Corrido en el iMac con Monterey 12.7.6 el 2026-10-15 (CVRPC0187). Lo que falle queda en `capturas.log`.
