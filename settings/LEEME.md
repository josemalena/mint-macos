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

## La ventana

Una barra **unificada**: un `GtkHeaderBar` (CSD) con los semáforos a la izquierda
(los pinta el tema, `headerbar button.titlebutton`), atrás/adelante y Show All, el
título al centro (sigue al panel abierto) y el buscador a la derecha. Muffin solo la
mueve. Las medidas (barra de 37 px, botones de 27×21, buscador de 158) salen de la
captura `Screen Shot 2026-10-14 at 12.07.52 AM` de Catalina, donde 1 px = 1 pt.

## Los paneles

Tres bloques, como los dibuja Catalina (no los cinco grupos del XML de Apple: esas
son etiquetas, no bandas; el orden sale de la captura):

| Bloque | Paneles |
|---|---|
| 1 | General (Themes, Fonts, Animations, Default Apps, Menu Bar) · Desktop & Screen Saver · **Dock** · Mission Control (Spaces, Hot Corners, Windows) · Language & Region · Notifications · Internet Accounts · Users & Groups (con Login Items) · Accessibility · Extensions · Security & Privacy |
| 2 | Software Update · Network · Bluetooth · Sound · Printers & Scanners · Keyboard · Trackpad · Mouse · Displays (Displays, Night Shift, Color) · Energy Saver · Date & Time · Time Machine · **Startup Disk** |
| 3 | «Advanced»: abre el cinnamon-settings de Mint con todo lo que Catalina no tiene (Disks, Firewall, Fingerprints…) |

Un panel sin ningún módulo disponible no sale. Los que son un programa externo
(Software Update, Time Machine, impresoras, Bluetooth…) lo lanzan y la ventana se
queda donde estaba. Un panel con varios módulos (Desktop & Screen Saver) muestra una
pestaña por módulo. Siri y Screen Time están como esqueleto en gris (`ausentes.py`); Profiles y CDs & DVDs no salen. **Apple ID** no está en la cuadrícula: se abre con el ícono de la
franja de arriba.

### Paneles propios (`propios.py`)

Escriben directo en la configuración del programa, en vez de traer su interfaz:

- **Dock**: Size, Magnification, Position, Minimize windows using (Genie/Scale: la
  extensión Magic Lamp), Minimize into application icon, Animate opening applications,
  Automatically hide and show, Show indicators y Show recent applications. Lo escribe
  en el dconf de Plank y en su `dock.theme` (el valor de antes se respalda para
  poder volver).
- **Spotlyte** (con el ícono de Spotlight de Catalina): los ajustes de Spotlyte, nuestro fork de
  Ulauncher, en su `~/.config/ulauncher/settings.json`: atajo (⌘Space, ⌃Space, ⌥Space, ⌥⌘Space),
  en qué pantalla sale, apps recientes, el ícono en la barra de menús y borrar la búsqueda al perder
  el foco. Spotlyte lee su configuración al arrancar, así que cada cambio lo reinicia con los mismos
  argumentos. Las categorías de resultados y Privacy de Catalina no están: Spotlyte no las tiene.
- **Apple ID**: el estado de iCloud Drive y de Mail y Calendar (abajo).
- **Mission Control**: «Displays have separate Spaces» (`workspaces-only-on-primary` de Muffin), los
  atajos de la extensión `misioncontrol@macos` (solo de lectura) y el botón **Hot Corners…**, que abre la
  hoja de las cuatro esquinas y escribe `hotcorner-layout` de `org.cinnamon`. Acciones: Mission Control
  (`scale`), Desktop (`desktop`), Launchpad, Start Screen Saver, Put Display to Sleep, Lock Screen, y
  Application Windows y Notification Center, que Cinnamon corre por `Eval` sobre ganchos que publican la
  extensión y el applet `notificaciones@macos` (`global.mintMacosAppWindows()`,
  `global.mintMacosNotificationCenter()`); esos dos pedirán reiniciar Cinnamon (o ReloadXlet) tras
  actualizar. Las otras opciones de Catalina (Automatically rearrange Spaces, Group windows by
  application…) no están: Cinnamon no las tiene.
- **Keyboard** (`teclado.py`): las cinco pestañas de Catalina. Keyboard: Key Repeat y Delay Until Repeat
  (los pasos de Catalina, escritos en `org.cinnamon.desktop.peripherals.keyboard`), Modifier Keys…
  (abajo) y Set Up Bluetooth Keyboard… (abre Bluetooth). Shortcuts: la lista de categorías de Catalina; hoy solo
  trae contenido Spotlight (el atajo de Spotlyte). Input Sources: las distribuciones de teclado
  (`org.gnome.libgnomekbd.keyboard`). Lo que Linux no tiene (Text, Dictation, el visor de emojis, Show Finder
  search window) se dibuja como en la captura pero en gris, como en una Mac sin esa función.
