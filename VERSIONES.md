# Versiones fijadas

Generado por `verificar-versiones.sh --escribir` a partir de `versiones.sh`: no se edita a mano.
Cada fork, el commit que se compila y los parches que lleva encima de su upstream.

## Fynder

- Fork: https://github.com/josemalena/fynder.git
- Upstream: https://github.com/linuxmint/nemo.git, rama `master`
- Commit: `fdde0498517e1d00db8bb2bd2597fb208fea5bb4` (2026-10-18, feat(preferencias): Advanced como en Catalina, con sus tres funciones)
- Base: `66eabf459bc86d03c24797274d0e3f60b9b7a7d8` (master.lmde7), 2026-10-06, nemo-icon-dnd.c: Fix reporting a successful drag result.
- Parches: 214

| Commit | Fecha | Asunto |
|---|---|---|
| `be2c9ddd` | 2026-10-07 | Aísla Nemo Mac para que no se mezcle con Nemo |
| `db3e17e6` | 2026-10-07 | Pon la fecha Finder con el ajuste finder |
| `78697cd0` | 2026-10-07 | Pega los botones de vista con el ajuste del selector |
| `749290a0` | 2026-10-07 | Organiza la barra lateral como Finder con ajustes |
| `fc475b03` | 2026-10-07 | Ordena iCloud y Locations en la barra Finder |
| `82e40a19` | 2026-10-07 | Renombra la interfaz como Nemo Finder |
| `a4ec97f8` | 2026-10-07 | Despliega iCloud al abrir el sidebar Finder |
| `063271d0` | 2026-10-07 | Da al sidebar Finder un acabado oscuro |
| `ae275691` | 2026-10-08 | Usa fuente del sistema para fechas Finder |
| `d71a33e4` | 2026-10-08 | Adapta iconos y encabezados del sidebar Finder |
| `2bc940e6` | 2026-10-08 | Añade el estilo Finder a la barra de herramientas |
| `667e4856` | 2026-10-08 | Resuelve iconos Finder por ubicación del sidebar |
| `6734b502` | 2026-10-08 | Uniforma la selección y segmentos Finder |
| `dc12e528` | 2026-10-08 | Activa Finder por defecto y corrige sus iconos |
| `b5e98460` | 2026-10-08 | Muestra nombres e iconos de red en el sidebar Finder |
| `99ab222e` | 2026-10-08 | Documenta el relevo de Nemo Finder |
| `b7f9de80` | 2026-10-08 | Pule el sidebar Finder: píldora, sangría, orden y Movies |
| `99523007` | 2026-10-08 | Añade Arrange al toolbar Finder |
| `67b3fffc` | 2026-10-08 | Añade Action al toolbar Finder |
| `04b6da4a` | 2026-10-08 | Añade el campo de búsqueda al toolbar Finder |
| `43c03710` | 2026-10-08 | Añade botones opcionales al toolbar Finder |
| `e1799e28` | 2026-10-08 | Usa el glifo de columnas en la vista compacta del toolbar Finder |
| `0e34f740` | 2026-10-08 | Corrige la búsqueda y los menús del toolbar Finder |
| `45855575` | 2026-10-08 | Añade atajos de teclado estilo Finder |
| `9745e184` | 2026-10-08 | Evita que la búsqueda del toolbar pierda letras al escribir |
| `7fccf1e3` | 2026-10-08 | Arregla las letras perdidas, Escape y Super dentro de campos de texto |
| `fd92c509` | 2026-10-08 | Añade la Path Bar estilo Finder en una franja sobre la statusbar |
| `71878a17` | 2026-10-08 | Dibuja el fondo y la línea superior de la Path Bar |
| `7361d784` | 2026-10-08 | Centra el texto de la statusbar en el layout Finder |
| `ee5c686a` | 2026-10-08 | Atenúa los archivos ocultos en las vistas de iconos y de lista |
| `e98a4db0` | 2026-10-10 | Actualiza el relevo de Nemo Finder |
| `81333cb8` | 2026-10-10 | Usa los glifos del Finder en todos los botones del toolbar |
| `6fcf6792` | 2026-10-10 | Restaura Cmd+↑ y evita que Super se cuele al filtro rápido |
| `8c96a734` | 2026-10-10 | Lee bien las filas ocultas seleccionadas en la vista de lista |
| `3fc97eef` | 2026-10-10 | Devuelve los iconos de Nemo al apagar el layout Finder |
| `cfb6fc28` | 2026-10-10 | Arregla encender el layout Finder en caliente |
| `d9b997fc` | 2026-10-10 | Muestra «Macintosh HD» en vez de «File System» y deja cambiarlo |
| `79914e7f` | 2026-10-10 | Da más ancho al nombre en las filas de disco del lateral Finder |
| `f5902b83` | 2026-10-10 | Actualiza el relevo con las últimas pruebas y claves |
| `f03401c7` | 2026-10-10 | Arregla el cierre de Preferencias por el formato de fecha Finder |
| `4918c7ad` | 2026-10-10 | Añade el menú global: publica la barra de menú de Nemo Mac por D-Bus |
| `753a9b5a` | 2026-10-10 | Permite arrancar una instancia aparte con NEMO_MAC_APP_ID |
| `aadb045c` | 2026-10-10 | Evita rehacer el modelo del menú global si su contenido no cambió |
| `6dff013c` | 2026-10-10 | Acerca el toolbar Finder a las medidas y posiciones del Finder |
| `21dcfcea` | 2026-10-10 | Iconos de 32 px y hueco proporcional en el toolbar Finder |
| `1f992361` | 2026-10-10 | Estabiliza el hueco del toolbar Finder y evita que la búsqueda desborde |
| `df00ea66` | 2026-10-10 | Baja los botones del toolbar Finder a 36 px, como la barra de Nemo |
| `11275fa6` | 2026-10-10 | Aplica el reparto del toolbar Finder fuera de size-allocate |
| `945ec3f3` | 2026-10-10 | Ajusta la altura del campo de búsqueda para que la barra mida 36 px |
| `497a5845` | 2026-10-10 | Renombra la identidad técnica del fork a Fynder |
| `0d9234a1` | 2026-10-10 | Cambia el nombre visible a Fynder |
| `56e82d83` | 2026-10-10 | Separa las rutas de Fynder de las del Nemo del sistema |
| `ca26b68a` | 2026-10-10 | Añade el guion para migrar los ajustes de nemo-mac a Fynder |
| `719604ea` | 2026-10-10 | Documenta el renombre a Fynder en el relevo |
| `2be2a7f4` | 2026-10-10 | Anota en el relevo cómo reconstruir los builds y el estado de la instalación |
| `28d042da` | 2026-10-10 | Hace que el zoom solo cambie el tamaño de los iconos, no el del texto |
| `4d8c4c85` | 2026-10-10 | Aplica al toolbar Finder las medidas del Finder de Catalina a escala 1x |
| `b91770d9` | 2026-10-10 | Mueve la Path Bar a la columna de contenido |
| `d26c51b7` | 2026-10-10 | Aplica las medidas del Finder al lateral y a la lista |
| `41c5134e` | 2026-10-10 | Vuelve a conectar la vista previa con nemo-preview |
| `e783cd73` | 2026-10-10 | Añade Quick Look: acción, menús y atajo ⌘Y |
| `dfa3409b` | 2026-10-10 | Lista en el menú «»» los items del toolbar Finder que no caben |
| `716e3bf7` | 2026-10-10 | Añade triángulos de despliegue y cebra a la vista de lista |
| `9d0431e6` | 2026-10-10 | Corrige el ancho del ⚙ y Arrange y el relleno lateral del toolbar Finder |
| `581db909` | 2026-10-10 | Añade Hide/Show a los encabezados del lateral Finder |
| `39931c40` | 2026-10-10 | Oculta el lateral automáticamente cuando la ventana es muy angosta |
| `65793e79` | 2026-10-10 | Ajusta los bordes del toolbar Finder y el texto de la búsqueda |
| `e24dd406` | 2026-10-10 | Hace los encabezados del lateral Finder más chicos y finos |
| `94ff8f23` | 2026-10-10 | Rehace el campo de búsqueda del toolbar Finder como el del Finder |
| `cf6dfd0e` | 2026-10-10 | Aclara la lupa y oscurece el marcador de la búsqueda como en el Finder |
| `734cbe47` | 2026-10-10 | Hace que Arrange ordene por columna en la lista y usa iconos del tema en la ruta |
| `1799ff0b` | 2026-10-10 | Completa los atajos estilo Finder: zoom, ir a, barras, alias y minimizar |
| `c6b82735` | 2026-10-10 | Añade el menú de la aplicación «Fynder» al menú global |
| `af3f177c` | 2026-10-10 | Reordena File y Edit como el Finder: Get Info, Rename, Duplicate, Make Alias y Move to Trash pasan a File |
| `10cf025e` | 2026-10-10 | Rehace el menú Go como el del Finder |
| `5f12e7ee` | 2026-10-10 | Añade el menú Window con Minimize, pestañas y panel extra |
| `ba10148a` | 2026-10-10 | Muestra en los menús los atajos Finder que de verdad funcionan |
| `059ca95f` | 2026-10-10 | Rehace el menú View como el del Finder |
| `665311d8` | 2026-10-10 | Reordena el menú contextual de la selección como el del Finder |
| `ef745421` | 2026-10-10 | Llama as Compact a la vista compacta y esconde Delete en modo Finder |
| `7bef88ae` | 2026-10-10 | Devuelve el glifo view-column al botón de la vista compacta |
| `b5c606e1` | 2026-10-10 | Quita Bookmarks de la barra en layout Finder y publica Empty Trash… siempre |
| `197d7333` | 2026-10-10 | Añade la ventana de Preferences estilo Finder (General, Sidebar, Advanced) |
| `96f2b6b4` | 2026-10-10 | Añade Show View Options (Cmd+J): tamaño de iconos y orden de la vista |
| `a72ea75a` | 2026-10-10 | Añade el LEEME de Fynder: qué es, qué cambia respecto a Nemo, cómo compilar y la licencia |
| `933f1cbc` | 2026-10-10 | Añade «Open folders in tabs» y «Show all filename extensions» |
| `0af2f823` | 2026-10-10 | Añade la vista Gallery (Cmd+4): vista previa grande y tira de miniaturas |
| `a544abbd` | 2026-10-10 | Anota en el LEEME la Gallery y lo que queda pendiente |
| `3a82fe8b` | 2026-10-10 | Añade Compress, Burn to Disc y Add to Dock al menú contextual |
| `f01ccef3` | 2026-10-10 | Añade fynder-desktop con el escritorio en columnas de derecha a izquierda |
| `f3a674c7` | 2026-10-10 | Etiquetas y selección del escritorio como en macOS |
| `20884366` | 2026-10-10 | Ajusta la selección del escritorio a las medidas de macOS |
| `f4075153` | 2026-10-10 | Menú del escritorio vacío como el de Catalina |
| `c8b768a5` | 2026-10-10 | Muestra discos en el escritorio según el Finder: duros, externos, ópticos y servidores |
| `31a3921a` | 2026-10-10 | Añade Show View Options al escritorio: tamaño de íconos, espacio de la rejilla y texto |
| `9a99ca22` | 2026-10-10 | Ajusta el escritorio a las observaciones de la comparación con macOS |
| `f153fb67` | 2026-10-10 | Agrega la columna Date Added y deja «carpetas primero» apagado por defecto, como el Finder |
| `cc70b1b2` | 2026-10-10 | Lee el .DS_Store de macOS al abrir una carpeta por primera vez |
| `47d80d17` | 2026-10-10 | Lee enteros de 16 bytes en los plist del .DS_Store |
| `8f1517e3` | 2026-10-10 | ⌘ + clic suma o quita elementos de la selección, como en macOS |
| `b3a3544c` | 2026-10-10 | ⌘↑ y ⌘↓ funcionan: Alt+↑ y Alt+↓ de keyd, y Ctrl+Inicio y Ctrl+Fin sin la regla |
| `490a0ddd` | 2026-10-10 | No muestra los .DS_Store, ni con los archivos ocultos visibles |
| `90f35f10` | 2026-10-10 | Número de compilación secuencial en «fynder --version» y en el About |
| `af726aff` | 2026-10-10 | Los montajes FUSE de rclone (iCloud Drive) ya no salen como discos en la barra lateral ni en el escritorio |
| `ab41db80` | 2026-10-10 | Barra lateral: solo se oculta el montaje de iCloud; los demás de rclone siguen en Locations (el escritorio los sigue omitiendo) |
| `6df603c9` | 2026-10-10 | iCloud Drive: círculo de progreso en la barra lateral y ventana con subidas y bajadas (API rc de rclone por socket Unix) |
| `a4c7ca42` | 2026-10-11 | Barra lateral: el botón (expulsar / progreso de iCloud) queda dentro del fondo de selección; el círculo de iCloud consulta cada segundo y se mantiene 2 s tras terminar |
| `644aca47` | 2026-10-12 | Columnas Tags y Comments: lee las etiquetas de color y los comentarios de Finder (xattr o archivo ._ de AppleDouble) |
| `42d87db3` | 2026-10-12 | Path Bar: la ruta termina en el elemento seleccionado, como en el Finder (una carpeta se abre al hacer clic; un archivo no) |
| `0d5f44a8` | 2026-10-12 | Show Package Contents para paquetes de Mac (carpeta o zip de iCloud): abre el zip con archive:// de solo lectura, el doble clic no abre el gestor de archivos comprimidos, el Path Bar sigue por el zip; Tags y Comments vacíos en vez de «unknown» |
| `ce6b5105` | 2026-10-12 | Iconos de paquetes de Mac: el .app (carpeta o zip de iCloud) muestra el icono que trae dentro (CFBundleIconFile → .icns → PNG, con caché) |
| `ca67812a` | 2026-10-12 | Iconos de paquetes: solo el Info.plist y los .icns del primer nivel (no los de plugins anidados); la caché cambia de versión |
| `f91a389c` | 2026-10-12 | Abrir una carpeta que ya está abierta en otra ventana o pestaña la trae al frente en vez de abrir una nueva |
| `09f9c524` | 2026-10-12 | Importar .DS_Store: la vista de lista se lee de lsvC y solo si no hay se usa lsvp (en macOS 27 el Finder ignora lsvp) |
| `fce51b20` | 2026-10-12 | Fynder escribe el .DS_Store: escritor del archivo (árbol B, bloques, plist binario) y exportación de vista, columnas, orden, tamaño y posiciones de íconos |
| `0329cbc5` | 2026-10-12 | Exportación a .DS_Store: solo se avisa si el metadato guardado cambió de verdad (abrir una carpeta no escribe nada) |
| `afb63a9c` | 2026-10-12 | Exportación a .DS_Store: el aviso compara contra el valor que había (los metadatos se guardan en segundo plano); prueba de la exportación |
| `0877c704` | 2026-10-12 | Exportar a .DS_Store: la vista va en el .DS_Store del padre con el nombre de la carpeta, y lsvC lleva las columnas como lista con identifier (lo que escribe el Finder); el importador también lee esa forma |
| `cb231bf6` | 2026-10-12 | Exportar a .DS_Store: junto con la vista se escriben vSrn, LSVO y lsvt como hace el Finder (solo si faltan) |
| `cf906f5d` | 2026-10-12 | Exportar a .DS_Store: lsvt es de tipo «shor», como lo escribe el Finder |
| `1c903590` | 2026-10-12 | Vista de columnas (as Columns) propia: una columna por carpeta del camino, vista previa del archivo, renombrar en el sitio, menú contextual, arrastrar y soltar y ancho ajustable; Cmd+3 la abre y navegar desde ella conserva la vista |
| `5056ea81` | 2026-10-12 | Vista de columnas: la selección del camino se aplica aunque la fila ya esté, borde de columna invisible, icono de columnas |
| `071f3693` | 2026-10-13 | Una sola ventana por carpeta: el doble clic y el escritorio traen al frente la que ya la tiene |
| `50fadfd2` | 2026-10-13 | Arranque del escritorio: nada de stat síncronos sobre ~/Desktop en el hilo principal |
| `15857532` | 2026-10-13 | El escritorio publica el menú de Fynder, como el Finder al hacer clic en él |
| `20ebd0e0` | 2026-10-13 | Abrir una carpeta desde el escritorio ya no lanza otro proceso fynder |
| `4b1e003f` | 2026-10-13 | Los discos montados se muestran en /Volumes, como en macOS |
| `1419a54a` | 2026-10-13 | Los discos montados se cargan por /Volumes/<disco>, el enlace a /media/<usuario> |
| `bfbe0ce8` | 2026-10-13 | Go > Applications (⇧⌘A) y Utilities (⇧⌘U), acción Applications en el menú del Dock, y el lanzador se nombra por lo que dice en la ruta |
| `a9f5a333` | 2026-10-13 | Barra lateral: Applications después de Recent, y la papelera ya no sale |
| `752cfd9b` | 2026-10-13 | /Applications como en el Finder: «Kind: Application» y el tamaño de cada aplicación |
| `7f2a73b6` | 2026-10-13 | .localized como el Finder: la carpeta se muestra con el nombre del idioma del sistema |
| `ac156773` | 2026-10-13 | Los .app de macOS: «macOS App», su tamaño, el «prohibido» y su Info.plist en Get Info |
| `95d5d536` | 2026-10-13 | Abrir un .app de macOS avisa en vez de entrar a la carpeta |
| `a202bf21` | 2026-10-13 | El aviso de los .app de macOS, como la hoja (sheet) del Finder |
| `814b495f` | 2026-10-13 | Todos los avisos y confirmaciones salen como la hoja (sheet) del Finder |
| `82a31afd` | 2026-10-13 | Diálogos: panel para las confirmaciones, atajos de Apple y foco del teclado |
| `3540d5a0` | 2026-10-13 | CLAUDE.md: siempre revisar las capturas de referencia antes de diseñar o cerrar |
| `df32c075` | 2026-10-13 | feat(sidebar): Applications como casilla en Settings > Sidebar; Trash sale de la lista |
| `6b6e00cd` | 2026-10-13 | feat(preferences): pestañas con icono, título fijo y lista con iconos como el Finder |
| `5607e88d` | 2026-10-13 | style: barra de herramientas y lateral con los grises de Catalina oscuro |
| `251655cc` | 2026-10-13 | feat(tags): registro de etiquetas, escritura en xattr y pestaña Tags de Preferences |
| `f624638e` | 2026-10-13 | style: una sola linea bajo la barra de herramientas |
| `a21ae6bd` | 2026-10-13 | feat(tags): fila de puntos de color y Tags… en el menú contextual |
| `28cc54ab` | 2026-10-13 | feat(tags): sección Tags en el lateral y búsqueda por etiqueta |
| `3f7e9ebc` | 2026-10-13 | feat(tags): campo Tags en Get Info |
| `309494d2` | 2026-10-13 | style: botones de la barra con los colores del Finder y glifo oscuro en la vista elegida |
| `d393414e` | 2026-10-13 | feat(info): ventana Info del Finder, iCloud en el lateral e iconos de Preferences |
| `fb70af79` | 2026-10-13 | feat(tags): botón Tags en la barra y atajo ⇧⌘⌫ de Empty Trash en el menú |
| `ddbd278c` | 2026-10-13 | feat(view-options): Show View Options de la lista como el Finder |
| `fe2eb618` | 2026-10-13 | feat(window): barra de título propia con el icono de la carpeta |
| `30291829` | 2026-10-13 | style: barra de título y de herramientas de 54 px y encabezados del lateral como el Finder |
| `1ba21252` | 2026-10-13 | feat(root): el disco como en el Finder, vistas alineadas al lateral y barra a 25/54 px |
| `e7261de5` | 2026-10-13 | CLAUDE.md: el turno de pantalla (gui-lock) y el foco antes de tocar la sesión de José |
| `4f5a165c` | 2026-10-14 | feat(view-options): iconos, galería, columnas y Desktop como el Finder, y la ventana sigue a la vista |
| `c47046c2` | 2026-10-14 | feat(info): sugerencias de etiquetas con su punto de color en el campo Tags |
| `8d5d6169` | 2026-10-14 | fix(desktop): el escritorio se vuelve a leer si su carpeta cambia por debajo |
| `513d728a` | 2026-10-14 | fix(view-options): el espaciado de la rejilla del escritorio se aplica en fynder-desktop |
| `b455dcab` | 2026-10-14 | fix(global-menu): «Fynder ▸ Empty Trash…» sale con su atajo ⇧⌘⌫ |
| `6611bfba` | 2026-10-14 | fix(window): la raíz de un volumen lleva el icono del disco en la barra de título (TRANSPORTE, Data, HDD) |
| `5898a1b3` | 2026-10-14 | fix(window): el icono del disco en el título busca el montaje por dispositivo e inodo (Fynder abre /Volumes/X) |
| `8bf5d364` | 2026-10-14 | feat(desktop): rejilla del escritorio como Catalina: primera fila 30 px bajo la barra y columna derecha 45 px hacia el borde |
| `d158eb91` | 2026-10-14 | Revert "feat(desktop): rejilla del escritorio como Catalina: primera fila 30 px bajo la barra y columna derecha 45 px hacia el borde" |
| `e39a4f80` | 2026-10-14 | fix(desktop): la ventana del escritorio sin decoración queda en el área de trabajo (0,22), no en (-45,-7) |
| `b34bd6eb` | 2026-10-14 | fix(info): Get Info de un disco del escritorio usa la ventana Info (ruta del URI de activación) |
| `5674e0cc` | 2026-10-14 | feat(shortcuts): ⌘E expulsa o desmonta el disco, y los menús contextuales muestran los atajos con glifos |
| `7c8186e5` | 2026-10-14 | feat(info): Get Info de un volumen muestra Kind, Format, Capacity, Available y Used, sin escanear el disco |
| `80d6e473` | 2026-10-14 | feat(quicklook): la vista previa sigue a la selección con ↑↓←→, Espacio y Esc la cierran y el foco se queda en Fynder |
| `0d65f684` | 2026-10-14 | feat(columns): el camino arranca en el disco, asa de dos rayitas, y el panel de datos con Dimensions, Tags, Where, Size y Show More |
| `e040ed42` | 2026-10-14 | fix(icon-container): el relleno del rectángulo de selección sale del nodo rubberband del tema, no del fondo opaco del contenedor |
| `7e8c5fc7` | 2026-10-14 | feat(columns): Add Tags… del panel agrega etiquetas con sugerencias y un clic en una etiqueta busca por ella |
| `a25e1985` | 2026-10-14 | feat(columns): primer nivel del equipo (Macintosh HD, volúmenes montados y Network) y la cadena de un disco arranca en él |
| `00489a11` | 2026-10-15 | fix(info): la ventana toma el alto de su contenido, el candado y los permisos funcionan, el engranaje abre las propiedades estándar; ⌘W cierra solo la ventana activa y ⌥⌘W todas |
| `3a29f18e` | 2026-10-15 | feat(columns): clic derecho en una etiqueta del panel ofrece «Remove Tag» |
| `2975f9eb` | 2026-10-15 | fix(info): el candado y el chmod por pkexec corren sin bloquear la ventana |
| `0a88ee15` | 2026-10-15 | feat(pathbar): el ícono del título y los segmentos de la barra de ruta se arrastran como archivo o como ruta |
| `2b1a04fe` | 2026-10-15 | feat(trash): la Trash suma la papelera de macOS de los discos externos (.Trashes/<uid>) |
| `39605ace` | 2026-10-15 | test(trash): gancho FYNDER_TRASH_PRUEBA para probar Empty Trash sin tocar discos ni la Trash reales |
| `bc25f90c` | 2026-10-16 | feat(disks): los discos APFS de fstab (fsapfs) salen siempre en Locations y en el escritorio |
| `c69f0e69` | 2026-10-16 | feat(disks): los montajes internos de ~/.cache/mint-macos no se listan en ningún lado |
| `153a1e56` | 2026-10-17 | feat(gallery): panel de información a la derecha, como el de la Gallery del Finder |
| `5f44b6a8` | 2026-10-17 | feat(gallery): el tamaño de la tira sigue al zoom y «Show filename» pone los nombres bajo las miniaturas |
| `e710bc0b` | 2026-10-17 | feat(view): Show Preview (⇧⌘P) y «Show preview column» de verdad; Columns y Gallery como vista por defecto |
| `87e55b7f` | 2026-10-17 | feat(preview): Preview pane en Icons y List (⇧⌘P), panel común con la Gallery y candado de XDG para las pruebas |
| `1e32ade5` | 2026-10-17 | fix(preview): el Preview pane se vacía al cambiar de carpeta en la misma vista |
| `6dd6fd83` | 2026-10-17 | feat(go): la hoja «Go to the folder:» del Finder para ⇧⌘G y Go ▸ Go to Folder… |
| `96ef69eb` | 2026-10-17 | feat(menus): Edit y Window como en el Finder de Catalina, con «Copy "nombre"» y la lista de ventanas |
| `08f610d4` | 2026-10-17 | feat(tabs): la barra de pestañas del Finder, a todo el ancho de la ventana |
| `78f3415c` | 2026-10-17 | feat(search): la búsqueda del Finder: alcance This Mac \| carpeta, criterio Kind, sugerencia y columnas Name/Size/Kind |
| `cadf1399` | 2026-10-17 | feat(toolbar): Customize Toolbar del Finder: la barra sale de una lista que se edita arrastrando |
| `0079bbae` | 2026-10-17 | feat: ⌥⌘V mueve lo copiado, iCloud Drive entra en This Mac, glifo de Connect y build reproducible |
| `5c06e8f4` | 2026-10-17 | feat(tags): Control-1…7 ponen o quitan las etiquetas favoritas y Control-0 las quita todas |
| `5c8d1df2` | 2026-10-17 | feat(menus): el menú View del Finder de Catalina |
| `552a50b6` | 2026-10-17 | feat(appimage): una AppImage con su lanzador de mint-macos se ve con el nombre de la app y «.app» |
| `223db0b1` | 2026-10-17 | feat(appimage): el ícono del lanzador de mint-macos (Icon=) |
| `236f91b3` | 2026-10-18 | fix(escritorio): miniaturas de videos y capturas, y que quepan en el recuadro |
| `1482cbfc` | 2026-10-18 | feat(menús): File y Go como en el Finder de Catalina |
| `7a3a0119` | 2026-10-18 | feat(menú global): íconos del menú Go y atajos con ^ del menú File |
| `b4d0b912` | 2026-10-18 | fix(portapapeles): un solo pedido de TARGETS en vuelo |
| `c44e4e7f` | 2026-10-18 | test: reproducción de la caída de kitty por BadWindow (portapapeles) |
| `3e157166` | 2026-10-18 | fix(discos): los APFS de fstab con el ícono de su disco físico |
| `b08912ab` | 2026-10-18 | feat(selector): Open y Save de todo el sistema con una ventana de Fynder |
| `c44284f8` | 2026-10-18 | portal: instalar-selector.sh, el selector de Fynder en la sesión (sin sudo) |
| `e6fc78f4` | 2026-10-18 | feat(selector): la hoja de guardar de la Mac, compacta y expandida |
| `550aae8c` | 2026-10-18 | fix(selector): la hoja vuelve a su sitio al aparecer y sin barra de ruta |
| `364c37e5` | 2026-10-18 | feat(selector): módulo de GTK 3 para los programas que arman su propio diálogo |
| `c662f8f8` | 2026-10-18 | fix(selector): el módulo de GTK pasa la carpeta y el archivo que puso el programa |
| `0169a655` | 2026-10-18 | feat(apps de la Mac): abrir un .app muestra su interfaz con mac-visor-nib |
| `12e7942e` | 2026-10-18 | fix(apps de la Mac): el .app se reconoce al abrirlo, sin esperar al tamaño |
| `f171c117` | 2026-10-18 | fix(papelera): la alerta de Empty Trash como en Catalina |
| `2a0e337e` | 2026-10-18 | feat(lateral): el menú contextual del Finder en la barra lateral |
| `b492ed38` | 2026-10-18 | feat(menú): los atajos del menú View en el menú global |
| `e145286f` | 2026-10-18 | feat(menú): Add to Dock en el menú File, con ^⇧⌘T |
| `fdde0498` | 2026-10-18 | feat(preferencias): Advanced como en Catalina, con sus tres funciones |

