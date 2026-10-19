# org.mintmacos.Apariencia1

General ▸ Appearance: Light, Dark y Auto, el color de acento y el de resaltado. José,
18-10-2026: cambian el tema activo de verdad.

- **Servicio:** `mint-macos-apariencia` (rust/apariencia), sin root.
- **Activación:** la arranca D-Bus; sin llamadas se va al minuto.
- **Bus y ruta:** bus de sesión, nombre `org.mintmacos.Apariencia1`, ruta `/org/mintmacos/Apariencia1`.

## Métodos

| Método | Devuelve | Qué hace |
|---|---|---|
| `Estado()` | `a{sv}` | La lista de claves está abajo |
| `Poner(s apariencia, s acento, s resaltado)` | `b` | Cambia lo que se le pasa. Un texto vacío deja lo que había y algo inválido devuelve `false` sin cambiar nada |

Lo que acepta `Poner`:
- `apariencia`: `light`, `dark` o `auto`.
- `acento`: uno de la lista `acentos` de `Estado`.
- `resaltado`: `acento` (el mismo color del acento) o un color `#RRGGBB`.

Lo que trae `Estado`:
- `apariencia`, `acento` y `resaltado`: lo escogido.
- `oscuro` (b): lo que está puesto ahora; en Auto depende de la hora.
- `tema`: el tema GTK que queda.
- `acentos` (as): los de la versión de macOS activa. Catalina tiene Blue, Purple, Pink, Red, Orange, Yellow, Green y Graphite; Multicolor llegó en Big Sur.
- `proximo_cambio` (x): solo en Auto, en segundos desde 1970 (UTC).

Señal: `Cambio()`, después de cada `Poner` que cambió algo.

## Qué cambia

- **El tema:** `org.cinnamon.desktop.interface gtk-theme`, `org.cinnamon.desktop.wm.preferences theme` y `org.cinnamon.theme name`.
  - Es `<Base>-<Oscuro|Claro>[-<Acento>]`, por ejemplo `Constanza-Claro-Green`.
  - La base es el tema de la versión de macOS activa (`version.json` del perfil): Constanza, Samana, ValleNuevo u Ozama.
  - Si esa base o esa variante no están construidas, cae a Constanza o a la variante azul.
- **El portal:** `org.x.apps.portal color-scheme` (`prefer-dark` o `default`), para las apps de GTK 4 y Flatpak.
- **El Dock:** `/org/mintmacos/muelle/docks/dock1/theme` (Muelle) y `/net/launchpad/plank/docks/dock1/theme` (el Plank de antes, mientras dure la vuelta atrás), un tema por apariencia; el acento no cambia el Dock.
- **El resaltado:** `~/.config/gtk-3.0/mint-macos-resaltado.css`, que el `gtk.css` del usuario importa en una línea marcada. Lo demás de ese archivo, como la línea de cinnamon-settings, no se toca.
- **Lo escogido:** se guarda en `~/.config/mint-macos/apariencia.json`.

## Auto, sin nada corriendo

1. Al ponerlo, calcula la próxima salida o puesta del sol con la ecuación de la salida del sol. La ubicación sale de la zona horaria del sistema en `zone1970.tab` (Santo Domingo: 18°28′ N, 69°54′ O), sin red ni GPS. Sin ubicación, el día va de 7:00 a 19:00.
2. Deja un temporizador del usuario, `systemd-run --user --unit=mint-macos-apariencia-auto --on-calendar=<UTC>`, que corre `mint-macos-apariencia --auto-ahora`.
3. Ese modo aplica lo que toca y programa el siguiente cambio.

Entre un cambio y otro no queda ningún proceso: solo el temporizador de systemd.

## Night Shift (19-10-2026)

Displays ▸ Night Shift y el interruptor del Notification Center. Schedule, From/to y Color Temperature los escribe la ventana directo en `org.cinnamon.settings-daemon.plugins.color` (`night-light-*`), como ya hace. El servicio pone lo que csd-color no trae:

| | |
|---|---|
| `NightShift() → a{sv}` | `activo` (b, lo que dice csd-color `NightLightActive`), `horario` (s: `off`, `custom` o `sunset`), `desde` y `hasta` (d, horas locales), `temperatura` (u, kelvin), `apagado_hasta_manana` (b) y, con el manual puesto, `manual_hasta` (x, segundos desde 1970) |
| `NightShiftManual(b encender) → b` | «Manual: Turn On Until Tomorrow». También el interruptor del Notification Center |

La casilla Manual va marcada cuando `activo` es true, igual que en la Mac.

**Fuente:** la guía de Catalina dice: «Select to turn on Night Shift; deselect to turn it off. Night Shift remains on until the next day or until you turn it off» ([Change Night Shift settings on Mac, 10.15](https://support.apple.com/guide/mac-help/mchl9d976e85/10.15/mac/10.15)).

**Encender fuera del horario:**
1. Anota el horario de antes en `~/.config/mint-macos/nightshift.json`.
2. Pone `night-light-schedule-mode=always`.
3. Deja el temporizador `mint-macos-nightshift-fin`, que al «día siguiente» corre `--nightshift-fin` y devuelve el horario. El «día siguiente» es:
   - con horario Custom, la hora «to»;
   - con Sunset to Sunrise, la salida del sol;
   - sin horario, las 7:00 (**hipótesis**: el «to» de fábrica de la Mac; la guía no dice la hora).
4. Mientras dura, `horario` enseña el de antes, no el `always`.

**Apagar:**
- con el manual puesto, devuelve el horario y para el temporizador;
- dentro del horario, pone `DisabledUntilTomorrow=true` de csd-color, que lo vuelve a encender solo la noche siguiente.

## Costo (18-10-2026)

- **RSS:** 3.8 MB mientras corre.
- **Sin llamadas:** se va a los 60 s.
- **Auto:** ningún proceso mientras espera.

## Pruebas

- `cargo test -p mint-macos-apariencia`: la salida y la puesta del sol en Santo Domingo, el nombre del tema por apariencia y acento, y Night Shift:
  - encender a las 15:00 con el horario de 20:00 a 6:00 lo deja hasta las 6:00 de mañana;
  - quitarlo devuelve el horario;
  - apagarlo dentro del horario usa DisabledUntilTomorrow;
  - sin horario dura hasta las 7:00.

  Con `APARIENCIA_NOCHE` haciendo de gsettings y de csd-color.
- `rust/apariencia/prueba.sh`: el servicio en un bus aparte, con `APARIENCIA_SIMULAR` para anotar los comandos en vez de correrlos y `APARIENCIA_AHORA` para fijar la hora.
