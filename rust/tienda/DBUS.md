# mint-macos-tienda: la interfaz D-Bus del App Store

El motor del App Store, sin ventana. Las pantallas (Dev-Dock, en Vala) hablan
solo con esta interfaz; el motor habla con PackageKit (APT) por D-Bus, con
libflatpak por una FFI mínima, y lee los catálogos de AppStream directo. No
llama a mintinstall ni lee nada suyo.

**Estado: interfaz aprobada por Planner (18-10-2026); implementándose.**

## De dónde salen los datos

| | Ruta en esta máquina (Mint 22.3) | Formato |
|---|---|---|
| Catálogo de APT | `/var/lib/swcatalog/yaml/*_dep11_Components-amd64.yml.gz` (las de Ubuntu; el repo de Mint no publica DEP-11) | DEP-11 YAML; íconos y capturas por URL relativa a `MediaBaseUrl` |
| Catálogo de Flathub | `/var/lib/flatpak/appstream/<remote>/x86_64/active/appstream.xml.gz` | AppStream XML; íconos en `active/icons/{64x64,128x128}` |
| Instalar con APT | PackageKit (`org.freedesktop.PackageKit`, bus de sistema) | D-Bus |
| Instalar con Flatpak | `libflatpak.so.0`: installation, transaction, add_install/add_uninstall/add_update, run y sus señales de progreso | FFI |
| Estantes | `https://flathub.org/api/v2/…` | JSON |

## Dónde vive

| | |
|---|---|
| Bus | de sesión |
| Nombre | `org.mintmacos.Tienda1` |
| Objeto | `/org/mintmacos/Tienda1` |
| Interfaz | `org.mintmacos.Tienda1` |
| Arranque | activación por D-Bus (`~/.local/share/dbus-1/services/org.mintmacos.Tienda1.service`); se queda residente mientras haya trabajos o alguien escuchando, y se va solo tras 10 min sin uso |

## Identificadores

Cada app tiene un `id` que dice de dónde sale, para que no haya dos «GIMP»
sin saber cuál es cuál:

- `flatpak:<instalación>/<remote>/<ref>` — p. ej. `flatpak:system/flathub/app/org.gimp.GIMP/x86_64/stable`
- `apt:<paquete>` — p. ej. `apt:gimp`

Además, `appstream_id` (`org.gimp.GIMP`) junta las variantes de la misma app:
la ficha devuelve las otras fuentes en `otras_fuentes`.

## Tipos

**Resumen** (`a{sv}`), lo que lleva cada tarjeta o fila:

| clave | tipo | |
|---|---|---|
| `id` | s | ver arriba |
| `appstream_id` | s | |
| `nombre` | s | localizado según `LANG` |
| `resumen` | s | el subtítulo de la fila |
| `icono` | s | ruta local si está en caché; si no, URL (la descarga el motor y avisa con `IconoListo`) |
| `origen` | s | `flatpak` o `apt` |
| `instalada` | b | |
| `actualizable` | b | |
| `desarrollador` | s | vacío si AppStream no lo trae |
| `verificada` | b | solo Flathub (`verification`); en APT no existe y no viene |

Las claves que no tienen dato **no vienen**. Nunca van con un valor inventado.

**Ficha** (`a{sv}`): todo el Resumen, más:

| clave | tipo | |
|---|---|---|
| `descripcion` | s | el markup de AppStream (`<p>`, `<ul>`, `<li>`, `<em>`, `<code>`) tal cual |
| `capturas` | a(sss) | (url de la imagen grande, url de la miniatura, pie de foto) |
| `version` | s | la que se instalaría |
| `version_instalada` | s | |
| `fecha_version` | x | unix, de `<releases>` |
| `notas_version` | s | markup de la última `<release>` |
| `tamano_descarga` | t | bytes; no viene si la fuente no lo da |
| `tamano_instalada` | t | bytes |
| `licencia` | s | SPDX |
| `web`, `ayuda`, `donar`, `errores` | s | las `<url>` de AppStream |
| `categorias` | as | las de AppStream |
| `clasificacion_edad` | a{ss} | OARS (`content_rating`), si viene |
| `permisos` | as | solo Flatpak: lo que pide (red, archivos, dispositivos…) |
| `instalaciones_mes` | u | solo Flathub, de `/stats/{app_id}`; `fuente_instalaciones` dice de dónde |
| `otras_fuentes` | as | otros `id` con el mismo `appstream_id` |

