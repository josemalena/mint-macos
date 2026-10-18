# mint-macos-tienda: la interfaz D-Bus del App Store

El motor del App Store, sin ventana. Las pantallas (Dev-Dock, en Vala) hablan
solo con esta interfaz; el motor habla con PackageKit (APT) por D-Bus, con
libflatpak por una FFI mínima, y lee los catálogos de AppStream directo. No
llama a mintinstall ni lee nada suyo.

**Estado (18-10-2026): implementada e instalada** (`tienda/instalar.sh`, vuelta
atrás con `--quitar`). Pruebas: `rust/tienda/prueba.sh` (35 comprobaciones de punta
a punta en un bus aparte) y `rust/tienda/prueba-flatpak.sh` (libflatpak contra un
repo de juguete). La primera llamada tarda 0.43 s con el caché del índice
(`~/.cache/mint-macos/tienda/indice.json`) y 2.5 s sin él; las demás, unos 36 ms.

**Además de lo de abajo:** el Resumen trae `icono_tema` (el nombre del ícono en el
tema, cuando AppStream lo da) y, en el grupo `sistema`, `pk_id` (el id de PackageKit).
Los títulos de las secciones, categorías y estantes van en inglés, como en la Mac.

## Lo más cercano a la Mac (decisiones de José, 18-10-2026)

1. **Get sin clave:** Flathub está también como remote **de usuario**
   (`flatpak remote-add --user flathub`, hecho el 18-10). Los Flatpak se
   instalan en `~/.local/share/flatpak` sin polkit, como en la Mac.
2. **Una ficha por app, Flatpak primero:** si una app está en Flatpak y en APT
   (mismo `appstream_id`), sale la de Flatpak; la de APT va en `otras_fuentes`.
   APT solo sale sola cuando no hay Flatpak.
3. **Actualizaciones como en la Mac, partidas en dos:** las apps (Flatpak de
   usuario) se actualizan solas una vez al día, sin clave, si
   `com.linuxmint.updates auto-update-flatpaks` está encendido (la misma
   preferencia del panel; no se duplica). Lo demás va por Software Update.
4. **Notas y reseñas de ODRS** (odrs.gnome.org, la base abierta que usa GNOME
   Software), diciendo que salen de ahí; sin rellenar cuando no hay.

## De dónde salen los datos

| | Ruta en esta máquina (Mint 22.3) | Formato |
|---|---|---|
| Catálogo de APT | `/var/lib/swcatalog/yaml/*_dep11_Components-amd64.yml.gz` (las de Ubuntu; el repo de Mint no publica DEP-11) | DEP-11 YAML; íconos y capturas por URL relativa a `MediaBaseUrl` |
| Catálogo de Flathub | `/var/lib/flatpak/appstream/<remote>/x86_64/active/appstream.xml.gz` | AppStream XML; íconos en `active/icons/{64x64,128x128}` |
| Instalar con APT | PackageKit (`org.freedesktop.PackageKit`, bus de sistema) | D-Bus |
| Instalar con Flatpak | `libflatpak.so.0`: installation, transaction, add_install/add_uninstall/add_update, run y sus señales de progreso | FFI |
| Catálogo de Flathub (usuario) | `~/.local/share/flatpak/appstream/flathub/x86_64/active/appstream.xml.gz` | el mismo |
| Estantes | `https://flathub.org/api/v2/…` | JSON |
| Notas y reseñas | `https://odrs.gnome.org/1.0/reviews/api/ratings/{id}` y `…/fetch` | JSON |

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

- `flatpak:<instalación>/<remote>/<ref>` — p. ej. `flatpak:user/flathub/app/org.gimp.GIMP/x86_64/stable`. Lo nuevo se instala en `user`; lo que ya estaba en `system` se sigue viendo, actualizando y quitando ahí
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
| `nota` | d | promedio de 0 a 5 de ODRS (star1…star5); no viene si no hay votos |
| `votos` | u | `total` de ODRS |
| `votos_por_estrella` | au | cinco números, de 1 a 5 estrellas |
| `fuente_nota` | s | `odrs:/1.0/reviews/api/ratings/{id}` |

El precio no existe en ninguna fuente que usamos y no viene.

