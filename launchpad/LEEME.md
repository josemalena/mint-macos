# Launchpad

El Launchpad de Catalina: el contenido de `/Applications` (lo que arma
`aplicaciones/aplicaciones.py`, con los mismos nombres e íconos) en pantalla
completa sobre el fondo de escritorio desenfocado y oscurecido, con el buscador
arriba, la rejilla paginada de 7×5, los puntos de página abajo y la carpeta
**Other** con lo de `Utilities`.

```
./instalar.sh            instala mac-launchpad y reemplaza el lanzador de rofi de este usuario
./instalar.sh --quitar   devuelve el lanzador anterior y borra lo instalado
mac-launchpad            abre; ejecutarlo estando abierto lo cierra
mac-launchpad --lista    qué mostraría, sin abrir nada
```

**Atajo ⌥⌘L**: lo pone `instalar.sh` (y `--quitar` lo quita) como una entrada personalizada de
Cinnamon. keyd manda ⌘ como Ctrl, así que ⌥⌘L llega a Cinnamon como `<Control><Alt>l` (igual que ⌘⌥F
en VS Code); ese es el atajo registrado. Ojo: en Fynder ⌥⌘L es Downloads y el atajo del sistema lo
quita; si se prefiere dejarlo para Fynder, hay que cambiarlo en System Settings ▸ Keyboard ▸ Shortcuts.

El Dock (Plank) apunta a `~/.local/share/applications/launchpad.desktop`, que el
instalador reescribe; el anterior (rofi con `/usr/share/launchpad.sh`) queda en
`~/.local/share/mint-macos/respaldos/launchpad.desktop.antes`. No se toca nada de
`/usr/share`.

Teclas: escribir busca (palabras que empiezan con lo escrito), ←/→ cambian de
página o mueven el resaltado, Enter abre el resaltado, Esc borra la búsqueda, cierra
la carpeta o cierra el Launchpad; un clic en el vacío también lo cierra, y los
puntos o arrastrar/rueda cambian de página.

## Medidas

Salen de las capturas de José en Catalina del 14-10-2026 («Screen Shot … at 1.05.32
PM», 1.06.12, 1.11.15…; 1920×1200, 1 px = 1 px) y se escalan con la pantalla:
ícono 112, paso 215×193, buscador 250×23, puntos de 8 px cada 20, carpeta de 124 con
minis de 26, panel abierto de 1550 de ancho. El fondo es un gaussiano de ~30 px y,
por canal, `y = a·x + k` (ajustado contra la captura, error medio 1.6 de 255).
Las capturas son de Apple y no entran al repo; el glifo de la lupa y el de borrar
(`SearchMagGlass`, `Cancel`) salen de la Mac con `tema/iconos/finder.py`.

## Pendiente

- El Dock no se ve encima: la ventana es de pantalla completa, y en Muffin eso queda
  por encima de los docks.
- Reordenar con el ratón y crear carpetas no están (el orden es alfabético).
