# mint-macos

> **Para migrar a un usuario de macOS Catalina a Linux Mint, paso a paso:** [LEEME.md](LEEME.md)
> (`requisitos.sh` → `instalar.sh` → `migrar-datos.sh`).

Ajustes para que Linux Mint (Cinnamon) se maneje como macOS: la tecla
Super hace de ⌘ y Alt de ⌥, en el escritorio, en kitty y en VS Code, y el
panel lleva el menú Apple y el nombre de la aplicación activa.

## Qué hay

| Carpeta | Qué lleva | Dónde va |
|---|---|---|
| `keyd/` | ⌘ + letra → Ctrl + letra y ⌥←/→ por palabra en todo el sistema; excepciones por aplicación | `/etc/keyd/default.conf`, `~/.config/keyd/app.conf` |
| `apfs/` | Leer el disco de una Mac (APFS) en solo lectura por FUSE: instalador, helper de `mount`, ejemplo de fstab y recuperación | ver `apfs/README.md` |
| `cinnamon/` | Atajos del escritorio y fuentes de entrada (dconf) | `/org/cinnamon/desktop/keybindings/`, `input-sources/` |
| `kitty/macos-keys.conf` | ⌘T, ⌘W, ⌘⏎, ⌘←/→ entre pestañas, ⌥←/→ y ⌥⌫ por palabra | `~/.config/kitty/`, incluido desde `kitty.conf` |
| `vscode/keybindings.json` | Lo que keyd no traduce: ⌘⌥F, ⌘1…3, ⌘⇧[ ] | `~/.config/Code/User/` |
| `applets/` | `applemenu@macos` (menú Apple, Force Quit), `appmenu@macos` (app activa, Quit) y `globalmenu@macos` (la barra de menú de la ventana enfocada, para apps que la publican por D-Bus con el protocolo de GTK: `gtk_application_set_menubar`; nemo-mac con `global-menu` encendido) | `~/.local/share/cinnamon/applets/` |
| `menu-global/` | El lado de las apps del menú global: registrador `com.canonical.AppMenu.Registrar` como servicio de usuario y que las apps (GTK, Firefox, Thunderbird, Chromium/Electron, Qt) publiquen su menú; `install.sh` lo corre con `--sesion` y pide cerrar sesión. Detalle en su `LEEME.md` | servicio de usuario, `~/.xsessionrc` |
| `tema/` | Constanza: el tema (GTK, íconos, cursores, fondo, fuentes SF) con lo de Apple sacado de la Mac, nunca copiado al repo | `~/.themes`, `~/.local/share/icons/`, `~/.local/share/constanza/` (créditos en `tema/CREDITOS.md`) |
| `extensions/` | `cmdtab@macos` (⌘Tab), `misioncontrol@macos` (⌃↑ ⌃↓ ⌃← ⌃→) y `entrada@macos` (la espera al iniciar sesión); Magic Lamp con su parche. Detalle en su `LEEME.md` | `~/.local/share/cinnamon/extensions/` |
| `settings/` | System Preferences de Catalina (`mac-settings`): barra unificada, tres bloques de paneles sobre los módulos de Cinnamon, paneles propios (Dock, Apple ID con iCloud/Mail/Calendar, Startup Disk). Detalle en su `LEEME.md` | `~/.local/lib/mint-macos/settings`, `~/.local/bin/mac-settings` |
| `login/` | La pantalla de inicio de sesión de Catalina (`slick-greeter-mac`, fork de slick-greeter) con vuelta atrás `login-mac-revertir`. Detalle en su `LEEME.md` | `/usr/local/…`, `/etc/lightdm/` (con sudo) |
| `aplicaciones/` | `/Applications` como en la Mac, armada sola con una copia de cada `.desktop` y la subcarpeta `Utilities` | `/Applications`, servicio de usuario |
| `launchpad/` | El Launchpad: `/Applications` en pantalla completa sobre el fondo desenfocado, con buscador, páginas y la carpeta Other | `~/.local/bin/mac-launchpad` y el lanzador del Dock |
| `etiquetas/` | Las etiquetas del Finder sacadas de la Mac a una base local (`etiquetas.json`) | `~/.local/share/mint-macos/etiquetas/` |
| `icloud/` | iCloud Drive montado con rclone (`icloud.sh`), las apps web de iCloud y `esperar-icloud.sh` | servicio de usuario, `~/iCloud Drive` |
| `capturas/` | ⇧⌘3, ⇧⌘4, ⇧⌘5 y el selector de emojis ⌃⌘Espacio | atajos de Cinnamon, `~/.local/bin/` |