**Reseña** (`a{sv}`): `resumen` s, `texto` s, `nota` d (0 a 5), `autor` s
(`user_display`; no viene si es anónima), `fecha` x, `version` s, `distro` s.
Solo se leen: el motor no publica reseñas ni manda el `user_hash` de la máquina
(manda uno en ceros, que ODRS acepta para leer).

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
| `Resenas` | `s appstream_id, u limite` | `aa{sv}` | De ODRS, las más útiles primero (su `score`) |
| `Actualizaciones` | `s grupo` | `aa{sv}` | `grupo`: `apps` o `sistema` (ver «Las actualizaciones en dos»). Resúmenes con `version` y `version_instalada` |
| `Actualizar` | `s grupo, as ids` | `s trabajo` | `ids` vacío = todas las del grupo |
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

## Las actualizaciones en dos (como Catalina)

| grupo | qué entra | dónde se instala |
|---|---|---|
| `apps` | Flatpak (usuario y sistema) y los paquetes de APT que tienen ficha `desktop-application` en DEP-11 | Updates del App Store |
| `sistema` | todo lo demás de APT: núcleo, bibliotecas, Cinnamon… | Software Update (System Preferences), dentro del panel, con progreso |

Los núcleos y Timeshift se quedan en Update Manager (Advanced… en Software
Update).

### El salto de versión de Mint (grupo `sistema`)

Se **detecta con los archivos de Mint** y se **hace con las herramientas de
Mint**; el motor no reimplementa ningún salto (aprobado por Planner, 18-10-2026).

- Detección, la misma regla que los informes 070 y 071 de mintreport: el
  codename y la edición de `/etc/linuxmint/info`, y el paquete
  `mint-upgrade-info`. `/usr/share/mint-upgrade-info/<codename>/info` es un
  salto **menor** (22.2 → 22.3); `<codename>-major/info`, uno **mayor** (22 → 23,
  si la edición y la arquitectura están en la lista).
- Ejecución: el menor abre `mint-release-upgrade` (el asistente de Mint, con su
  pkexec). El mayor abre `mintupgrade`; si no está instalado, primero lo instala
  por PackageKit. El progreso lo enseña la herramienta de Mint, no el panel.
- **Nunca se corre un salto sin el sí de José**, ni para probar: las pruebas
  cubren solo la detección, con una raíz falsa.

| Método | Entrada | Salida | |
|---|---|---|---|
| `NuevaVersion` | — | `a{sv}` | Vacío si no hay salto. Si hay: `tipo` (`menor` o `mayor`), `nombre` («Linux Mint 23 …»), `codename`, `imagen` (el png de la edición, si viene), `enlace` (whatsnew en el menor, el blog en el mayor), `herramienta` (`mint-release-upgrade` o `mintupgrade`), `herramienta_instalada` b |
| `SubirVersion` | — | `s trabajo` | Abre la herramienta de Mint (antes instala `mintupgrade` si hace falta). `Terminado` llega cuando la herramienta se cierra; si hubo salto o no lo dice la herramienta, no el motor |

## Autorización

- APT: PackageKit pide `org.freedesktop.packagekit.package-install` (y `-remove`, `system-update`, `system-sources-refresh`) por polkit; el diálogo lo pone mac-polkit. El motor no toca polkit ni pide claves.
- Flatpak de usuario (lo nuevo): **sin clave**.
- Flatpak de sistema (lo que ya estaba): pasa por `flatpak-system-helper` y polkit.

**Para la UI:** `Instalar` de un Flatpak no pide nada. `Instalar` y `Quitar`
de APT, `Quitar` y `Actualizar` de un Flatpak de sistema, y `Refrescar`
pueden pedir la clave. El diálogo lo pone mac-polkit, fuera de la ventana del App Store;
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
- «Top Paid» y Arcade no tienen fuente y no se ofrecen.
- Tarjetas editoriales con texto propio (kicker, título y subtítulo): no hay fuente. Fuera, salvo que José decida otra cosa.

## Lo que el motor no hace

- No añade remotes ni repositorios, ni toca `/etc/apt` (el remote de usuario de Flathub lo puso Infra una vez, con el sí de José).
- No instala de un `.deb` o `.flatpakref` suelto (podría venir después, con la misma confirmación de Gatekeeper que las AppImages).
- No corre nada como root: todo pasa por PackageKit o por flatpak-system-helper.