## mint-macos-dock

- Fork: https://github.com/josemalena/mint-macos-dock.git
- Upstream: https://github.com/zquestz/plank-reloaded.git, rama `master`
- Commit: `68d01f049de8653aa52f685774666bac13900fb4` (2026-10-17, tests: plank-tests a 120 s y dock-test a 60 s también sin Xvfb (el timeout de 30 s por defecto se agotó una de tres veces con la máquina cargada))
- Base: `e8e2b1fe2e9b13664b1402e2e68246a974ea1a4b` (0.11.176), 2026-10-09, Bump version to 0.11.176
- Parches: 21

| Commit | Fecha | Asunto |
|---|---|---|
| `67ba01577` | 2026-10-10 | feat(macos): el indicador de punto y el fondo desenfocado detrás del dock |
| `286452f7c` | 2026-10-10 | feat(macos): el docklet de pilas, Descargas como en el Dock de macOS |
| `df25a20ee` | 2026-10-10 | fix(macos): la pila compila y no tapa el SortBy de los lanzadores |
| `6f8323940` | 2026-10-10 | fix(macos): la pila enseña las imágenes y usa ~/Downloads de verdad |
| `090195ecd` | 2026-10-10 | fix(macos): la raya del separador es la del Dock de macOS |
| `a90d61b88` | 2026-10-10 | fix(macos): la pila se lee como pila |
| `ac97f8e01` | 2026-10-10 | fix(macos): el menú de la pila marca con ✓, no con radio |
| `e27bb0c2e` | 2026-10-10 | feat(macos): el Calendario enseña la fecha de hoy |
| `32ef2eae6` | 2026-10-10 | feat(macos): «Options ▸ Keep in Dock / Remove from Dock», como en macOS |
| `4cf5ae489` | 2026-10-10 | fix(macos): el humo al quitar un ícono sale donde se suelta, no en la esquina |
| `461786b42` | 2026-10-10 | fix(macos): el genio entra en el ícono, no en un punto del borde |
| `92c981e55` | 2026-10-12 | LEEME: de dónde viene el fork y para qué es (mint-macos-dock) |
| `d377f7d1d` | 2026-10-14 | macos: «minimize-into-icon»; apagada, las ventanas minimizadas van al final del dock |
| `76a095c55` | 2026-10-14 | macos: apps recientes (show-recent-apps), nuevas apps tras el separador y fijadas a su izquierda |
| `ce71e842d` | 2026-10-14 | macos: la pila con las medidas de Catalina (abanico más abierto y rejilla de 126 pt con íconos de 90) |
| `4727955e8` | 2026-10-14 | macos: con dos separadores, las apps sin fijar van entre los dos |
| `36745a176` | 2026-10-15 | macos: con dos separadores, el segundo solo sale si hay una app abierta sin fijar entre los dos |
| `8400c8442` | 2026-10-15 | macos: soltar un ícono del dock sobre la Papelera lo quita del dock |
| `a8ce1db1e` | 2026-10-15 | macos: la Papelera del dock cuenta y vacía la de macOS de los discos externos (<volumen>/.Trashes/<uid>) |
| `12d51dd5c` | 2026-10-16 | macos: los dos separadores con la misma holgura, y sin apps recientes no sale el segundo |
| `68d01f049` | 2026-10-17 | tests: plank-tests a 120 s y dock-test a 60 s también sin Xvfb (el timeout de 30 s por defecto se agotó una de tres veces con la máquina cargada) |

