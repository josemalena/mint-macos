# Perfiles de versión de macOS

Un solo programa por pieza (Fynder, el Dock, Spotlyte, la barra de menús, el menú Apple, App
Store, System Preferences, Activity Monitor…) y **un perfil por versión de macOS** que dice cómo
es su interfaz y cómo se comporta en esa versión. La pieza no lleva literales de una versión:
pregunta al perfil de la versión escogida. Decisión de José, 18-10-2026: «extraer diseño de
interfaz de usuario y no crear un programa diferente para cada versión».

## Qué versión: una sola, global

- Se escoge en System Preferences («macOS version»). Vale para todas las piezas.
- El cambio vale **al volver a entrar** (José, 18-10-2026). La escogida se guarda en
  `~/.config/mint-macos/macos.json` (`{"version": "sequoia-15.8.1"}`); al entrar,
  `mint-macos-version --aplicar` la copia a `$XDG_RUNTIME_DIR/mint-macos/macos.json`, que es la
  **activa** y la que leen las piezas. Así una pieza que arranca a mitad de sesión ve la misma que
  las demás.
- Sin nada escogido, la activa es `catalina-10.15`.

## Dónde está

Los perfiles tienen textos, menús y medidas de Apple: **se generan en cada máquina** desde el
disco de la Mac o desde las referencias de `extraer-mac`, y **nunca van al repo** ni al paquete
publicado. En el repo están solo este esquema, el generador y las librerías.

```
~/.local/share/mint-macos/macos/
  catalina-10.15/
    version.json          id, nombre, número, de dónde salió cada parte
    medidas.json          medidas de la interfaz (barra de menús, letras, colores, semáforos)
    apps/
      menu-apple.json     el menú Apple
      menus-estandar.json los ítems que AppKit pone en todas las apps (menú de la app, Window…)
      <app>.json          lo de cada pieza (System Preferences, Activity Monitor…)
  monterey-12.7.6/ …
  sequoia-15.8.1/ …
  macos-27/ …
```

`perfiles/generar.py` los genera (`--version`, `--sistema` con una o varias raíces que tienen
`System/…`). Lo corre el instalador; se puede volver a correr cuando llegan referencias nuevas.

## Ids estables

Lo que cambia entre versiones es el texto, el orden, el atajo y si un ítem existe. Lo que **no**
cambia es el id, y por el id se pregunta:

| Origen | Id | Ejemplo |
|---|---|---|
| Menú Apple y menús de Carbon (HIToolbox, `StandardMenus.nib`) | `comando`, el código de 4 letras | `abtm` About This Mac, `sysp` System Preferences…/System Settings…, `apwn` Force Quit…, `lock` Lock Screen |
| Ítems de menú de AppKit (nib) | `accion`, el selector | `terminate:` Quit, `performClose:` Close, `showWindow:`/⌘, Preferences…/Settings… |
| Textos de SwiftUI y de los paneles | `clave`, la de la tabla de cadenas | `SHOW_SCROLL_TITLE` |
| Paneles de ajustes | el id del panel | `com.apple.preference.dock`, `com.apple.Desktop-Settings.extension` |

Una pieza que dibuja el menú Apple pregunta «el ítem `sysp`» y recibe «System Preferences…» en
Catalina y «System Settings…» en Sequoia, con su atajo y su lugar. Si en una versión el ítem no
existe, no viene.

## Formato de un menú

```json
{
  "id": "menu-apple",
  "items": [
    {"id": "abtm", "texto": "About This Mac", "fuente": "HIToolbox StandardMenus.nib; AppKit Menus.loctable"},
    {"id": "spro", "texto": "System Information…", "alterno_de": "abtm", "mods_alterno": "⌥"},
    {"separador": true},
    {"id": "sysp", "texto": "System Settings…"},
    {"id": "apwn", "texto": "Force Quit…", "atajo": "⌥⌘⎋"},
    {"id": "logo", "texto": "Log Out %@…", "atajo": "⇧⌘Q", "variables": {"%@": "nombre completo del usuario"}}
  ]
}
```

