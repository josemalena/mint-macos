# org.mintmacos.Menu1: el menú de la app al frente, sin que el applet lea nada

**Estado (18-10-2026): revisado por Infra (visto bueno con siete cambios, ya incorporados), sin implementar.** Hoy `globalmenu@macos` (668 líneas de JS) y
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
| `id` | s | válido solo con la `version` con la que se pidió |
| `tipo` | s | `item`, `separador` o `submenu` |
| `etiqueta` | s | ya limpia: sin `_` de acelerador (`«__»` queda como `«_»`) |
| `activo` | b | el estado de la acción en ese momento (GTK) o `enabled` (dbusmenu) |
| `marca` | s | `check` o `radio`; no viene si no es de marca |
| `marcado` | b | solo con `marca` |
| `atajo` | s | **ya con la forma de la Mac** («⌘N», «⇧⌘Z», «^⌘F» si el original lleva `x-constanza-accel`). Lo da el servicio: hoy lo hace `atajoBonito` en JS. Con keyd: lo que la app dice Ctrl+X se ve «⌘X»; «^⌘» es Ctrl+Super; las excepciones por app (en Edge, Chrome y Chromium ⌘Q manda Ctrl+Shift+Q, y su Quit sale «⌘Q», no «⇧⌘Q») se leen de `~/.config/keyd/app.conf`, no se copian |
| `icono` | s | un GIcon como lo da `g_icon_to_string` (nombre de tema o ruta); no viene si no hay |
| `hijos` | aa{sv} | solo en `submenu` y solo desde `Abrir`: el árbol completo hasta 4 niveles, con las secciones aplanadas y un `separador` entre ellas |

## Métodos

| Método | Entrada | Salida | |
|---|---|---|---|
| `Fuente` | `u xid` | `s` | `gtk`, `dbusmenu` o `ninguna`. Barato: no espera nada |
| `Barra` | `u xid` | `(u, aa{sv})` | (`version`, los menús de arriba: `id`, `etiqueta`, `activo`). Espera a que el modelo se asiente (máx. 400 ms, **asíncrono en el main loop**: no congela los otros residentes de mac-ventanas) y devuelve lo que haya. Vacío si no hay menú; `BarraCambio` avisa cuando cambie |
| `Abrir` | `u xid, s id` | `(u, aa{sv})` | (`version`, los ítems de ese menú, con `hijos`). En dbusmenu llama antes a `AboutToShow` (Chrome, Firefox y Electron arman el menú al abrirlo), asíncrono, y devuelve lo que ya sabe si la app tarda más de 150 ms; lo demás llega por `ArbolCambio`. Cuenta una apertura por (xid, id, remitente) |
| `Cerrar` | `u xid, s id` | — | Cierra la apertura de ese remitente. El `Event closed` de dbusmenu sale solo cuando cierra el **último** que lo tenía abierto; si un cliente se va del bus cuenta como que cerró lo suyo. En GTK no hace nada |
| `Activar` | `u xid, u version, s id` | `b` | Ejecuta el ítem: la acción de GTK con su objetivo (o cambia el estado de un check o de un radio), o el `Event clicked` de dbusmenu. Si la `version` ya no es la vigente da `Error.Vencido` y **no ejecuta nada** (la app pudo rehacer el menú entre el clic y la llamada); `false` si el `id` no existe |
| `Buscar` | `u xid, s texto` | `aa{sv}` | Los ítems cuya etiqueta contiene el texto (sin distinguir mayúsculas), en cualquier menú, para el Help de la Mac y para Spotlyte. Cada uno trae el ítem de siempre más `ruta` («Edit ▸ Find ▸ Find…»), `version` e `id` para `Activar`. Un texto vacío trae todos los ítems; incluye los del menú propio de la app (ruta «Application ▸ …»). En dbusmenu hace antes `AboutToShow` de los menús de arriba, con el mismo límite de 150 ms |
| `MenuApp` | `u xid` | `aa{sv}` | El menú propio de la app (el marcado `x-constanza-app-menu`, que hoy lee `appmenu@macos` para su desplegable). Mismo formato, con `version` en cada ítem (para `Activar`); vacío si no trae |

## Señales

| Señal | Argumentos | |
|---|---|---|
| `BarraCambio` | `u xid` | los menús de arriba cambiaron (llegaron, o la app los rehízo). El applet vuelve a pedir `Barra` |
| `ArbolCambio` | `u xid, s id` | el contenido de ese menú cambió estando abierto; el applet vuelve a pedir `Abrir` |

El servicio se suscribe a `items-changed` / `LayoutUpdated` solo de las ventanas por las que le han preguntado, y las suelta
cuando la ventana se cierra (`wnck`) o pasan 2 min sin preguntas.

## Errores

`org.mintmacos.Menu1.Error.SinMenu` (la ventana no existe o no publica nada) en `Abrir`, `Cerrar`, `Activar` y `MenuApp`;
`org.mintmacos.Menu1.Error.Vencido` en `Activar` cuando la `version` no coincide;
`Barra` devuelve vacío en vez de error.

## Lo que el servicio no hace

- No sigue el foco ni decide qué ventana manda (lo decide el applet).
- No sirve en Wayland: el `xid` ata esto a X11; con Wayland la clave sería otra.
- No se fía solo de las señales del registrador: si se reinicia, las apps no se vuelven a registrar, así que pregunta por `xid` (`GetMenuForWindow`) cuando hace falta. Si una app se va del bus sin desregistrar, el registrador emite `WindowUnregistered`.
- No dibuja nada ni conoce Cinnamon.
- No guarda menús de ventanas cerradas ni cambia el texto de los ítems (salvo limpiar el `_`).
- No arranca apps ni toca sus acciones salvo por `Activar`.

## Medidas previstas

RSS de `mac-ventanas` antes y después (hoy 41 MB); la espera de `Barra` y de `AboutToShow` no congela ⇧⌘5 ni Force Quit (caso que los usa mientras un dbusmenu falso tarda 1 s).

## Pruebas previstas

Caso con xed (GTK/appmenu-gtk-module: barra en dos secciones), un `Gio.Menu` exportado con submenús, y un servidor dbusmenu
falso (el formato de Firefox: `AboutToShow` antes de abrir). Lo mismo que cubren hoy los casos 41 y 46 pero contra la interfaz.
