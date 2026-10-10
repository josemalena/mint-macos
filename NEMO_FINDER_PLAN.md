# Fork de Nemo con aspecto y comportamiento de Finder

**Estado: PLAN REVISADO por Planner (07-10-2026). Lo ejecuta una sesión nueva o Codex, no Dev ni Dev-2.** Lo redactó
Marketing a partir de una captura del Finder de Mojave en modo oscuro y del código
de Nemo (`linuxmint/nemo`, rama principal al 06-10-2026, `66eabf4`).

## Para qué

José usa sobre todo macOS e iOS; este host con Linux Mint Cinnamon es el único
Linux. `mint-macos` busca que pasar de uno a otro sea transparente (tema Mojave,
⌘Q, Ulauncher como Spotlight, APFS). El navegador de archivos es la pieza que más
se nota: el tema (`catalina.sh`) cambia colores y formas, pero no el
comportamiento.

## Decisiones de José

1. **Alcance: la Fase 1 (puntos 1 a 6; el 6, el formato de fecha, se sumó el mismo día).** Corrección de José del mismo día: lo
   que llamó «etiquetas» eran **los títulos de sección de la barra lateral**
   (Favorites, iCloud, Locations), que es el punto 3, **sin la sección Tags**. El
   punto 8 (etiquetas de archivos) queda fuera. También fuera, por ahora: la barra
   unificada con el título (CSD), «Agrupar por», compartir, y las vistas de columnas
   y de galería.
2. **Cada cambio es una opción en gsettings.**
3. **El fork es un binario propio, con otro nombre**, para que una actualización
   del sistema no lo pise ni lo mezcle con el Nemo de Mint.

## Lo que no hace falta programar

Sale del tema o ya existe en Nemo:
- **Colores, tipografía, alturas de fila y esquinas:** tema GTK. **La fuente es
  San Francisco, instalada en local por José** desde su propia copia (decisión
  del 07-10-2026, sabiendo que la licencia de Apple la limita a sus sistemas
  operativos). **Los archivos de SF nunca entran al repo** (es público en GitHub:
  sería redistribuirla). `catalina.sh` la usa si la encuentra instalada y, si no,
  cae en **Inter** (OFL), que sigue siendo la fuente por defecto del repo.
  Esto es de Infra, no del fork: Nemo toma la fuente del sistema.
- **Filas en cebra:** la lista ya activa `gtk_tree_view_set_rules_hint`
  (`nemo-list-view.c:2680`); el color lo da el tema.
- **Triángulos para desplegar carpetas en la lista:** ya es una opción
  (`gtk_tree_view_set_show_expanders`, `nemo-list-view.c:301`).
- **Semáforos a la izquierda:** CSS y `gtk-decoration-layout = close,minimize,maximize:`.

## El binario aparte: lo que hay que cambiar para que no choque con Nemo

Que el ejecutable se llame distinto no basta. Nemo se identifica en varios
sitios, y si el fork comparte alguno, las dos copias se pisan:

| Qué | Nemo de Mint | Fork (decidido por José, 07-10-2026) |
|---|---|---|
| Ejecutable | `nemo` | `fynder` |
| ID de aplicación (GApplication, D-Bus de instancia única) | `org.Nemo` | `io.github.josemalena.Fynder`. **Si se repite, abrir el fork abre el Nemo del sistema.** Sin la marca Kóralis: es una herramienta personal |
| Esquemas de gsettings | `org.nemo.*` | `io.github.josemalena.fynder.*`, con los ajustes propios y los heredados copiados |
| Archivo `.desktop` | `nemo.desktop` | `fynder.desktop` |
| Dónde se instala | `/usr` (apt) | **`/usr/local`** (Planner): así los esquemas en `/usr/local/share/glib-2.0/schemas` se encuentran sin variables de entorno. **Nunca `/usr`** |
| Escritorio (`nemo-desktop`) | lo dibuja Nemo | **el fork no lo dibuja**: se queda el del sistema |
| `org.freedesktop.FileManager1` (D-Bus de «mostrar en carpeta») | lo reclama Nemo | **El fork lo reclama solo si está puesto como predeterminado** (un ajuste); si no, se lo deja al de Mint. Probar «Mostrar en carpeta» desde Chrome y Firefox |
| Extensiones (`libnemo-extension`, nemo-python, acciones) | las del sistema | **El fork lee también `~/.local/share/nemo/actions`.** Las extensiones compiladas (nemo-python) no se cargan, y se acepta |

Después: hacerlo el administrador de archivos por defecto
(`xdg-mime default fynder.desktop inode/directory`), y revisar qué partes de
Cinnamon llaman a `nemo` por nombre (applet de lugares, «abrir carpeta»).
Lo instala un guion de `mint-macos`, como el resto del repo.

## Fase 1 (puntos 1 a 5), unos 5 a 10 días

Estimación de Marketing para alguien con C y GTK 3; Dev la corrige.

