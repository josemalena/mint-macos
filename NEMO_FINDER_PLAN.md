# Fork de Nemo con aspecto y comportamiento de Finder

**Estado: PLAN para revisión de Planner → Dev (José, 07-10-2026).** Lo redactó
Marketing a partir de una captura del Finder de Mojave en modo oscuro y del código
de Nemo (`linuxmint/nemo`, rama principal al 06-10-2026, `66eabf4`).

## Para qué

José usa sobre todo macOS e iOS; este host con Linux Mint Cinnamon es el único
Linux. `mint-macos` busca que pasar de uno a otro sea transparente (tema Mojave,
⌘Q, Ulauncher como Spotlight, APFS). El navegador de archivos es la pieza que más
se nota: el tema (`catalina.sh`) cambia colores y formas, pero no el
comportamiento.

## Decisiones de José

1. **Alcance: la Fase 1 (puntos 1 a 5) y el punto 8 (etiquetas).** Fuera, por
   ahora: la barra unificada con el título (CSD), «Agrupar por», compartir, y las
   vistas de columnas y de galería.
2. **Cada cambio es una opción en gsettings.**
3. **El fork es un binario propio, con otro nombre**, para que una actualización
   del sistema no lo pise ni lo mezcle con el Nemo de Mint.

## Lo que no hace falta programar

Sale del tema o ya existe en Nemo:
- **Colores, tipografía, alturas de fila y esquinas:** tema GTK.
- **Filas en cebra:** la lista ya activa `gtk_tree_view_set_rules_hint`
  (`nemo-list-view.c:2680`); el color lo da el tema.
- **Triángulos para desplegar carpetas en la lista:** ya es una opción
  (`gtk_tree_view_set_show_expanders`, `nemo-list-view.c:301`).
- **Semáforos a la izquierda:** CSS y `gtk-decoration-layout = close,minimize,maximize:`.

## El binario aparte: lo que hay que cambiar para que no choque con Nemo

Que el ejecutable se llame distinto no basta. Nemo se identifica en varios
sitios, y si el fork comparte alguno, las dos copias se pisan:

| Qué | Nemo de Mint | Fork (nombre propuesto, lo decide José) |
|---|---|---|
| Ejecutable | `nemo` | `nemo-mac` |
| ID de aplicación (GApplication, D-Bus de instancia única) | `org.Nemo` | `org.koralis.NemoMac`. **Si se repite, abrir el fork abre el Nemo del sistema.** |
| Esquemas de gsettings | `org.nemo.*` | `org.koralis.nemo-mac.*`, con los ajustes propios y los heredados copiados |
| Archivo `.desktop` | `nemo.desktop` | `nemo-mac.desktop` |
| Dónde se instala | `/usr` (apt) | `/usr/local` u `/opt/nemo-mac`, **nunca `/usr`** |
| Escritorio (`nemo-desktop`) | lo dibuja Nemo | **el fork no lo dibuja**: se queda el del sistema |
| `org.freedesktop.FileManager1` (D-Bus de «mostrar en carpeta») | lo reclama Nemo | decidir quién lo reclama. Si lo quiere el fork, hay que evitar que lo tome el de Mint |
| Extensiones (`libnemo-extension`, nemo-python, acciones) | las del sistema | las compiladas para el Nemo de Mint pueden no cargar en el fork. Decidir si se comparten las acciones (`~/.local/share/nemo/actions`) o van aparte |

Después: hacerlo el administrador de archivos por defecto
(`xdg-mime default nemo-mac.desktop inode/directory`), y revisar qué partes de
Cinnamon llaman a `nemo` por nombre (applet de lugares, «abrir carpeta»).
Lo instala un guion de `mint-macos`, como el resto del repo.

## Fase 1 (puntos 1 a 5), unos 5 a 10 días

Estimación de Marketing para alguien con C y GTK 3; Dev la corrige.