Notas, reseñas y precio no existen en ninguna fuente que usamos y no vienen.

## Métodos

| Método | Entrada | Salida | |
|---|---|---|---|
| `Buscar` | `s texto, as origenes, u limite` | `aa{sv}` | Resúmenes. `origenes` vacío = todos. AppStream (nombre, keywords, resumen); local, sin red |
| `Secciones` | — | `a(ssas)` | (id, clave de título, categorías de AppStream que reúne). Ver «Secciones» |
| `Categorias` | — | `a(ssas)` | Igual, para la lista de Categories |
| `ListarCategoria` | `s categoria, u desde, u limite` | `aa{sv}` | |
| `Estantes` | `s seccion` | `a(ssssaa{sv})` | (id, clave de título, tipo, fuente, apps). Ver «Estantes» |
| `Ficha` | `s id` | `a{sv}` | |
| `Instalar` | `s id` | `s trabajo` | Devuelve enseguida; lo demás va por señales |
| `Quitar` | `s id` | `s trabajo` | |
| `Actualizaciones` | — | `aa{sv}` | Resúmenes con `version` y `version_instalada` |
| `Actualizar` | `as ids` | `s trabajo` | `ids` vacío = todas |
| `Refrescar` | — | `s trabajo` | Catálogos de APT (PackageKit `RefreshCache`) y de Flatpak (appstream de cada remote) |
| `Cancelar` | `s trabajo` | `b` | false si ya no se puede (PackageKit no deja cancelar a mitad del dpkg) |
| `Trabajos` | — | `a(sssu)` | (trabajo, tipo, id, porcentaje): para reengancharse si la ventana se abrió después |

## Señales

| Señal | Argumentos | |
|---|---|---|
| `Progreso` | `s trabajo, u porcentaje, s etapa, t bytes_hechos, t bytes_total` | `etapa`: `esperando`, `autorizando`, `descargando`, `instalando`, `quitando`, `limpiando`. `porcentaje` = 101 cuando no se sabe |
| `Terminado` | `s trabajo, b ok, s codigo, s mensaje` | `codigo`: `""`, `cancelado`, `sin-autorizacion`, `sin-red`, `sin-espacio`, `ocupado` (otro gestor tiene el lock de dpkg), `fallo`. `mensaje` es el de la fuente, para el detalle |
| `InstaladasCambiaron` | `as ids` | también cuando la instalación la hizo otro programa |
| `ActualizacionesCambiaron` | — | |
| `IconoListo` | `s url, s ruta` | |

## Propiedades

| | | |
|---|---|---|
| `Origenes` | `a(ssb)` | (origen, nombre visible, disponible): `flatpak`, `apt` |
| `Ocupado` | `b` | |
| `UltimoRefresco` | `x` | unix |

## Autorización (sin sudo)

- APT: PackageKit pide `org.freedesktop.packagekit.package-install` (y `-remove`, `system-update`, `system-sources-refresh`) por polkit; el diálogo lo pone mac-polkit. El motor no toca polkit ni pide claves.
- Flatpak: en la instalación del remote. flathub está en **system**, así que instalar de flathub pasa por `flatpak-system-helper` y polkit también. El motor no añade un remote de usuario.

