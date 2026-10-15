# mint-macos-ayudante

Un solo proceso residente de Python con GTK ya cargado, para las ventanas pequeñas que se piden con un
atajo y que antes arrancaban su propio Python (unos 250 ms solo en cargar GTK):

| Acción | Atajo | Ventana |
|---|---|---|
| `forcequit` | ⌥⌘⎋ y Apple ▸ Force Quit… | `applets/applemenu@macos/forcekill.py` |
| `captura` | ⇧⌘5 | `capturas/herramienta.py` (la barra de Catalina) |

El diálogo de Restart / Shut Down / Log Out (`applemenu.py`) se queda como está: es raro y trae su cuenta regresiva.

## Cómo funciona

- `ayudante.py --residente` arranca con la sesión (`~/.config/autostart/mint-macos-ayudante.desktop`), carga las dos
  ventanas desde donde las instala cada una y se queda oculto (~50 MB).
- Se le pide por D-Bus, sin arrancar Python: `gdbus call … org.gtk.Actions.Activate forcequit '[]' '{}'`.
  `forcekill.py` y `mac-captura herramienta` ya traen esa vía rápida al principio; si el ayudante no está, siguen de
  largo y abren su propia ventana, así que nada se rompe si el proceso muere.
- `mint-macos-ayudante forcequit|captura` hace lo mismo desde la terminal y, si el proceso no existe, lo levanta
  (`ayudante.py --accion NOMBRE`).
- Las ventanas se arman de nuevo en cada petición y se destruyen al cerrar: el proceso solo guarda GTK, el CSS y los íconos.

## Instalar y quitar

    ./instalar.sh            instala; copia forcekill.py, captura.sh y herramienta.py a donde el ayudante los lee
    ./instalar.sh --quitar   quita el arranque y el proceso (Force Quit y ⇧⌘5 vuelven a arrancar su Python)

Para probar sin instalar: `AYUDANTE_FORCEKILL=… AYUDANTE_HERRAMIENTA=… python3 ayudante.py --residente`.

## Medido (Xephyr, desde el atajo hasta la ventana visible)

| | Antes | Después |
|---|---|---|
| Force Quit | 449, 337, 390 ms | 132, 184, 101 ms (la primera vez, ~340) |
| Barra de ⇧⌘5 | 550, 368, 999 ms | 144, 147, 160 ms (94, 126, 179 en otra tanda) |