| # | Cambio | Dónde | Cómo | Ajuste gsettings | Esfuerzo |
|---|---|---|---|---|---|
| 1 | **Archivos ocultos atenuados** (los que empiezan por punto) | `nemo-list-view.c` (lo que pinta la celda del nombre) y la vista de íconos | Bajar la opacidad del texto y del ícono | `dim-hidden-files` | ½–1 día |
| 2 | **Texto de la barra de estado centrado** | `nemo-statusbar.c:160-225`: el `GtkStatusbar` va entre botones y el zoom | Etiqueta centrada; decidir si el zoom se esconde (el Finder no lo tiene) | `statusbar-centered`, `statusbar-show-zoom` | ½ día |
| 3 | **Barra lateral con las secciones del Finder**: Favoritos, Ubicaciones, Etiquetas | `nemo-places-sidebar.c`: «My Computer» (:779), «Bookmarks» (:928), «Devices» (:348), «Network» (:1240) | Renombrar y reordenar; «Favoritos» une las carpetas del usuario con los marcadores | `sidebar-finder-sections` | 1–3 días |
| 4 | **Selector de vista segmentado** | `nemo-toolbar.c:355-361`: tres botones sueltos (íconos, lista, compacta) | Ponerlos en una caja `linked` para que el tema los pinte pegados | `toolbar-linked-view-switcher` | ½–1 día |
| 5 | **Búsqueda siempre visible a la derecha** | `nemo-toolbar.c:344` (botón) y `nemo-window-slot.c:389` (el editor de búsqueda vive en cada panel) | Un campo fijo en la barra que maneje la búsqueda del panel activo; cuidar el modo de dos paneles | `toolbar-search-entry` | 3–5 días |

## Punto 8: etiquetas

Nemo no tiene etiquetas; tiene **emblemas** (en `nemo-list-model.c`,
`nemo-list-view.c` y `nemo-icon-view-container.c`). Dos caminos, **lo decide José
con Dev**:

- **A. Etiquetas sobre emblemas, alrededor de 1 semana.** Siete colores como los
  del Finder, guardados como emblemas (metadatos de gvfs); un menú «Etiquetas»
  en el clic derecho; la sección «Etiquetas» de la barra lateral filtra por color.
  Limitación: el metadato vive solo en este host, **no viaja con el archivo**.
- **B. Etiquetas compatibles con macOS, 3 semanas o más.** Leer y escribir las
  etiquetas del Finder en el atributo extendido del archivo
  (`com.apple.metadata:_kMDItemUserTags`, en plist binario), para que una etiqueta
  puesta en el Mac se vea aquí y al revés, en discos o carpetas compartidas que
  conserven los atributos extendidos (el NAS por SMB, por ejemplo; el APFS del Mac
  Mini está en solo lectura). **Es el que encaja con la idea de «transparente»**,
  pero hay que comprobar primero que los atributos sobreviven en el camino real
  (SMB del NAS → este host).

Ajustes: `tags-enabled` y `tags-backend` (`emblems` o `macos-xattr`).

## Mantenimiento

- Cada cambio va detrás de su ajuste, **apagado por defecto**: el fork se comporta
  como Nemo hasta que se enciende, y actualizarlo con el Nemo original choca menos.
- Commits pequeños, uno por punto, para poder reaplicarlos sobre una versión
  nueva de Nemo.
- Los puntos 1 y 2 podrían proponerse al Nemo original.

## Lo que Planner tiene que decidir o pedir

1. **El nombre del fork** (propuesta: `nemo-mac`, `org.koralis.NemoMac`), con José.
2. **El camino de las etiquetas** (A o B), con José, después de comprobar los
   atributos extendidos por SMB si se va por B.
3. **Quién reclama `FileManager1`**, y si las acciones de Nemo se comparten.
4. **Dónde vive el código del fork**: repo propio (`nemo-mac`, fork de
   `linuxmint/nemo`) con su instalador llamado desde `mint-macos`.
5. **Repartir el trabajo con Infra**, que lleva `mint-macos`.
