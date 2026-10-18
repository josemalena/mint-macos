# org.mintmacos.Menu1: el menú de la app al frente, sin que el applet lea nada

**Estado (18-10-2026): borrador para revisión de Infra, sin implementar.** Hoy `globalmenu@macos` (668 líneas de JS) y
`dbusmenu.js` (275) leen los dos protocolos de menú dentro del proceso de Cinnamon: org.gtk.Menus + org.gtk.Actions
(GMenuModel) y com.canonical.dbusmenu. Un D-Bus lento o una app colgada congela el panel. Aquí lo lee un servicio y el
applet solo dibuja lo que recibe.

## Dónde vive

| | |
|---|---|
| Proceso | `mac-ventanas --residente` (ya está residente, ya usa GTK/GIO; un proceso menos). Si la medición no conviene, un residente aparte con el mismo nombre y activación por D-Bus |
| Bus | de sesión |
| Nombre | `org.mintmacos.Menu1` |
| Objeto | `/org/mintmacos/Menu1` |
| Interfaz | `org.mintmacos.Menu1` |
| Lenguaje | Vala + GIO (`GDBusMenuModel`, `GDBusActionGroup`) y `libdbusmenu-glib` para el otro protocolo; no se reescribe ninguno de los dos |

El servicio **no sigue el foco**: el applet ya lo sigue (con los casos del escritorio de Fynder, las ventanas internas y
el foco nulo) y pide por `xid`.

## Conceptos

- `xid` (`u`): la ventana X11 de la app, la misma de `Meta.Window.get_xwindow()`.
- `id` (`s`): identificador **opaco** de un ítem dentro de esa ventana (hoy una ruta de índices, «2.0.5»). Solo vale
  para la ventana y la versión del menú en la que se pidió; si el menú cambia llega la señal.
- Fuentes, en este orden: **`gtk`** (`_GTK_UNIQUE_BUS_NAME` + `_GTK_MENUBAR_OBJECT_PATH` de la ventana; incluye las apps
  que exportan con appmenu-gtk-module, cuya barra viene envuelta en dos secciones sin etiqueta: el servicio las aplana),
  **`dbusmenu`** (el registrador `com.canonical.AppMenu.Registrar`: Firefox, Thunderbird, Chrome, Edge, Electron, Qt) o
  **`ninguna`**. Si GTK no da ningún menú pintable y hay dbusmenu, gana dbusmenu (el caso de Firefox con el módulo).

## Ítem (`a{sv}`)

Las claves que no tienen dato **no vienen**.

| clave | tipo | |
|---|---|---|
| `id` | s | |
| `tipo` | s | `item`, `separador` o `submenu` |
| `etiqueta` | s | ya limpia: sin `_` de acelerador (`«__»` queda como `«_»`) |
| `activo` | b | el estado de la acción en ese momento (GTK) o `enabled` (dbusmenu) |
| `marca` | s | `check` o `radio`; no viene si no es de marca |
| `marcado` | b | solo con `marca` |
| `atajo` | s | **ya con la forma de la Mac** («⌘N», «⇧⌘Z», «^⌘F» si el original lleva `x-constanza-accel`). Lo da el servicio: hoy lo hace `atajoBonito` en JS |
| `icono` | s | un GIcon como lo da `g_icon_to_string` (nombre de tema o ruta); no viene si no hay |
| `hijos` | aa{sv} | solo en `submenu` y solo desde `Abrir`: el árbol completo hasta 4 niveles, con las secciones aplanadas y un `separador` entre ellas |

## Métodos

| Método | Entrada | Salida | |
|---|---|---|---|
| `Fuente` | `u xid` | `s` | `gtk`, `dbusmenu` o `ninguna`. Barato: no espera nada |
| `Barra` | `u xid` | `aa{sv}` | Los menús de arriba (File, Edit…): `id`, `etiqueta`, `activo`. Espera a que el modelo se asiente (máx. 400 ms) y devuelve lo que haya. Vacío si no hay menú; `BarraCambio` avisa cuando cambie |
| `Abrir` | `u xid, s id` | `aa{sv}` | Los ítems de ese menú, con `hijos`. En dbusmenu llama antes a `AboutToShow` (Chrome, Firefox y Electron arman el menú al abrirlo) y devuelve lo que ya sabe si la app tarda más de 150 ms; lo demás llega por `ArbolCambio` |
| `Cerrar` | `u xid, s id` | — | Avisa a la app (dbusmenu `Event closed`). En GTK no hace nada |
| `Activar` | `u xid, s id` | `b` | Ejecuta el ítem: la acción de GTK con su objetivo (o cambia el estado de un check o de un radio), o el `Event clicked` de dbusmenu. `false` si el `id` ya no existe |
| `MenuApp` | `u xid` | `aa{sv}` | El menú propio de la app (el marcado `x-constanza-app-menu`, que hoy lee `appmenu@macos` para su desplegable). Mismo formato; vacío si no trae |

## Señales

| Señal | Argumentos | |
|---|---|---|
| `BarraCambio` | `u xid` | los menús de arriba cambiaron (llegaron, o la app los rehízo). El applet vuelve a pedir `Barra` |
| `ArbolCambio` | `u xid, s id` | el contenido de ese menú cambió estando abierto; el applet vuelve a pedir `Abrir` |

El servicio se suscribe a `items-changed` / `LayoutUpdated` solo de las ventanas por las que le han preguntado, y las suelta
cuando la ventana se cierra (`wnck`) o pasan 2 min sin preguntas.

## Errores

`org.mintmacos.Menu1.Error.SinMenu` (la ventana no existe o no publica nada) en `Abrir`, `Cerrar`, `Activar` y `MenuApp`;
`Barra` devuelve vacío en vez de error.

## Lo que el servicio no hace

- No sigue el foco ni decide qué ventana manda (lo decide el applet).
- No dibuja nada ni conoce Cinnamon.
- No guarda menús de ventanas cerradas ni cambia el texto de los ítems (salvo limpiar el `_`).
- No arranca apps ni toca sus acciones salvo por `Activar`.

## Pruebas previstas

Caso con xed (GTK/appmenu-gtk-module: barra en dos secciones), un `Gio.Menu` exportado con submenús, y un servidor dbusmenu
falso (el formato de Firefox: `AboutToShow` antes de abrir). Lo mismo que cubren hoy los casos 41 y 46 pero contra la interfaz.
