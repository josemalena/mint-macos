# mint-macos

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

Atajos del escritorio que ya están:

- ⌘Tab / ⌘⇧Tab cambia de ventana; ⌘\` / ⌘⇧\` entre ventanas de la misma app.
- ⌘⇧Q cierra la sesión; ⌘⌃Q bloquea la pantalla.
- ⌘⇧4 captura un área y ⌘⇧5 una ventana, al portapapeles.
- Super+Espacio cambia entre el teclado español y el inglés.

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
