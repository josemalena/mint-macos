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
pestaña por módulo. Faltan en Linux Siri, Spotlight, Screen Time, Sharing, Profiles
y CDs & DVDs. **Apple ID** no está en la cuadrícula: se abre con el ícono de la
franja de arriba.

### Paneles propios (`propios.py`)

Escriben directo en la configuración del programa, en vez de traer su interfaz:

- **Dock**: Size, Magnification, Position, Minimize windows using (Genie/Scale: la
  extensión Magic Lamp), Minimize into application icon, Animate opening applications,
  Automatically hide and show, Show indicators y Show recent applications. Lo escribe
  en el dconf de Plank y en su `dock.theme` (el valor de antes se respalda para
  poder volver).
- **Apple ID**: el estado de iCloud Drive y de Mail y Calendar (abajo).
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

La lógica y el aspecto van separados a propósito: el tema pasará a Sequoia y la
ventana de Sequoia (barra lateral con buscador, grupos redondeados) será otro
estilo sobre el mismo motor.

## Lo que falta

- **Paneles sin captura propia todavía:** Siri, Spotlight (Spotlyte), Screen Time y
  Sharing no existen aquí; los demás usan los módulos de Cinnamon con el aspecto de
  Catalina y se irán sustituyendo por paneles propios, uno por uno.
- **Sequoia:** una segunda pasada sobre este mismo motor (barra lateral con
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