## slick-greeter-mac

- Fork: https://github.com/josemalena/mint-macos-greeter.git
- Upstream: https://github.com/linuxmint/slick-greeter.git, rama `master`
- Commit: `13ae3286979c42de30b6f30e884ce8eec25a7c6d` (2026-10-17, slick-greeter-mac: el fondo es el de escritorio de la persona (o de la última que entró), con Catalina de respaldo)
- Base: `d1f81b4406d5a756d2274c3dbbbd39bd1bd0f6d4` (2.2.6), 2026-01-08, 2.2.6
- Parches: 9

| Commit | Fecha | Asunto |
|---|---|---|
| `a10beed` | 2026-10-10 | slick-greeter-mac: la ventana de inicio de macOS Catalina |
| `41f01b9` | 2026-10-10 | slick-greeter-mac: medido contra la Mac, y prueba en Xephyr sin tocar la sesión |
| `1cda956` | 2026-10-10 | slick-greeter-mac: los botones de abajo, los de la Mac |
| `f30327f` | 2026-10-10 | slick-greeter-mac: el .conf manda sobre dconf, y sin la franja de arriba |
| `27641de` | 2026-10-10 | slick-greeter-mac: al bloquear va directo al usuario que bloqueó |
| `2214646` | 2026-10-11 | slick-greeter-mac: los puntos de la clave, los de la Mac (● y no •) |
| `9d5c853` | 2026-10-12 | LEEME: de dónde viene el fork y para qué es (mint-macos-greeter) |
| `5254f60` | 2026-10-14 | slick-greeter-mac: fondo claro en la lista y oscuro según el estilo del usuario, con ‹ para volver |
| `13ae328` | 2026-10-17 | slick-greeter-mac: el fondo es el de escritorio de la persona (o de la última que entró), con Catalina de respaldo |

