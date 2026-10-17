# Versiones fijadas

Generado por `verificar-versiones.sh --escribir` a partir de `versiones.sh`: no se edita a mano.
Cada fork, el commit que se compila y los parches que lleva encima de su upstream.

## Fynder

- Fork: https://github.com/josemalena/fynder.git
- Upstream: https://github.com/linuxmint/nemo.git, rama `master`
- Commit: `6df603c9598d92bef95cc13bc781a65abe53a043` (2026-10-10, iCloud Drive: círculo de progreso en la barra lateral y ventana con subidas y bajadas (API rc de rclone por socket Unix))
- Base: `66eabf459bc86d03c24797274d0e3f60b9b7a7d8` (master.lmde7), 2026-10-06, nemo-icon-dnd.c: Fix reporting a successful drag result.
- Parches: 106

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

## mint-macos-dock

- Fork: https://github.com/josemalena/mint-macos-dock.git
- Upstream: https://github.com/zquestz/plank-reloaded.git, rama `master`
- Commit: `12d51dd5c95a1cc4f8b900e0b81c8c9c08323100` (2026-10-16, macos: los dos separadores con la misma holgura, y sin apps recientes no sale el segundo)
- Base: `e8e2b1fe2e9b13664b1402e2e68246a974ea1a4b` (0.11.176), 2026-10-09, Bump version to 0.11.176
- Parches: 20

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
- Commit: `a62cdb91edc803f042ee654e60f0e9d56186d655` (2026-10-14, tema: esquinas de 12, lupa de 28, cabeceras tenues y tabla de datos en la vista previa)
- Base: `5ba6eb1ec507d0c90cae80a8b4c33df473ade7be` (5.16.2), 2026-09-17, fix(settings): convert v6 setting names back when returning from v6
- Parches: 6

| Commit | Fecha | Asunto |
|---|---|---|
| `a364b3ea` | 2026-10-14 | ui: ventana de dos paneles como el Spotlight de Catalina |
| `da69c758` | 2026-10-14 | feat: índice de archivos por nombre, secciones de resultados e ícono de barra apagado |
| `abbcb1ae` | 2026-10-14 | fix: un aviso que no se puede mostrar no tumba el arranque |
| `b87bab62` | 2026-10-14 | perf: un índice por fuente (home, discos montados, iCloud) y sin stat por archivo |
| `6159e16a` | 2026-10-14 | perf: el indexado corre con E/S en clase idle |
| `a62cdb91` | 2026-10-14 | tema: esquinas de 12, lupa de 28, cabeceras tenues y tabla de datos en la vista previa |