| # | Cambio | Dónde | Cómo | Ajuste gsettings | Esfuerzo |
|---|---|---|---|---|---|
| 1 | **Archivos ocultos atenuados** (los que empiezan por punto) | `nemo-list-view.c` (lo que pinta la celda del nombre) y la vista de íconos | Bajar la opacidad del texto y del ícono | `dim-hidden-files` | ½–1 día |
| 2 | **Texto de la barra de estado centrado** | `nemo-statusbar.c:160-225`: el `GtkStatusbar` va entre botones y el zoom | Etiqueta centrada; decidir si el zoom se esconde (el Finder no lo tiene) | `statusbar-centered`, `statusbar-show-zoom` | ½ día |
| 3 | **Barra lateral con las secciones del Finder**: **Favorites, iCloud y Locations** (sin Tags) | `nemo-places-sidebar.c`: «My Computer» (:779), «Bookmarks» (:928), «Devices» (:348), «Network» (:1240) | Renombrar y reordenar; «Favorites» une las carpetas del usuario con los marcadores; «iCloud» enseña el iCloud Drive montado (ver abajo); «Locations», los discos y la red | `sidebar-finder-sections` | 1–3 días |
| 4 | **Selector de vista segmentado** | `nemo-toolbar.c:355-361`: tres botones sueltos (íconos, lista, compacta) | Ponerlos en una caja `linked` para que el tema los pinte pegados | `toolbar-linked-view-switcher` | ½–1 día |
| 5 | **Búsqueda siempre visible a la derecha** | `nemo-toolbar.c:344` (botón) y `nemo-window-slot.c:389` (el editor de búsqueda vive en cada panel) | Un campo fijo en la barra que maneje la búsqueda del panel activo; cuidar el modo de dos paneles | `toolbar-search-entry` | 3–5 días |
| 6 | **Formato de fecha «finder»**: `Today, 9:48 PM` · `Yesterday, 9:48 PM` · `dd/mm/yyyy, 9:48 PM` (hora en 12 h con AM/PM; 24 h si `org.cinnamon.desktop.interface clock-use-24h` está encendido) | `libnemo-private/nemo-file.c` ~5206-5340 (`nemo_file_get_date_as_string`): hoy enseña solo la hora, ayer «Yesterday 9:48 PM», la semana con el día, el año con el mes en letras | Un valor nuevo en el enum de `date-format` (`finder`) en el esquema del fork; las demás opciones no cambian. Pedido de José, 07-10-2026 | `date-format = finder` | ½ día |

**Estado de la prueba gráfica (07-10-2026):**
- **Punto 6** (`39326479`): pasa. Con `finder`, la lista enseña `Today, 21:48`, `Yesterday, 21:48` y `04/10/2026, 09:05` (24 h porque el reloj está en 24 h). Con `informal`, sigue igual que en Nemo.
- **Punto 4** (`46ceaff8`): pasa. La caja `linked` se aplica, y el fondo del segmentado lo pone el CSS del tema (`fe64378`, hoy dentro del tema Constanza).

## La sección iCloud

En Linux no hay cliente oficial de iCloud Drive. Para que «iCloud» enseñe algo,
el iCloud Drive tiene que estar montado en este host (rclone tiene un conector de
iCloud Drive; versión y estabilidad por verificar). **Eso es de Infra, no del
fork.** El fork solo necesita una ruta configurable: si existe, sale la sección
«iCloud» con «iCloud Drive»; si no, la sección no aparece. Ajuste:
`sidebar-icloud-path`.

## Mantenimiento

- Cada cambio va detrás de su ajuste, **apagado por defecto**: el fork se comporta
  como Nemo hasta que se enciende, y actualizarlo con el Nemo original choca menos.
- Commits pequeños, uno por punto, para poder reaplicarlos sobre una versión
  nueva de Nemo.
- Los puntos 1 y 2 podrían proponerse al Nemo original.

## Decisiones tomadas (07-10-2026)

- **Nombre** (José, 10-10-2026, **reemplaza a `nemo-mac`**): **Fynder**. Ejecutable
  `fynder`, ID `io.github.josemalena.Fynder`, esquemas
  `io.github.josemalena.fynder.*`, `fynder.desktop`, sin la marca Kóralis. Es la
  alusión más directa al Finder (marca de Apple) con una letra cambiada: José lo
  eligió sabiendo que es la opción con algo de riesgo de marca, aceptable para una
  herramienta personal.
- **Nombre visible:** «Fynder» en el lanzador, «About», los menús y los mensajes
  (reemplaza a «Nemo Finder», que también usaba la marca entera).
- **Defaults** (José, 08-10-2026): el modo Finder viene **encendido por defecto** (`date-format=finder`, `toolbar-linked-view-switcher`, `toolbar-finder-layout`, `sidebar-finder-sections`), por `c66498d4`. Esto reemplaza la regla de «apagado por defecto» de Mantenimiento; los cambios siguen detrás de su ajuste.
- **Alcance** (José): Fase 1, puntos 1 a 6; sin etiquetas de archivos. Mientras
  tanto, el Nemo de Mint quedó con `date-format = informal`, lo más cercano.
- **Quién aplica el punto 6** (José): Codex.
- **Quién lo hace** (José): una sesión nueva o Codex; Planner prepara el encargo.
- **FileManager1** (Planner): lo reclama solo si el fork está como predeterminado.
- **Acciones** (Planner): se comparten; las extensiones compiladas no cargan.
- **Instalación** (Planner): `/usr/local`.
- **Código** (Planner): repo propio **`josemalena/nemo-mac`** (con el cambio de nombre, Planner decide si se renombra a `fynder`), fork de
  `linuxmint/nemo`. `mint-macos` trae solo el guion que lo compila e instala.
- **Pendiente de Infra:** montar iCloud Drive en el host (ruta para
  `sidebar-icloud-path`) y que `catalina.sh` use San Francisco si está instalada.
