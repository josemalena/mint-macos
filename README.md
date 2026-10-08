# mint-macos

Ajustes para que Linux Mint (Cinnamon) se maneje como macOS: la tecla
Super hace de ⌘ y Alt de ⌥, en el escritorio, en kitty y en VS Code, y el
panel lleva el menú Apple y el nombre de la aplicación activa.

## Qué hay

| Carpeta | Qué lleva | Dónde va |
|---|---|---|
| `cinnamon/` | Atajos del escritorio y fuentes de entrada (dconf) | `/org/cinnamon/desktop/keybindings/`, `input-sources/` |
| `kitty/macos-keys.conf` | ⌘T, ⌘W, ⌘⏎, ⌘←/→ entre pestañas, ⌥←/→ y ⌥⌫ por palabra | `~/.config/kitty/`, incluido desde `kitty.conf` |
| `vscode/keybindings.json` | ⌘N/O/S/W, ⌘P, ⌘⇧P, ⌘F, ⌘/, ⌘D, ⌥ por palabra | `~/.config/Code/User/` |
| `applets/` | `applemenu@macos` (menú Apple, Force Quit) y `appmenu@macos` (app activa, Quit) | `~/.local/share/cinnamon/applets/` |

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

## Lo que falta

- **⌘C / ⌘V / ⌘Z en todas las aplicaciones.** Hoy funcionan en kitty y VS
  Code porque cada uno tiene su mapa. En Chrome, el explorador de archivos
  y las demás, copiar sigue siendo Ctrl+C. Para que sea global hace falta
  un reasignador a nivel de teclado (keyd, Toshy o xremap), que traduce
  ⌘ a Ctrl salvo en las terminales.