- **Mouse y Trackpad** (`raton.py`): Natural scroll, Tracking speed, Double-Click speed y el botón principal
  (`org.cinnamon.desktop.peripherals.mouse`); Scrolling speed en gris. Sin touchpad, Trackpad es la pantalla
  «No trackpad found» de Catalina; con uno lo sirve el módulo de Cinnamon.
- **General** (`general.py`): Default web browser (`xdg-settings`) y Show scroll bars; Appearance solo con el
  tema oscuro, y lo demás en gris. Las miniaturas Light/Dark/Auto las arma `apariencia.py` con los cuadros claro y
  oscuro de Catalina.heic (los que marca su metadato XMP).
- **Sound** (`sonido.py`): Output e Input por `pactl` (dispositivo, Balance, volumen, Mute) y los efectos de
  interfaz por `org.cinnamon.desktop.sound`. Las alertas (Basso, Blow…) salen del disco de la Mac con `desde-mac.sh`.
- **Displays** (`pantallas.py`): Rotation y Refresh Rate por el DisplayConfig de Cinnamon con vuelta atrás a los
  15 s; Color (colord) y Night Shift (`org.cinnamon.settings-daemon.plugins.color`).
- **Desktop & Screen Saver** (`escritorio.py`): la cuadrícula de fondos de Apple (Desktop Pictures y Colors) y
  las carpetas del usuario, Change picture / Random order (slideshow de Cinnamon), Start after, Show with
  clock y Hot Corners…. Los fondos salen del disco de la Mac con `fondos.py` (49 fotos y 19 colores, ~30 MB, a
  `~/.local/share/mint-macos/fondos`); los protectores de Apple van en gris.
- **Notifications** (`avisos.py`): todo en gris, como una Mac sin esa función (Cinnamon no filtra por app).
- **Date & Time** (`fecha.py`): timedatectl con el candado por polkit y el formato del reloj de la barra.
- **Energy Saver** (`energia.py`): Computer sleep y Display sleep (`...plugins.power`); lo demás en gris.
- **Software Update** (`actualizaciones.py`): estado de `apt` y de Update Manager, con Advanced….
- **Bluetooth** (`bt.py`): BlueZ por D-Bus (encender, apagar, conectar los dispositivos emparejados).
- **Sharing** (`compartir.py`): Remote Login (ssh), File Sharing (smbd) y Printer Sharing (cupsctl) por un
  ayudante de root con polkit (abajo).
- **Printers & Scanners** (`impresoras.py`): CUPS (lista, predeterminada, compartir).
- **Startup Disk**: arranque EFI y entrada por defecto de GRUB (abajo).

## Apple ID: iCloud Drive, Mail y Calendar

La franja de arriba muestra «Sign in to your Apple ID» con un botón Sign In, o el
nombre y el Apple ID con sesión; el ícono de Apple ID a la derecha abre el panel.
Sign In (`apple_id.py`) es una hoja en dos pasos:

1. **Apple ID, clave y código de verificación** (2FA): lo crea con `rclone config
   create/update --non-interactive` para el remoto de iCloud Drive; la clave se ofusca
   con `rclone obscure` y nunca se guarda en claro.
2. **Contraseña de app** (la que se genera en appleid.apple.com): se guarda en el
   **llavero** (libsecret, esquema `org.mintmacos.AppleID`), nunca en un archivo de
   texto. Con ella se descubren los calendarios (CalDAV) y se configuran en
   **Thunderbird** las cuentas IMAP (`imap.mail.me.com:993`), SMTP
   (`smtp.mail.me.com:587`) y los calendarios, en un bloque marcado
   `mint-macos Apple ID` de `user.js`. Thunderbird tiene que estar cerrado; él no lee
   libsecret, así que pide esa misma contraseña la primera vez (y se marca «Use
   Password Manager»).

Sign Out desmonta iCloud Drive y quita ese bloque de Thunderbird; los archivos en
iCloud no se tocan. `MINT_APPLEID_PRUEBA=1` prueba todo con datos falsos (clave
«password», código «123456») sin tocar rclone, Thunderbird ni la red.

## Startup Disk

La lista son las entradas de arranque EFI (`efibootmgr`, que se lee sin root: Ubuntu
con GRUB, Mac OS X…); elegir una pone esa entrada primera en el `BootOrder`. «Restart…»
arranca con ella solo esa vez (`BootNext`) y reinicia. Aparte, un selector con las
entradas del propio GRUB para la que arranca por defecto. No hay Target Disk Mode.

Todo cambio lo hace un ayudante de root por `pkexec` (`startup-disk/`): el **candado**
pide la clave de administrador una vez (la acción de polkit es `auth_admin_keep`).
Sin instalarlo, el panel solo mira:

```
sudo settings/startup-disk/instalar-root.sh            # instala el ayudante y la acción de polkit
sudo settings/startup-disk/instalar-root.sh --quitar
```

El ayudante vive en `/usr/libexec/mint-macos/startup-disk`, con dueño root, y valida
cada argumento contra una lista cerrada. Para elegir una entrada de GRUB hace falta
`GRUB_DEFAULT=saved`: el panel ofrece «Enable…», que lo pone (con respaldo de
`/etc/default/grub`) y corre `update-grub`.

## Keyboard ▸ Modifier Keys

Reasigna Caps Lock, Control, Option y Command (cada una a Caps Lock, Control, Option, Command, Escape o
No Action) sobre **keyd**. El panel no escribe en `/etc`: se lo pide por `pkexec` a un ayudante de root
(`modifier-keys/`), que valida los cuatro argumentos, reescribe un bloque `[main]` delimitado por marcas en
`/etc/keyd/default.conf`, lo comprueba con `keyd check` y recarga; si keyd no recarga, devuelve el archivo
anterior. El primer respaldo queda en `/etc/keyd/default.conf.mint-macos.bak`.

```
sudo settings/modifier-keys/instalar-root.sh            # instala el ayudante y la acción de polkit
sudo settings/modifier-keys/instalar-root.sh --quitar   # los quita y deja las teclas por defecto
```

## Sharing: Remote Login, File Sharing y Printer Sharing

Se encienden y apagan por un ayudante de root (`sharing/`), como Startup Disk: el panel pide la clave por
`pkexec` y el ayudante valida el servicio contra una lista cerrada (ssh.socket/ssh.service, smbd y
`cupsctl --share-printers`). Su estado se lee sin root.

```
sudo settings/sharing/instalar-root.sh            # instala el ayudante y la acción de polkit
sudo settings/sharing/instalar-root.sh --quitar
```

## Los íconos y glifos de Apple

Son de Apple: **nunca van al repo**. `desde-mac.sh` los saca del disco de la Mac,
en solo lectura, a `~/.local/share/mint-macos/settings/`:

- `iconos/<identificador>.png`: el de cada panel (36 de 38). Los que Apple guarda
  dentro de un catálogo (`Assets.car`: General, Internet Accounts, Spotlight) salen
  con `tema/iconos/car.py`, que no necesita macOS.
- `glifos/`: atrás, adelante y Show All (`GoBack`, `GoForward`, `ToolbarTopSites`), en
  negro (la app los pinta del color que toque), y el candado cerrado y abierto
  (`LockLocked`, `LockUnlocked`, de `SecurityInterface.framework`).
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

La lógica y el aspecto van separados a propósito: el tema pasará a macOS 27 y la
ventana de macOS 27 (barra lateral con buscador, grupos redondeados) será otro
estilo sobre el mismo motor.

## Lo que falta

- **Paneles sin captura propia todavía:** Siri, Spotlight (Spotlyte), Screen Time y
  Sharing no existen aquí; los demás usan los módulos de Cinnamon con el aspecto de
  Catalina y se irán sustituyendo por paneles propios, uno por uno.
- **macOS 27:** una segunda pasada (la referencia es la Mac de José con macOS 27; decidido el 14-10-2026) sobre este mismo motor (barra lateral con
  buscador y contenido con su barra integrada).
- El arranque en una máquina de prueba tarda 25 s por los portales de escritorio que
  ahí no corren; en la sesión real los módulos cargan en 0,3 s.
- Displays y Network muestran un panel vacío si Cinnamon no está detrás (solo pasa en
  pruebas aisladas).

## Decisión de José (14-10-2026)

- La cuadrícula lleva solo los paneles que Catalina tiene, más «Advanced» (el
  cinnamon-settings de Mint). Los íconos del tema se fuerzan al mismo tamaño que los demás.
- El primero ya es así: Dock (propios.py). Cada panel escribirá en el archivo de configuración del programa
  (Plank, por ejemplo) en vez de traer la interfaz de ese programa. Se trabaja panel por panel.

## Residente (14-10-2026)

System Preferences también es residente: `instalar.sh` pone `~/.config/autostart/mint-macos-settings.desktop`
(`preferencias.py --residente`), que la deja armada y escondida al iniciar sesión (los módulos de Cinnamon ya
cargados, ~85 MB). `mac-settings` es un `sh` que llama por D-Bus a la acción `abrir` (con el panel pedido, o
vacío para la cuadrícula) y solo arranca Python si no hay proceso o si recibe una opción como `--lista`.
Cerrar la ventana la esconde, como en la Mac; al volver a abrirla aparece la cuadrícula. Medido en Xephyr: de
~900 ms a ~30 ms (la cuadrícula) y ~160 ms (un panel con su módulo). `--quitar` borra el arranque y termina el residente.
