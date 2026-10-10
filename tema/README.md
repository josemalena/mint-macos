# Constanza

Tema oscuro para Linux Mint (Cinnamon) con la apariencia del Finder de macOS
Catalina/Mojave: ventanas, panel, bordes con semáforos, dock, íconos y
fuentes. Reemplaza a `catalina.sh`.

```bash
./instalar.sh              # construye y activa (respalda lo actual)
./instalar.sh --construir  # solo construye, sin tocar la sesión
./instalar.sh --deshacer   # vuelve al último respaldo
```

| Carpeta | Qué hace | Dónde instala |
|---|---|---|
| `gtk/` | Compila Mojave-gtk-theme fijado y le agrega `_constanza.scss` | `~/.themes/Constanza-Oscuro`, Plank |
| `iconos/` | Os-Catalina con arreglos, y encima los íconos del Finder si hay disco de Mac | `~/.local/share/icons/Constanza` |
| `fuentes/` | Copia San Francisco (sistema, Compact y SF Mono) del disco de la Mac | `~/.local/share/fonts/san-francisco` |
| `fondo/` | Saca el fondo de Catalina del disco de la Mac: el cuadro 7 (atardecer) de `Catalina.heic`; `CUADRO=1` da la noche, el «oscuro» de Apple. Sin disco de Mac, el fondo no se toca | `~/.local/share/backgrounds/constanza/catalina.jpg` |
| `manzana/` | La manzana del menú Apple: el carácter U+F8FF de SFNS.ttf, en SVG blanco y PNG a 1x/2x (13×16 px), para `applemenu@macos`. Necesita antes las fuentes de `fuentes/` | `~/.local/share/constanza/manzana/apple-menu.svg` |
| `comun.sh` | Busca y monta en solo lectura el volumen de sistema de la Mac | — |

## Con disco de Mac y sin él

Si el disco de una Mac está conectado (APFS, se lee con `fsapfsmount`, ver
`../apfs/`), el instalador saca de ahí:

- **Íconos del Finder:** carpetas, documento genérico, ejecutable, fuentes,
  discos (interno, externo, extraíble, CD/DVD/BD), red, servidor, papelera y
  la Mac mini, a color; y los glifos del lateral pintados de gris.
- **San Francisco:** la de interfaz, títulos y documentos, y **SF Mono** para
  kitty (los glifos de Nerd Font del prompt siguen saliendo de MesloLGS NF).

Sin disco: Os-Catalina e Inter. Nada de Apple se guarda en el repo
(ver `CREDITOS.md` y el `.gitignore`).

## Requisitos

`sassc` y `glib-compile-resources` (`libglib2.0-dev-bin`) para compilar el
tema base; `python3-pil` e ImageMagick para los íconos; `fsapfsmount` para el
disco de la Mac.