**Para la UI:** `Instalar`, `Quitar`, `Actualizar` y `Refrescar` pueden pedir la
clave. El diálogo lo pone mac-polkit, fuera de la ventana del App Store;
mientras tanto `Progreso` va con `etapa = autorizando`. Si la persona cancela
el diálogo, `Terminado` llega con `codigo = sin-autorizacion`: no es un error
que haya que enseñar en rojo, el botón vuelve a «Get».

## Secciones

Las de apps.apple.com/mac: Discover, Arcade, Create, Work, Play, Develop, Categories.

| Sección | Categorías de AppStream |
|---|---|
| `discover` | — (solo estantes) |
| `create` | Graphics, AudioVideo (Video, Audio, AudioVideoEditing, Recorder, Photography, 2DGraphics, 3DGraphics, VectorGraphics, Publishing) |
| `work` | Office, Finance, ProjectManagement, Presentation, Spreadsheet, WordProcessor, Calendar, ContactManagement, Email |
| `play` | Game (todas sus subcategorías) |
| `develop` | Development (IDE, Debugger, RevisionControl, WebDevelopment, Building, Profiling) |
| `arcade` | **no se ofrece**: no hay nada equivalente |

Categories, de la lista de Apple a la de freedesktop:

| Apple | AppStream | |
|---|---|---|
| Productivity | Office | |
| Finance | Finance | |
| Utilities | Utility, System | |
| News | News, Feed | pocas apps |
| Entertainment | Player, TV, Amusement | aproximado |
| Reference | Dictionary, Documentation, Education | |
| Lifestyle | — | **sin fuente** |
| Health & Fitness | — | Flathub tiene `healthfitness`, pero no es de freedesktop: solo apps de Flathub |
| Music | Audio, Music, Midi | |
| Games | Game | |
| Graphics & Design | Graphics | |
| Photography | Photography | |
| Video | Video | |
| Education | Education, Science | |
| Social Networking | InstantMessaging, Chat | |
| Developer Tools | Development | |

## Estantes

Cada estante dice su `fuente`. Si una fuente no responde (sin red), el estante
**no viene**: no se rellena con otra cosa.

| id | tipo | fuente | |
|---|---|---|---|
| `app-del-dia` | `destacada` | `flathub:/app-picks/app-of-the-day/{fecha}` | solo el app_id: la tarjeta lleva nombre, resumen y captura de su AppStream, sin texto editorial |
| `apps-de-la-semana` | `fila` | `flathub:/app-picks/apps-of-the-week/{fecha}` | |
| `populares` | `lista-numerada` | `flathub:/collection/popular` | instalaciones del último mes |
| `tendencia` | `lista-numerada` | `flathub:/collection/trending` | dos semanas |
| `nuevas` | `fila` | `flathub:/collection/recently-added` | |
| `actualizadas` | `fila` | `flathub:/collection/recently-updated` | |
| `selecciones` | `destacada` | `flathub:/app-picks/curated-app-selections/{fecha}` | hoy vino vacío; si trae título, es texto de Flathub |
| `populares-<seccion>` | `lista-numerada` | `flathub:/collection/category/{cat}` | en Create/Work/Play/Develop |
| `instaladas-actualizables` | `fila` | `local` | |

- En APT no hay ranking: los estantes son solo de Flathub, y una app de APT sale en búsqueda y categorías, no en estantes.
- Las respuestas de Flathub se guardan en caché 24 h (es lo que su CDN dice en `s-maxage`), en `~/.cache/mint-macos/tienda/`.
- «Top Paid», notas, reseñas y Arcade no tienen fuente y no se ofrecen.
- Tarjetas editoriales con texto propio (kicker, título y subtítulo): no hay fuente. Fuera, salvo que José decida otra cosa.

## Lo que el motor no hace

- No añade remotes ni repositorios, ni toca `/etc/apt`.
- No instala de un `.deb` o `.flatpakref` suelto (podría venir después, con la misma confirmación de Gatekeeper que las AppImages).
- No corre nada como root: todo pasa por PackageKit o por flatpak-system-helper.