## Spotlyte

- Fork: https://github.com/josemalena/spotlyte.git
- Upstream: https://github.com/Ulauncher/Ulauncher.git, rama `v5`
- Commit: `0a6a4c4878936a4c611098397f7f0e0b5b6e4f78` (2026-10-18, fix(ventana): Spotlyte no sale en el Dock ni en el selector de ventanas, como Spotlight)
- Base: `5ba6eb1ec507d0c90cae80a8b4c33df473ade7be` (5.16.2), 2026-09-17, fix(settings): convert v6 setting names back when returning from v6
- Parches: 8

| Commit | Fecha | Asunto |
|---|---|---|
| `a364b3ea` | 2026-10-14 | ui: ventana de dos paneles como el Spotlight de Catalina |
| `da69c758` | 2026-10-14 | feat: índice de archivos por nombre, secciones de resultados e ícono de barra apagado |
| `abbcb1ae` | 2026-10-14 | fix: un aviso que no se puede mostrar no tumba el arranque |
| `b87bab62` | 2026-10-14 | perf: un índice por fuente (home, discos montados, iCloud) y sin stat por archivo |
| `6159e16a` | 2026-10-14 | perf: el indexado corre con E/S en clase idle |
| `a62cdb91` | 2026-10-14 | tema: esquinas de 12, lupa de 28, cabeceras tenues y tabla de datos en la vista previa |
| `cb78641c` | 2026-10-18 | perf: la búsqueda de archivos ya no traba el teclado (hilo aparte, espera de 90 ms, fuentes a la vez, índice en el disco del sistema) |
| `0a6a4c48` | 2026-10-18 | fix(ventana): Spotlyte no sale en el Dock ni en el selector de ventanas, como Spotlight |
