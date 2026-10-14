# System Preferences (Settings.app)

Una ventana nueva de ajustes con el diseño de **macOS Catalina**: barra de
herramientas (atrás, adelante, Show All y búsqueda), la cuadrícula de paneles por
grupos y, al abrir uno, su página con pestañas. Por dentro **no reescribe nada de
Cinnamon**: carga los módulos de `cinnamon-settings` (los `cs_*.py` de
`/usr/share/cinnamon/cinnamon-settings`) y los muestra en su propia ventana. Lo
que cambia es el aspecto y cómo se agrupan.

```
./desde-mac.sh     # los íconos y glifos de Apple, del disco de la Mac (una vez)
./instalar.sh      # la app, el comando mac-settings y el lanzador
./instalar.sh --quitar
```

```
mac-settings                 la cuadrícula
mac-settings sound           un panel, por su nombre de Cinnamon…
mac-settings Displays        …o por el de Catalina (sin importar mayúsculas)
mac-settings --lista         los paneles que hay
```

Una instancia sola: pedirle otro panel a la que ya está abierta la trae al frente.
Por D-Bus: `app.abrir("sound")` y `app.todo`.

## Los paneles

Los grupos y el orden son los de Catalina (`NSPrefPaneGroups.xml` de la Mac); lo
que hay en cada panel es lo que Cinnamon ya sabe hacer (`paneles.py`):

| Grupo | Paneles |
|---|---|
| personal | General (Themes, Fonts, Animations, Default Apps, Menu Bar) · Desktop & Screen Saver · Dock · Mission Control (Spaces, Hot Corners, Windows) · Language & Region · Security & Privacy · Notifications |
| hardware | Displays (Displays, Night Shift, Color) · Energy Saver · Keyboard · Mouse · Trackpad (touchpad y gestos) · Printers & Scanners · Sound |
| internet | Internet Accounts · Software Update · Network · Bluetooth · Extensions (applets, desklets, extensions, actions) |
| sistema | Users & Groups (con Login Items) · Date & Time · Time Machine · Accessibility |
| advanced | un solo botón, «Advanced», que abre el cinnamon-settings de Mint con todo lo que Catalina no tiene (Disks, Firewall, Fingerprints…) |

Un panel sin ningún módulo disponible no sale. Los que son un programa externo
(Dock, Software Update, Time Machine, impresoras, Bluetooth…) lo lanzan y la
ventana se queda donde estaba. Un panel con varios módulos (Desktop & Screen
Saver) muestra una pestaña por módulo, y si el módulo trae sus propias pestañas
salen debajo.

## Los íconos y glifos de Apple

Son de Apple: **nunca van al repo**. `desde-mac.sh` los saca del disco de la Mac,
en solo lectura, a `~/.local/share/mint-macos/settings/`:

- `iconos/<identificador>.png`: el de cada panel (36 de 38). Los que Apple guarda
  dentro de un catálogo (`Assets.car`: General, Internet Accounts, Spotlight) salen
  con `tema/iconos/car.py`, que no necesita macOS.
- `glifos/`: atrás, adelante y Show All (`GoBack`, `GoForward`, `ToolbarTopSites`),
  en negro; la app los pinta del color que toque.
- `orden.json`: los grupos de Catalina tal como los define la Mac.

Sin ellos la app se ve igual, con los íconos del tema.

## Cómo está hecho

- `preferencias.py`: la ventana. Importa `cinnamon-settings.py` como módulo, instancia
  cada `Module(content_box)` y usa su `SidePage.build()` para llenar la página.
  Además de la caja de contenido, esos módulos esperan dos cosas de la aplicación
  principal, que aquí se dan: `stack_switcher` (cs_themes y cs_gestures lo
  esconden en el modo simplificado) y la llamada a `on_navigate_out_of_module`
  al salir.
- `paneles.py`: la tabla de paneles y qué módulos de Cinnamon sirve cada uno.
- `estilo/catalina.css`: el aspecto. Es lo único que cambiaría con otro tema.
- Si Cinnamon cambia y el motor no carga, se abre `cinnamon-settings` y el usuario
  no se queda sin ajustes.

La lógica y el aspecto van separados a propósito: el tema pasará a Sequoia y la
ventana de Sequoia (barra lateral con buscador, grupos redondeados) será otro
estilo sobre el mismo motor.

## Lo que falta

- **Medir contra la Mac.** Las medidas son provisionales (668 de ancho, íconos de 40,
  8 por fila). Hace falta una captura de la ventana de System Preferences de la
  Mac de José, y de un par de paneles, para ajustarla al píxel como el dock.
- **El menú Apple** (`System Preferences…`) y el Dock siguen abriendo
  `cinnamon-settings`: cambiarlos es del applet y del Dock, no de esta app.
- La barra de menús global con el menú View con la lista de paneles (⌘1…).
- El arranque en esta máquina de prueba tarda 25 s por los portales de escritorio
  que ahí no corren; en la sesión real los módulos cargan en 0,3 s.
- Displays y Network muestran un panel vacío si Cinnamon no está detrás (solo pasa
  en pruebas aisladas).

## Decisión de José (14-10-2026)

- La cuadrícula lleva solo los paneles que Catalina tiene, más «Advanced» (el
  cinnamon-settings de Mint). Los íconos del tema se fuerzan al mismo tamaño que los demás.
- El primero ya es así: Dock (propios.py). Cada panel escribirá en el archivo de configuración del programa
  (Plank, por ejemplo) en vez de traer la interfaz de ese programa. Se trabaja panel por panel.