- `texto`: como se ve, con `%@` donde la Mac pone un nombre (`variables` dice cuál).
- `atajo`: como lo escribe la Mac (⌃⌥⇧⌘ y la tecla). Las piezas lo pasan a sus teclas (⌘ = Ctrl
  con keyd).
- `alterno_de`: el ítem aparece en lugar de ese otro mientras se aprieta ⌥ (System Information en
  lugar de About This Mac). `mods_alterno`: con qué teclas.
- `oculto`: existe pero la Mac no lo enseña salvo en un caso (Location, solo con más de una).
- `ocultar` (con `motivo`): lo quitamos nosotros, por adaptaciones.json («menus», `menu-apple:<id>`); no se enseña nunca.
- `icono`: en las versiones que ponen íconos en los menús (macOS 27), el nombre del símbolo.
- `fuente`: de qué archivo de la Mac salió, o `captura <archivo>` si lo dice una captura. **Si una
  captura contradice un archivo, gana la captura** y se anota.

## Formato de una interfaz (ventanas, paneles)

El mismo nodo que el visor (`herramientas/visor-nib`): `{"clase", "props", "hijos"}`, con un
vocabulario común a los nib (Catalina, Monterey) y a SwiftUI (Sequoia, 27): `ventana`,
`barra-herramientas`, `seccion`, `fila`, `boton`, `interruptor`, `casilla`, `selector`, `opcion`,
`deslizador`, `campo`, `texto`, `imagen`, `lista`, `tabla` (con `columnas`), `pestanas`,
`separador`, `grupo-v`, `grupo-h`, `espacio`. `props` lleva `id` (el estable), `texto`, `atajo`,
`marco` si se sabe, `opciones` de un selector, `condicional` si sale solo a veces. Esta parte entra
con el primer panel; el piloto son los menús.

## Comportamiento

`apps/<app>.json` lleva también `comportamiento`: números que cambian entre versiones (el rebote
del Dock al abrir y al pedir atención, las animaciones de Mission Control…), cada uno con su
`fuente`.

Las animaciones medidas en los videos (fase A, 27-10-2026) van en `apps/animaciones.json`, con esta forma:

```json
{"id": "animaciones", "medido": "2026-10-27", "precision": "un cuadro (16.7 ms), salvo el login (33 ms)",
 "comportamiento": {
   "launchpad-abrir": {"ms": 250, "rango_ms": "217-283", "curva": "easeIn (0.42,0,1,1)",
                       "escala_inicial": "~1.05 (hipótesis)", "fuente": "referencias/animaciones-medidas/launchpad/INDICE.md"}}}
```

- `ms`: la duración central; `rango_ms` cuando las tomas o las versiones difieren; `curva`: la más cercana de las curvas por omisión
  del motor (linear, easeIn, easeOut, easeInEaseOut, default; si ninguna coincide, se dice); `cuadros` cuando la animación es de uno o pocos cuadros.
- Lo que no se pudo medir **no se escribe**: una clave ausente significa «no medido», no «cero».
- Los números de cada animación se calculan con `animaciones-medidas/herramientas/` (local, como las referencias) y el generador
  (`generar-comportamiento.py`) los escribe en los perfiles; `perfiles/generar.py` no debe borrar `apps/animaciones.json` al regenerar.

## Librerías

- Python: `perfiles/macos_version.py` — `activa()`, `perfil(app)`, `menu(app, id_menu)`,
  `item(app, id_menu, id)`, `texto(app, clave)`, `medida('pantalla', 'alto_barra_menu_pt')`.
- Vala: `perfiles/vala/perfil-macos.vala` — lo mismo con Json-GLib, para las piezas nativas.
- Las dos leen la versión activa una vez al arrancar (el cambio vale al volver a entrar).