Atajos del escritorio que ya están:

- ⌘Tab / ⌘⇧Tab cambia de ventana; ⌘\` / ⌘⇧\` entre ventanas de la misma app.
- ⌘⇧Q cierra la sesión; ⌘⌃Q bloquea la pantalla.
- ⌘⇧3 captura la pantalla y ⌘⇧4 un área, al escritorio (con ⌃, al portapapeles); ⌘⇧5 abre la herramienta de captura.
- Super+Espacio cambia entre el teclado español y el inglés.

## Cómo se trabaja en este repo

- **Lo de Apple nunca entra al repo.** Íconos, glifos, fondos, fuentes y fotos se sacan
  del disco de la Mac, en solo lectura, con los `desde-mac.sh` de cada carpeta, a
  `~/.local/share/…`. Las capturas de referencia tampoco se commitean: se citan por
  nombre de archivo.
- **Antes de diseñar o dar algo por terminado, mirar las capturas de Catalina** y
  comparar el resultado al lado de la de referencia; si no hay captura, se pide, no se
  reconstruye de memoria (`CLAUDE.md`).
- **Turno de pantalla (`gui-lock`)**: antes de cualquier `xdotool`, `wmctrl`, clic o
  ventana nueva en la pantalla del usuario (`:0`), `~/.local/bin/gui-lock tomar <sesión>`
  y soltarlo al terminar. Lo que se pueda probar en Xephyr o Xvfb va ahí y no lo necesita.
- Los instaladores respaldan antes de tocar y traen su vuelta atrás (`--quitar`,
  `--deshacer` o un `volver.sh`).

## Instalar

```bash
./install.sh
```

Respalda todo lo que va a tocar en `~/.mint-macos-respaldo/<fecha>/`. No
reemplaza el `kitty.conf`: le agrega `include macos-keys.conf`. Los
applets se agregan al panel a mano en System Settings → Applets.

## Guardar lo que se ajustó a mano

Después de cambiar un atajo en System Settings, en kitty o en VS Code:

```bash
./capturar.sh   # trae los ajustes de esta computadora al repo
git diff
git commit -am "…"
```

## keyd: ⌘ en todas las aplicaciones

[keyd](https://github.com/rvaiya/keyd) intercepta el teclado por debajo
del escritorio. `install.sh` lo compila (v2.6.0; no está en los
repositorios de Mint 22) y lo deja como servicio.

- **⌘ + letra sale como Ctrl + letra**: ⌘C, ⌘V, ⌘Z, ⌘⇧Z, ⌘S, ⌘T, ⌘W, ⌘F,
  ⌘L, ⌘R… en Chrome, Edge, el explorador de archivos y VS Code.
- **⌘← ⌘→** van al inicio y al fin de la línea, **⌘↑ ⌘↓** al inicio y al
  fin del documento, **⌘⌫** borra hasta el inicio de la línea. Con ⇧
  seleccionan.
- **⌥← ⌥→** saltan por palabra y **⌥⌫** borra la palabra anterior.
- **Sin traducir**, para que Cinnamon las siga viendo como Super: ⌘Q (⌘⇧Q
  cierra sesión), ⌘H y ⌘M, los números, ⌘Tab, ⌘Espacio, ⌘⇧4 y ⌘⇧5.
- **kitty** recibe ⌘ y ⌥ tal cual (`keyd/app.conf`), así que sus atajos
  `cmd+…` y `opt+…` del `kitty.conf` siguen mandando. Las excepciones las
  aplica `keyd-application-mapper`, que arranca con la sesión.

Ojo:

- Cinnamon usa ⌘←/→/↑/↓ para acomodar ventanas; con keyd esas teclas
  pasan a ser de texto. Si se quiere acomodar ventanas, hay que darle
  otra combinación en System Settings → Keyboard → Shortcuts.
- Para que funcionen las excepciones por aplicación, el usuario tiene que
  estar en el grupo `keyd`: después de instalar hay que cerrar sesión y
  volver a entrar.
- Si el teclado se traba: **Backspace + Escape + Enter** a la vez detiene
  keyd.
- Ver qué tecla llega: `sudo keyd monitor`. Ver la clase de una ventana
  para `app.conf`: `wmctrl -lx` (va en minúsculas).
