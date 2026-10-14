# /Applications

Como en la Mac: una carpeta con una entrada por aplicación y una subcarpeta
`Utilities` con las herramientas del sistema. Se arma sola a partir de los
lanzadores (`.desktop`) que Linux ya tiene instalados y se mantiene al día:
cuando se instala o se quita una app, systemd lo ve y la vuelve a armar en
unos segundos.

```
sudo install -d -o "$USER" -g "$(id -gn)" /Applications   # una sola vez
./instalar.sh                                              # el generador y el servicio
./instalar.sh --quitar                                     # deshace todo
```

`requisitos.sh` es el que crea `/Applications` al instalar el paquete, junto a
`/Users` y `/Volumes`; es una carpeta real y del usuario, no un enlace, para que
la ruta que ve Fynder sea literalmente `/Applications`.

## Cómo está hecho

Cada entrada es una **copia ejecutable** del `.desktop`, no un enlace. Fynder
solo muestra el nombre y el ícono de un lanzador si el archivo es ejecutable o
vive en una carpeta del sistema (`is_link_trusted`, en
`libnemo-private/nemo-directory-async.c`); un enlace a `/usr/share/applications`
sale como un archivo cualquiera con candado. En la copia solo cambia `Name=`:
lleva el nombre corto y el sufijo `.app`, porque la Mac de José muestra todas
las extensiones (Finder ▸ Preferences ▸ Advanced). Las copias conservan la fecha
del original, que es lo que Fynder enseña en «Date Modified».

Dos corridas seguidas no cambian nada. Lo único que el programa toca es lo que él
creó: la lista va en `.mint-macos-aplicaciones` dentro de la carpeta, y un archivo
del usuario nunca se pisa ni se borra.

## Qué entra

Entran las apps que Cinnamon mostraría en su menú (`should_show`: sin
`NoDisplay`, y con `OnlyShowIn` válido para Cinnamon), de `/usr/share`, el
usuario, Flatpak y Snap. No entran:

- los paneles de configuración de Cinnamon (`cinnamon-settings-*`,
  `cinnamon-*-panel`): son 50 y la Mac los junta en una sola app, que aquí es
  `cinnamon-settings` (System Settings);
- los programas de terminal (`Terminal=true`, `ConsoleOnly`);
- las piezas internas del escritorio y los duplicados de «el Finder»: Fynder,
  Nemo, Nautilus, Plank, Rofi;
- un segundo lanzador con el mismo nombre (VS Code instalado dos veces).

`Utilities` lleva lo que en Catalina vive en `/Applications/Utilities` (Activity
Monitor, Terminal, Disk Utility, Keychain Access…): las categorías `System`,
`Monitor`, `TerminalEmulator`, `Security`, `Filesystem`, `Archiving`, las de
ajustes que no son paneles (Update Manager, Software Sources…) y
`X-GNOME-Utilities`. `System Settings` y `Software Manager` se quedan arriba,
como `System Preferences` y la App Store.

## Ajustes

`~/.config/mint-macos/aplicaciones.conf`, una orden por línea:

```
ocultar   algo.desktop          # no entra
mostrar   algo.desktop          # entra aunque la regla lo deje fuera
arriba    algo.desktop          # va en /Applications, no en Utilities
utilities algo.desktop          # va en Utilities
nombre    algo.desktop  Nombre  # el nombre que se ve (sin el .app)
```

`aplicaciones.py --simular` dice qué haría sin escribir nada, y `--sin-sufijo`
quita el `.app` de los nombres.

## Probado (13-10-2026)

- 77 apps en esta máquina (47 arriba y 30 en Utilities); las 77 copias las lee
  GIO, su comando resuelve a un programa que existe y son ejecutables.
- Fynder, en una pantalla aparte, las enseña con el ícono de Catalina y el nombre
  «Firefox.app».
- Con el servicio instalado, una app nueva aparece en unos 4 segundos y una
  borrada desaparece sola; `--quitar` deja la carpeta como estaba.

## Lo que falta en Fynder

Es de la sesión de Fynder: que `/Applications` salga en la barra lateral
(Favorites), en el menú Go con ⇧⌘A y en el menú de Fynder del Dock. Lo demás de
la Mac (el tamaño de cada app en la lista, «Kind: Application») depende de que
Fynder lea el `.desktop`.
